with TT_Types; use TT_Types;

package TT_Table is

   Min_Size_MB     : constant := 1;
   Max_Size_MB     : constant := 4096;
   Default_Size_MB : constant := 16;

   --  Entries sharing one cluster index. Probe scans all buckets; Store
   --  replaces by exact-key refresh, else empty, else shallowest depth.
   --  Cluster width is an implementation constant of the table layout.
   Bucket_Count : constant := 4;

   --  Allocates the table for the first time (called once at startup).
   procedure Init_TT (Size_MB : Positive);

   --  Reallocates the table to a new size in megabytes, clamped to
   --  Min_Size_MB .. Max_Size_MB, and clears it. This is exactly the
   --  UCI "setoption name Hash value N" entry point: safe to call any
   --  time the engine is not in the middle of a search (this engine is
   --  single-threaded and processes one UCI command at a time, so
   --  "setoption" between "go" and "bestmove" cannot happen), and the
   --  new size takes effect for every subsequent Store_TT / Probe_TT
   --  call everywhere in the engine.
   procedure Resize_TT (Size_MB : Positive);

   function Current_Size_MB return Positive;

   --  Full zero of every slot and a generation bump. Called from
   --  ucinewgame so a new game never reuses stale PV-probe hits.
   procedure Clear_TT;

   procedure Store_TT (Key   : Hash_Key;
                       Depth : Integer;
                       Score : Score_Type;
                       Flag  : TT_Flag;
                       Best  : Move_Type);

   function Probe_TT (Key : Hash_Key; TT_Ent : out TT_Entry) return Boolean;

   --  P4 audit instrumentation. The TT is a PV-extension cache, not a search
   --  table (the legacy cascade never probes/stores). These counters observe
   --  real traffic on the PV-probe path; no decision reads them. Purely
   --  additive, zero runtime cost beyond the increment.
   procedure Reset_TT_Counters;
   function TT_Probes               return Long_Long_Integer;
   function TT_Stores               return Long_Long_Integer;
   function TT_Hits                 return Long_Long_Integer;
   function TT_Misses               return Long_Long_Integer;

   --  Bytes actually allocated (Slots * entry size), <= the requested MB
   --  because allocation rounds down to whole clusters. For the N6 gate.
   function Current_Allocated_Bytes return Long_Long_Integer;

   --  Per-mille (0 .. 1000) of the table's buckets currently occupied, for the
   --  UCI `info ... hashfull N` field. Backed by an exact O(1) running counter
   --  (incremented on the empty-bucket-fill path of Store_TT, reset in
   --  Clear_TT); no scanning.
   function Hash_Full_Permille return Integer;

end TT_Table;
