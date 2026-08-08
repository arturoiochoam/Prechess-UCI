with Ada.Real_Time; use Ada.Real_Time;

package Time_Management is

   --  UCI time-control shapes. Tournament and All_In are structurally
   --  identical UCI input (wtime/btime[/winc/binc], optionally with
   --  movestogo) -- "blitz" is simply an All_In game played with a
   --  short clock, not a distinct protocol shape, so it is not given a
   --  separate value here; it is documented in README_UCI.md.
   type Time_Control_Type is (Fixed_Depth, Time_Per_Move, Tournament, All_In, Infinite);

   Search_Start_Time : Time := Clock;
   Time_Allocated    : Time_Span := Time_Span_Last;
   Current_Control   : Time_Control_Type := Infinite;

   --  Depth requested by "go depth N". The legacy core is structurally
   --  fixed at 3 plies and cannot be deepened or shortened on demand
   --  (see README_UCI.md, "Architectural limitations"); this is kept so
   --  the UCI front end can report an honest "depth" figure rather than
   --  a fabricated one when N < 3.
   Requested_Depth : Integer := 0;

   Search_Aborted : Boolean := False;

   --  Call this on "go" to initialize time management for the search
   --  that is about to start.
   procedure Start_Search (
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer;
      Is_White : Boolean;
      Infinite : Boolean
   );

   --  Call this periodically (the legacy Mate/Mate_ele2 inner loops
   --  already do) to check whether the allocated time has run out.
   procedure Check_Time;

   --  Abort the search explicitly (UCI "stop").
   procedure Stop_Search;

   --  Milliseconds elapsed since Start_Search was last called. Feeds
   --  the UCI "time"/"nps" live-info fields.
   function Elapsed_Ms return Integer;

   --  Whether starting another PV-extension probe search (see
   --  Prechess_UCI's Handle_Go) is reasonable right now. Probes are
   --  display polish: under "go infinite", "go depth" and
   --  "go movetime" the time is explicitly ours to use, so probes may
   --  fill the remaining budget; under real game clocks (wtime/btime,
   --  with or without movestogo) they are allowed only inside the
   --  first quarter of the allocated span, so the engine keeps its
   --  habit of moving quickly instead of burning clock on cosmetics.
   --  Always False once the search has been aborted.
   function Allow_PV_Probe return Boolean;

end Time_Management;
