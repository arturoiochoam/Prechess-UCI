-------------------------------------------------------------------------------
--  PRECHESS UCI - MULTI-BUCKET TRANSPOSITION TABLE IMPLEMENTATION
--
--  Module:        TT_Table (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Layer & Transposition Engine)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Unchecked_Deallocation;

package body TT_Table is

   ----------------------------------------------------------------------------
   --  STORAGE TOPOLOGY: 1D CONTIGUOUS CLUSTER ARRAY
   ----------------------------------------------------------------------------
   --  Cluster `I` contains slots `(I * 4) .. (I * 4 + 3)`.
   ----------------------------------------------------------------------------
   type TT_Array is array (Hash_Key range <>) of TT_Entry;
   type TT_Array_Access is access TT_Array;

   procedure Free is new Ada.Unchecked_Deallocation (TT_Array, TT_Array_Access);

   Table          : TT_Array_Access := null;
   Num_Clusters   : Hash_Key := 1;
   Cluster_Mask   : Hash_Key := 0;
   Size_MB_Now    : Natural := 0;
   Generation_Now : Natural := 1;

   ----------------------------------------------------------------------------
   --  TELEMETRY COUNTERS & OCCUPANCY MONITOR
   ----------------------------------------------------------------------------
   Allocated_Slots          : Hash_Key          := 0;
   Active_Generation_Slots  : Hash_Key          := 0;
   Probes                   : Long_Long_Integer := 0;
   Stores                   : Long_Long_Integer := 0;
   Hits                     : Long_Long_Integer := 0;
   Misses                   : Long_Long_Integer := 0;
   Entry_Bytes     : constant Long_Long_Integer :=
     Long_Long_Integer ((TT_Array'Component_Size + 7) / 8);

   Empty_Move : constant Move_Type :=
     (From_Sq => 1, To_Sq => 1, Prom => 0);

   Empty_Entry : constant TT_Entry :=
     (Occupied   => False,
      Key        => 0,
      Depth      => 0,
      Score      => 0,
      Flag       => Exact,
      Best       => Empty_Move,
      Generation => 0);

   ----------------------------------------------------------------------------
   --  CLUSTER BASE ADDRESS COMPUTATION
   ----------------------------------------------------------------------------
   function Cluster_Base (Key : Hash_Key) return Hash_Key is
   begin
      return (Key and Cluster_Mask) * Hash_Key (Bucket_Count);
   end Cluster_Base;

   ----------------------------------------------------------------------------
   --  VICTIM EVICTION ARBITRATION (N2: Generation-Discounted Effective Depth)
   ----------------------------------------------------------------------------
   --  Compares two candidate slots to determine which is a "worse" (more evictable)
   --  victim according to generation-discounted depth and aging criteria.
   --
   --  Effective_Depth = Depth - 4 * (Generation_Now - Entry.Generation)
   --  1. Lower effective depth is evicted first.
   --  2. On equal effective depth, older generation is evicted first.
   ----------------------------------------------------------------------------
   function Effective_Depth (E : TT_Entry) return Integer is
      Gen_Diff : constant Integer :=
        (if Generation_Now >= E.Generation then
            Generation_Now - E.Generation
         else
            0);
   begin
      if not E.Occupied then
         return -1_000_000;
      end if;
      return E.Depth - 4 * Gen_Diff;
   end Effective_Depth;

   function Is_Worse_Victim (Candidate, Current : TT_Entry) return Boolean is
      Eff_Cand : constant Integer := Effective_Depth (Candidate);
      Eff_Curr : constant Integer := Effective_Depth (Current);
   begin
      if Eff_Cand < Eff_Curr then
         return True;
      end if;
      if Eff_Cand > Eff_Curr then
         return False;
      end if;
      return Candidate.Generation < Current.Generation;
   end Is_Worse_Victim;

   ----------------------------------------------------------------------------
   --  TABLE FLUSH & EPOCH ADVANCEMENT
   ----------------------------------------------------------------------------
   procedure New_Generation is
   begin
      if Generation_Now < Natural'Last then
         Generation_Now := Generation_Now + 1;
      else
         Generation_Now := 1;
         --  On generation wrap, age every retained entry once so entries from
         --  the previous epoch cannot compare equal to the fresh generation.
         if Table /= null then
            for I in Table'Range loop
               if Table (I).Occupied then
                  Table (I).Generation := 0;
               end if;
            end loop;
         end if;
      end if;
      Active_Generation_Slots := 0;
   end New_Generation;

   procedure Clear_TT is
   begin
      New_Generation;
      if Table = null then
         return;
      end if;
      Table.all := [others => Empty_Entry];
   end Clear_TT;

   ----------------------------------------------------------------------------
   --  DYNAMIC MEMORY ALLOCATION & RESIZING
   ----------------------------------------------------------------------------
   procedure Allocate (Size_MB : Natural) is
      Clamped       : constant Positive :=
        Natural'Max (Min_Size_MB, Natural'Min (Size_MB, Max_Size_MB));
      Bytes         : Long_Long_Integer;
      Cluster_Bytes : Long_Long_Integer;
      Raw_Clusters  : Hash_Key;
      Clusters      : Hash_Key := 1;
      Slots         : Hash_Key;
   begin
      if Table /= null and then Clamped = Size_MB_Now then
         Clear_TT;
         return;
      end if;

      Bytes := Long_Long_Integer (Clamped) * 1024 * 1024;
      Cluster_Bytes := Entry_Bytes * Long_Long_Integer (Bucket_Count);
      if Cluster_Bytes < 1 then
         Cluster_Bytes := 1;
      end if;

      Raw_Clusters := Hash_Key (Bytes / Cluster_Bytes);
      if Raw_Clusters < 1 then
         Raw_Clusters := 1;
      end if;

      --  Round down to largest power of two so Cluster_Base uses bitmasking.
      while Clusters <= Raw_Clusters / 2 loop
         Clusters := Clusters * 2;
      end loop;

      Slots := Clusters * Hash_Key (Bucket_Count);

      --  Free existing table before allocating the replacement so peak
      --  memory usage does not require Old + New simultaneously.
      if Table /= null then
         Free (Table);
         Table           := null;
         Allocated_Slots := 0;
         Num_Clusters    := 0;
         Cluster_Mask    := 0;
         Size_MB_Now     := 0;
      end if;

      begin
         Table := new TT_Array (0 .. Slots - 1);
      exception
         when Storage_Error =>
            Ada.Text_IO.Put_Line
              ("info string TT_Table allocation failed for" &
               Positive'Image (Clamped) & " MB (out of memory)");
            Table           := null;
            Allocated_Slots := 0;
            Num_Clusters    := 0;
            Cluster_Mask    := 0;
            Size_MB_Now     := 0;
            return;
      end;

      Allocated_Slots := Slots;
      Num_Clusters    := Clusters;
      Cluster_Mask    := Clusters - 1;
      Size_MB_Now     := Clamped;

      Clear_TT;
   end Allocate;

   procedure Init_TT (Size_MB : Natural) is
   begin
      Allocate (Size_MB);
   end Init_TT;

   procedure Resize_TT (Size_MB : Natural) is
   begin
      Allocate (Size_MB);
   end Resize_TT;

   function Current_Size_MB return Natural is
   begin
      if Table = null then
         return 0;
      end if;
      return Size_MB_Now;
   end Current_Size_MB;

   function Cluster_Count return Hash_Key is
   begin
      if Table = null then
         return 0;
      end if;
      return Num_Clusters;
   end Cluster_Count;

   ----------------------------------------------------------------------------
   --  TRANSACTION: STORE_TT
   ----------------------------------------------------------------------------
   procedure Store_TT
     (Key   : Hash_Key;
      Depth : Integer;
      Score : Score_Type;
      Flag  : TT_Flag;
      Best  : Move_Type)
   is
      Base    : Hash_Key;
      Slot    : Hash_Key;
      Victim  : Hash_Key;
      New_Ent : TT_Entry;
   begin
      Stores := Stores + 1;
      if Table = null then
         return;
      end if;

      Base := Cluster_Base (Key);
      New_Ent :=
        (Occupied   => True,
         Key        => Key,
         Depth      => Depth,
         Score      => Score,
         Flag       => Flag,
         Best       => Best,
         Generation => Generation_Now);

      --  Phase 1: Exact Key Refresh (Hit within cluster). Do not clobber a
      --  deeper current-generation proof with a shallower re-store; a stale
      --  generation may always be refreshed.
      for B in 0 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if Table (Slot).Occupied and then Table (Slot).Key = Key then
            if New_Ent.Depth >= Table (Slot).Depth
              or else Table (Slot).Generation /= Generation_Now
            then
               if Table (Slot).Generation /= Generation_Now then
                  Active_Generation_Slots := Active_Generation_Slots + 1;
               end if;
               Table (Slot) := New_Ent;
            end if;
            return;
         end if;
      end loop;

      --  Phase 2: Empty Slot Utilization
      for B in 0 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if not Table (Slot).Occupied then
            Active_Generation_Slots := Active_Generation_Slots + 1;
            Table (Slot) := New_Ent;
            return;
         end if;
      end loop;

      --  Phase 3: Victim Selection (Shallower Depth / Older Generation)
      Victim := Base;
      for B in 1 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if Is_Worse_Victim (Table (Slot), Table (Victim)) then
            Victim := Slot;
         end if;
      end loop;
      if Table (Victim).Generation /= Generation_Now then
         Active_Generation_Slots := Active_Generation_Slots + 1;
      end if;
      Table (Victim) := New_Ent;
   end Store_TT;

   ----------------------------------------------------------------------------
   --  TRANSACTION: PROBE_TT
   ----------------------------------------------------------------------------
   function Probe_TT (Key : Hash_Key; TT_Ent : out TT_Entry) return Boolean is
      Base : Hash_Key;
      Slot : Hash_Key;
   begin
      Probes := Probes + 1;
      if Table = null then
         TT_Ent := Empty_Entry;
         Misses := Misses + 1;
         return False;
      end if;

      Base := Cluster_Base (Key);
      for B in 0 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if Table (Slot).Occupied and then Table (Slot).Key = Key then
            TT_Ent := Table (Slot);
            Hits := Hits + 1;
            return True;
         end if;
      end loop;

      TT_Ent := Empty_Entry;
      Misses := Misses + 1;
      return False;
   end Probe_TT;

   ----------------------------------------------------------------------------
   --  TELEMETRY & METERING GETTERS
   ----------------------------------------------------------------------------
   procedure Reset_TT_Counters is
   begin
      Probes := 0;  Stores := 0;  Hits := 0;  Misses := 0;
   end Reset_TT_Counters;

   function TT_Probes return Long_Long_Integer is (Probes);
   function TT_Stores return Long_Long_Integer is (Stores);
   function TT_Hits   return Long_Long_Integer is (Hits);
   function TT_Misses return Long_Long_Integer is (Misses);

   function Current_Allocated_Bytes return Long_Long_Integer is
     (Long_Long_Integer (Allocated_Slots) * Entry_Bytes);

   ----------------------------------------------------------------------------
   --  UCI HASHFULL ACTIVE-GENERATION OCCUPANCY
   ----------------------------------------------------------------------------
   function Hash_Full_Permille return Integer is
   begin
      if Table = null or else Allocated_Slots = 0 then
         return 0;
      end if;

      if Active_Generation_Slots = 0 then
         return 0;
      end if;

      --  Any current-generation occupancy reports at least 1 permille, so a
      --  small search in a large table does not truncate to a misleading 0.
      return Integer'Min
        (1000,
         Integer'Max
           (1, Integer ((Active_Generation_Slots * 1000) / Allocated_Slots)));
   end Hash_Full_Permille;

end TT_Table;
