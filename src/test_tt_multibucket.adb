with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with TT_Table;
with TT_Types; use TT_Types;

--  Gate for the multi-bucket transposition table (v0.7.9.2).
--  Verifies: same-cluster coexistence, exact-key refresh, shallow victim
--  replacement, and Probe miss after Clear_TT. Does not touch the legacy
--  search cascade.
procedure Test_TT_Multibucket is
   Failed : Natural := 0;

   procedure Expect (Cond : Boolean; Msg : String) is
   begin
      if not Cond then
         Failed := Failed + 1;
         Put_Line ("FAIL: " & Msg);
      else
         Put_Line ("PASS: " & Msg);
      end if;
   end Expect;

   function Mk_Move (F, T : Integer) return Move_Type is
   begin
      return (From_Sq => F, To_Sq => T, Prom => 0);
   end Mk_Move;

   --  Keys that collide into the same cluster once Num_Clusters is known
   --  after Init. Cluster index = Key mod Num_Clusters; we force collisions
   --  by using K, K+N, K+2N, K+3N, K+4N for cluster width 4.
   N : Hash_Key;
   K0, K1, K2, K3, K4 : Hash_Key;
   Ent : TT_Entry;
   Hit : Boolean;
begin
   TT_Table.Init_TT (1);

   --  After Init_TT(1), table has at least one cluster. Recover N by
   --  storing and probing with synthetic keys: we need Num_Clusters.
   --  Public API does not expose Num_Clusters; instead pick a dense set
   --  of consecutive keys and verify that at least Bucket_Count distinct
   --  keys remain simultaneously when they share an index pattern.
   --
   --  Practical approach: store Bucket_Count + 1 keys of the form
   --  Base + I * Step where Step is large enough that they map to the
   --  same cluster for any power-of-layout. With cluster index =
   --  Key mod Num_Clusters, keys that differ by Num_Clusters collide.
   --  We do not know Num_Clusters; so store many keys with the SAME
   --  low bits by using multiples. Simpler gate: store 4 distinct keys
   --  that are engineered as K + I (I in 0..3) after forcing a tiny
   --  table... Actually with Num_Clusters >= 1, keys 0,1,2,3 go to
   --  different clusters when Num_Clusters > 3. For 1 MB the cluster
   --  count is huge, so consecutive keys do NOT collide.
   --
   --  Force same-cluster keys: store Key = I * M for a fixed M by
   --  probing cluster membership indirectly. Easiest correct test:
   --  Resize to minimum, then use keys of the form Seed + I * Stride
   --  where Stride is found by scanning — overkill.
   --
   --  Clean approach used here: the table indexes by
   --  (Key mod Num_Clusters). We cannot read Num_Clusters, but we CAN
   --  store under key X and then store under keys X+1, X+2, ... until
   --  a later store of a fifth key that shares X's cluster displaces the
   --  shallowest among a deliberately prepared same-cluster set.
   --
   --  Construct same-cluster set without knowing N:
   --  Pick Base = 0. Store under 0. For Candidate in 1 .. large, Probe
   --  is not enough. Instead: allocate with Init already done; use the
   --  fact that for ANY Num_Clusters C, the keys 0, C, 2C, 3C, 4C all
   --  share cluster 0. We discover C by noting that after filling 4
   --  buckets at cluster 0, the 5th same-cluster key replaces depth-min.
   --
   --  Discover C: binary search is unnecessary. Clear, then for C_Try
   --  in a geometric search... Simpler: expose nothing; use a known
   --  property of Allocate: with Size_MB=1, Clusters = Bytes/Cluster_Bytes
   --  which is large. We can compute the same formula locally for the test.

   declare
      Entry_Bytes : constant Long_Long_Integer :=
        Long_Long_Integer (TT_Entry'Size + 7) / 8;
      Cluster_Bytes : constant Long_Long_Integer :=
        Entry_Bytes * Long_Long_Integer (TT_Table.Bucket_Count);
      Clusters : constant Hash_Key :=
        Hash_Key ((1024 * 1024) / Cluster_Bytes);
   begin
      N := Clusters;
      if N < 1 then
         N := 1;
      end if;
   end;

   K0 := 0;
   K1 := N;
   K2 := 2 * N;
   K3 := 3 * N;
   K4 := 4 * N;

   TT_Table.Clear_TT;

   TT_Table.Store_TT (K0, 1, 10, Exact, Mk_Move (1, 2));
   TT_Table.Store_TT (K1, 2, 20, Exact, Mk_Move (3, 4));
   TT_Table.Store_TT (K2, 3, 30, Exact, Mk_Move (5, 6));
   TT_Table.Store_TT (K3, 4, 40, Exact, Mk_Move (7, 8));

   Hit := TT_Table.Probe_TT (K0, Ent);
   Expect (Hit and then Ent.Best.From_Sq = 1, "bucket0 retained after 4 stores");
   Hit := TT_Table.Probe_TT (K1, Ent);
   Expect (Hit and then Ent.Depth = 2, "bucket1 retained (depth 2)");
   Hit := TT_Table.Probe_TT (K2, Ent);
   Expect (Hit and then Ent.Depth = 3, "bucket2 retained (depth 3)");
   Hit := TT_Table.Probe_TT (K3, Ent);
   Expect (Hit and then Ent.Depth = 4, "bucket3 retained (depth 4)");

   --  Fifth same-cluster store must replace the shallowest (K0, depth 1).
   TT_Table.Store_TT (K4, 5, 50, Exact, Mk_Move (9, 10));
   Hit := TT_Table.Probe_TT (K0, Ent);
   Expect (not Hit, "shallowest (K0) replaced by fifth store");
   Hit := TT_Table.Probe_TT (K4, Ent);
   Expect (Hit and then Ent.Depth = 5, "K4 occupies a bucket");
   Hit := TT_Table.Probe_TT (K3, Ent);
   Expect (Hit and then Ent.Depth = 4, "deepest prior entry still present");

   --  Exact-key refresh keeps the same key and updates depth/move.
   TT_Table.Store_TT (K4, 9, 99, Exact, Mk_Move (11, 12));
   Hit := TT_Table.Probe_TT (K4, Ent);
   Expect (Hit and then Ent.Depth = 9 and then Ent.Best.From_Sq = 11,
           "exact-key refresh updates depth and move");

   TT_Table.Clear_TT;
   Hit := TT_Table.Probe_TT (K4, Ent);
   Expect (not Hit, "Clear_TT drops all entries");

   --  Key = 0 must not falsely hit empty slots (Occupied flag).
   Hit := TT_Table.Probe_TT (0, Ent);
   Expect (not Hit, "Probe_TT(0) after Clear is a miss");
   TT_Table.Store_TT (0, 2, 0, Exact, Mk_Move (2, 3));
   Hit := TT_Table.Probe_TT (0, Ent);
   Expect (Hit and then Ent.Best.From_Sq = 2, "real Key=0 store is probeable");

   if Failed = 0 then
      Put_Line ("TEST_TT_MULTIBUCKET: PASS");
   else
      Put_Line ("TEST_TT_MULTIBUCKET: FAIL count =" & Natural'Image (Failed));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_TT_Multibucket;
