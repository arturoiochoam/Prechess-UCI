with Ada.Unchecked_Deallocation;

package body TT_Table is

   --  Flat storage: clusters of Bucket_Count consecutive entries.
   --  Cluster I holds slots (I * Bucket_Count) .. (I * Bucket_Count + Bucket_Count - 1).
   type TT_Array is array (Hash_Key range <>) of TT_Entry;
   type TT_Array_Access is access TT_Array;

   procedure Free is new Ada.Unchecked_Deallocation (TT_Array, TT_Array_Access);

   Table          : TT_Array_Access := null;
   Num_Clusters   : Hash_Key := 1;
   Size_MB_Now    : Positive := Default_Size_MB;
   Generation_Now : Natural := 1;

   --  P4 audit: allocated slot count + probe/store/hit/miss counters and the
   --  per-entry byte size. Pure instrumentation; no decision reads them.
   Allocated_Slots : Hash_Key          := 0;
   Probes          : Long_Long_Integer := 0;
   Stores          : Long_Long_Integer := 0;
   Hits            : Long_Long_Integer := 0;
   Misses          : Long_Long_Integer := 0;
   Entry_Bytes     : constant Long_Long_Integer :=
     Long_Long_Integer (TT_Entry'Size + 7) / 8;

   --  Occupied-bucket count backing the UCI `hashfull` metric. Incremented
   --  only on Store_TT's empty-bucket-fill path (an exact-key refresh or a
   --  replace-victim store writes into an already-occupied bucket, so neither
   --  changes occupancy); reset in Clear_TT. Exact and O(1): buckets are never
   --  individually un-occupied except by a full clear, so the running count
   --  equals a full scan at all times.
   Occupied_Count  : Long_Long_Integer := 0;

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

   function Cluster_Base (Key : Hash_Key) return Hash_Key is
   begin
      return (Key mod Num_Clusters) * Hash_Key (Bucket_Count);
   end Cluster_Base;

   --  Prefer shallower depth; on equal depth prefer older generation
   --  (or Generation = 0 for an empty slot, which never reaches here).
   function Is_Worse_Victim (Candidate, Current : TT_Entry) return Boolean is
   begin
      if Candidate.Depth < Current.Depth then
         return True;
      end if;
      if Candidate.Depth > Current.Depth then
         return False;
      end if;
      return Candidate.Generation < Current.Generation;
   end Is_Worse_Victim;

   procedure Clear_TT is
   begin
      if Generation_Now < Natural'Last then
         Generation_Now := Generation_Now + 1;
      else
         Generation_Now := 1;
      end if;

      Occupied_Count := 0;
      if Table = null then
         return;
      end if;
      for I in Table'Range loop
         Table (I) := Empty_Entry;
      end loop;
   end Clear_TT;

   procedure Allocate (Size_MB : Positive) is
      Clamped       : Positive := Size_MB;
      Bytes         : Long_Long_Integer;
      Cluster_Bytes : Long_Long_Integer;
      Clusters      : Hash_Key;
      Slots         : Hash_Key;
      Old           : TT_Array_Access := Table;
   begin
      if Clamped < Min_Size_MB then Clamped := Min_Size_MB; end if;
      if Clamped > Max_Size_MB then Clamped := Max_Size_MB; end if;

      Bytes := Long_Long_Integer (Clamped) * 1024 * 1024;
      Cluster_Bytes := Entry_Bytes * Long_Long_Integer (Bucket_Count);
      if Cluster_Bytes < 1 then
         Cluster_Bytes := 1;
      end if;

      Clusters := Hash_Key (Bytes / Cluster_Bytes);
      if Clusters < 1 then
         Clusters := 1;
      end if;

      Slots := Clusters * Hash_Key (Bucket_Count);

      begin
         Table := new TT_Array (0 .. Slots - 1);
      exception
         when Storage_Error =>
            return;
      end;

      Allocated_Slots := Slots;
      Num_Clusters := Clusters;
      Size_MB_Now  := Clamped;

      if Old /= null then
         Free (Old);
      end if;

      Clear_TT;
   end Allocate;

   procedure Init_TT (Size_MB : Positive) is
   begin
      Allocate (Size_MB);
   end Init_TT;

   procedure Resize_TT (Size_MB : Positive) is
   begin
      Allocate (Size_MB);
   end Resize_TT;

   function Current_Size_MB return Positive is
   begin
      return Size_MB_Now;
   end Current_Size_MB;

   procedure Store_TT (Key   : Hash_Key;
                       Depth : Integer;
                       Score : Score_Type;
                       Flag  : TT_Flag;
                       Best  : Move_Type) is
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

      --  1) Exact key already in the cluster: refresh that bucket.
      for B in 0 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if Table (Slot).Occupied and then Table (Slot).Key = Key then
            Table (Slot) := New_Ent;
            return;
         end if;
      end loop;

      --  2) Prefer an empty bucket.
      for B in 0 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if not Table (Slot).Occupied then
            Table (Slot) := New_Ent;
            Occupied_Count := Occupied_Count + 1;
            return;
         end if;
      end loop;

      --  3) Replace shallowest / oldest-generation victim.
      Victim := Base;
      for B in 1 .. Bucket_Count - 1 loop
         Slot := Base + Hash_Key (B);
         if Is_Worse_Victim (Table (Slot), Table (Victim)) then
            Victim := Slot;
         end if;
      end loop;
      Table (Victim) := New_Ent;
   end Store_TT;

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

   function Hash_Full_Permille return Integer is
      Per_Mille : Long_Long_Integer;
   begin
      if Allocated_Slots = 0 or else Table = null then
         return 0;
      end if;
      Per_Mille := Occupied_Count * 1000 / Long_Long_Integer (Allocated_Slots);
      if Per_Mille > 1000 then
         Per_Mille := 1000;
      end if;
      return Integer (Per_Mille);
   end Hash_Full_Permille;

end TT_Table;
