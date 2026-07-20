with Ada.Unchecked_Deallocation;

package body TT_Table is

   type TT_Array is array (Hash_Key range <>) of TT_Entry;
   type TT_Array_Access is access TT_Array;

   procedure Free is new Ada.Unchecked_Deallocation (TT_Array, TT_Array_Access);

   Table       : TT_Array_Access := null;
   Num_Entries : Hash_Key := 1;
   Size_MB_Now : Positive := Default_Size_MB;

   Empty_Entry : constant TT_Entry :=
     (Key   => 0,
      Depth => 0,
      Score => 0,
      Flag  => Exact,
      Best  => (From_Sq => 1, To_Sq => 1, Prom => 0));

   procedure Clear_TT is
   begin
      if Table = null then
         return;
      end if;
      for I in Table'Range loop
         Table (I) := Empty_Entry;
      end loop;
   end Clear_TT;

   procedure Allocate (Size_MB : Positive) is
      Clamped     : Positive := Size_MB;
      Bytes       : Long_Long_Integer;
      Entry_Bytes : constant Long_Long_Integer :=
        Long_Long_Integer (TT_Entry'Size + 7) / 8;
      Count : Hash_Key;
      Old   : TT_Array_Access := Table;
   begin
      if Clamped < Min_Size_MB then Clamped := Min_Size_MB; end if;
      if Clamped > Max_Size_MB then Clamped := Max_Size_MB; end if;

      Bytes := Long_Long_Integer (Clamped) * 1024 * 1024;
      Count := Hash_Key (Bytes / Entry_Bytes);
      if Count < 1 then
         Count := 1;
      end if;

      --  Allocate-then-free (never free-then-allocate): if the new
      --  allocation raises Storage_Error -- e.g. "setoption name Hash
      --  value 4096" on a machine without 4 GB to spare -- the old
      --  table is still intact and still installed, so the engine
      --  keeps running at its previous size instead of dying on an
      --  unhandled exception mid-session.
      begin
         Table := new TT_Array (0 .. Count - 1);
      exception
         when Storage_Error =>
            return; -- keep Old table, Num_Entries and Size_MB_Now as-is
      end;
      Num_Entries := Count;
      Size_MB_Now := Clamped;

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
      Index : Hash_Key;
   begin
      if Table = null then
         return;
      end if;
      Index := Key mod Num_Entries;
      Table (Index) := (Key => Key, Depth => Depth, Score => Score, Flag => Flag, Best => Best);
   end Store_TT;

   function Probe_TT (Key : Hash_Key; TT_Ent : out TT_Entry) return Boolean is
      Index : Hash_Key;
   begin
      if Table = null then
         TT_Ent := Empty_Entry;
         return False;
      end if;
      Index := Key mod Num_Entries;
      TT_Ent := Table (Index);
      return TT_Ent.Key = Key; -- one array read, not two
   end Probe_TT;

end TT_Table;
