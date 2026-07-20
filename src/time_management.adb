package body Time_Management is

   --  Sudden-death (All_In / "blitz") heuristic: with no movestogo, the
   --  clock is not going to be replenished, so assume this many moves
   --  remain and budget accordingly. A common, simple, documented
   --  constant -- not a tuned/opaque magic number.
   Assumed_Moves_Remaining : constant := 30;

   --  Safety margin subtracted from every time budget so the engine
   --  reliably hands control back to the GUI before its deadline,
   --  covering UCI I/O and process-scheduling overhead.
   Overhead_Ms : constant := 20;

   procedure Start_Search (
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer;
      Is_White : Boolean;
      Infinite : Boolean
   ) is
      Time_Left : Integer := 0;
      Inc       : Integer := 0;
   begin
      Search_Aborted := False;
      Search_Start_Time := Clock;
      Requested_Depth := Depth;

      if Infinite then
         Current_Control := Time_Management.Infinite;
         Time_Allocated := Time_Span_Last;
         return;
      end if;

      if Depth > 0 then
         Current_Control := Fixed_Depth;
         Time_Allocated := Time_Span_Last;
         return;
      end if;

      if Move_Time > 0 then
         Current_Control := Time_Per_Move;
         declare
            Target_Ms : Integer := Move_Time - Overhead_Ms;
         begin
            if Target_Ms < 1 then
               Target_Ms := 1;
            end if;
            Time_Allocated := Milliseconds (Target_Ms);
         end;
         return;
      end if;

      if Is_White then
         Time_Left := WTime;
         Inc := WInc;
      else
         Time_Left := BTime;
         Inc := BInc;
      end if;

      if Time_Left > 0 then
         declare
            Moves_Est : Integer;
            Target_Ms : Integer;
         begin
            if Moves_To_Go > 0 then
               Current_Control := Tournament; -- classical "N moves in X minutes"
               Moves_Est := Moves_To_Go;
            else
               Current_Control := All_In; -- sudden death / blitz
               Moves_Est := Assumed_Moves_Remaining;
            end if;

            Target_Ms := (Time_Left / Moves_Est) + Inc - Overhead_Ms;

            --  Never allocate more than is actually left on the clock.
            if Target_Ms > Time_Left - Overhead_Ms then
               Target_Ms := Time_Left - Overhead_Ms;
            end if;
            if Target_Ms < 1 then
               Target_Ms := 1;
            end if;

            Time_Allocated := Milliseconds (Target_Ms);
         end;
      else
         Current_Control := Time_Management.Infinite;
         Time_Allocated := Time_Span_Last;
      end if;
   end Start_Search;

   procedure Check_Time is
   begin
      if Search_Aborted then
         return;
      end if;

      if Current_Control /= Infinite and then Current_Control /= Fixed_Depth then
         if Clock - Search_Start_Time > Time_Allocated then
            Search_Aborted := True;
         end if;
      end if;
   end Check_Time;

   procedure Stop_Search is
   begin
      Search_Aborted := True;
   end Stop_Search;

   function Elapsed_Ms return Integer is
      Span : constant Time_Span := Clock - Search_Start_Time;
   begin
      return Integer (To_Duration (Span) * 1000);
   end Elapsed_Ms;

   function Allow_PV_Probe return Boolean is
   begin
      if Search_Aborted then
         return False;
      end if;
      case Current_Control is
         when Infinite | Fixed_Depth | Time_Per_Move =>
            --  This time is explicitly ours ("go infinite"/"go depth"
            --  never deadline; "go movetime N" grants N ms to spend):
            --  probe freely -- the probes themselves still self-abort
            --  through Check_Time when a movetime budget runs out.
            return True;
         when Tournament | All_In =>
            --  Real game clock: cosmetics only inside the first quarter
            --  of the allocated span.
            return (Clock - Search_Start_Time) * 4 <= Time_Allocated;
      end case;
   end Allow_PV_Probe;

end Time_Management;
