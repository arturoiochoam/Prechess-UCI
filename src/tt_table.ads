with TT_Types; use TT_Types;

package TT_Table is

   Min_Size_MB     : constant := 1;
   Max_Size_MB     : constant := 4096;
   Default_Size_MB : constant := 16;

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

   procedure Clear_TT;

   procedure Store_TT (Key   : Hash_Key;
                       Depth : Integer;
                       Score : Score_Type;
                       Flag  : TT_Flag;
                       Best  : Move_Type);

   function Probe_TT (Key : Hash_Key; TT_Ent : out TT_Entry) return Boolean;

end TT_Table;
