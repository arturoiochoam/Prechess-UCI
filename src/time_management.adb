-------------------------------------------------------------------------------
--  PRECHESS UCI - TIME CONTROL & SEARCH BUDGET MANAGEMENT
--
--  Module:        Time_Management (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Time Management Layer)
--  Date:          2026
-------------------------------------------------------------------------------

with TT_Types;

package body Time_Management is

   ----------------------------------------------------------------------------
   --  TIME BUDGET HEURISTICS & SAFETY MARGINS
   ----------------------------------------------------------------------------
   --  Assumed remaining moves for sudden death / blitz (no `movestogo`).
   Assumed_Moves_Remaining : constant := 30;

   --  Safety margin subtracted from budgets to absorb OS scheduler jitter,
   --  pipe I/O latency, and GUI message handling overhead (configurable via Move Overhead).
   Move_Overhead_Ms : Integer := Default_Move_Overhead_Ms;

   --  T2: Dynamic safety overhead scaling with remaining clock time.
   function Effective_Overhead_Ms (Time_Left_Ms : Long_Long_Integer) return Long_Long_Integer is
     (Long_Long_Integer'Max (Long_Long_Integer (Move_Overhead_Ms), Time_Left_Ms / 50));

   procedure Set_Move_Overhead (Ms : Integer) is
   begin
      if Ms < Min_Move_Overhead_Ms then
         Move_Overhead_Ms := Min_Move_Overhead_Ms;
      elsif Ms > Max_Move_Overhead_Ms then
         Move_Overhead_Ms := Max_Move_Overhead_Ms;
      else
         Move_Overhead_Ms := Ms;
      end if;
   end Set_Move_Overhead;

   function Move_Overhead return Integer is (Move_Overhead_Ms);

   --  Node count recorded at search start for relative node budget calculation.
   Search_Start_Nodes : Long_Long_Integer := 0;

   --  Saved bounded budget while a verification time slice is reserved.
   Slice_Active           : Boolean := False;
   Slice_Expired          : Boolean := False;
   Saved_Time_Allocated   : Time_Span := Time_Span_Last;
   Saved_Allocated_Budget : Integer := Integer'Last;

   ----------------------------------------------------------------------------
   --  NODE LIMIT CONTROLS
   ----------------------------------------------------------------------------
   procedure Set_Node_Limit (Limit : Long_Long_Integer) is
   begin
      Nodes_Limit := Limit;
   end Set_Node_Limit;

   function Node_Limit_Reached return Boolean is
   begin
      if Nodes_Limit > 0 and then (TT_Types.Nodes_Searched - Search_Start_Nodes) >= Nodes_Limit then
         return True;
      else
         return False;
      end if;
   end Node_Limit_Reached;

   ----------------------------------------------------------------------------
   --  SEARCH INITIALIZATION
   ----------------------------------------------------------------------------
   procedure Start_Search
     (WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer;
      Is_White : Boolean;
      Infinite : Boolean;
      Nodes    : Long_Long_Integer := 0)
   is
      Time_Left : Integer := 0;
      Inc       : Integer := 0;
   begin
      Search_Aborted     := False;
      Slice_Active       := False;
      Slice_Expired      := False;
      Search_Start_Time  := Clock;
      Search_Start_Nodes := TT_Types.Nodes_Searched;
      Requested_Depth    := Depth;
      Nodes_Limit        := Nodes;

      -- Modal Case 1: Infinite / Ponder search
      if Infinite then
         Current_Control     := Time_Management.Infinite;
         Time_Allocated      := Time_Span_Last;
         Allocated_Budget_Ms := Integer'Last;
         return;
      end if;

      -- Modal Case 2: Move Time (`go movetime T`), combinable with Depth/Nodes
      if Move_Time > 0 then
         Current_Control := Time_Per_Move;
         declare
            Target_Ms : Integer := Move_Time - Move_Overhead_Ms;
         begin
            if Target_Ms < 1 then
               Target_Ms := 1;
            end if;
            Allocated_Budget_Ms := Target_Ms;
            Time_Allocated      := Milliseconds (Target_Ms);
         end;
         return;
      end if;

      -- Modal Case 3: Classical Tournament or Sudden Death / Blitz (combinable with Depth/Nodes)
      if Is_White then
         Time_Left := WTime;
         Inc       := WInc;
      else
         Time_Left := BTime;
         Inc       := BInc;
      end if;

      if Time_Left > 0 or else WTime > 0 or else BTime > 0 or else WInc > 0 or else BInc > 0 then
         declare
            Moves_Est    : Integer;
            Time_Left_64 : constant Long_Long_Integer :=
              Long_Long_Integer'Max (0, Long_Long_Integer (Time_Left));
            Inc_64       : constant Long_Long_Integer :=
              Long_Long_Integer'Max (0, Long_Long_Integer (Inc));
            Overhead_64  : constant Long_Long_Integer :=
              Effective_Overhead_Ms (Time_Left_64);
            Max_Safe_64  : constant Long_Long_Integer :=
              Long_Long_Integer'Max (1, Time_Left_64 - Overhead_64);
            Target_64    : Long_Long_Integer;
            Max_64       : Long_Long_Integer;
            Target_Ms    : Integer;
         begin
            if Moves_To_Go > 0 then
               Current_Control := Tournament;
               Moves_Est := Moves_To_Go;
            else
               Current_Control := All_In;
               Moves_Est := Assumed_Moves_Remaining;
            end if;

            Target_64 :=
              (Time_Left_64 / Long_Long_Integer (Moves_Est))
              + Inc_64
              - Overhead_64;

            if Current_Control = All_In then
               --  T2: Scramble floor prevents 1 ms collapse in sudden-death scramble
               if Target_64 < Scramble_Budget_Floor then
                  Target_64 := Scramble_Budget_Floor;
               end if;
               --  T2: 25% All-In cap ensures reserve for remaining game
               Target_64 := Long_Long_Integer'Min (Target_64, Time_Left_64 / 4 + Inc_64);
            else
               --  Tournament: never commit more than 80% of the current clock.
               Max_64 := Max_Safe_64;
               if Max_64 > (Time_Left_64 * 4) / 5 then
                  Max_64 := (Time_Left_64 * 4) / 5;
               end if;
               if Target_64 > Max_64 then
                  Target_64 := Max_64;
               end if;
            end if;

            --  Anti-flagging ceiling: increment is credited AFTER moving, so never
            --  commit more than remaining clock balance minus safety overhead.
            if Target_64 > Max_Safe_64 then
               Target_64 := Max_Safe_64;
            end if;

            if Target_64 < 1 then
               Target_64 := 1;
            end if;

            if Target_64 > Long_Long_Integer (Integer'Last) then
               Target_Ms := Integer'Last;
            else
               Target_Ms := Integer (Target_64);
            end if;

            Allocated_Budget_Ms := Target_Ms;
            Time_Allocated      := Milliseconds (Target_Ms);
         end;
      elsif Depth > 0 then
         --  Fixed Depth without a time budget (`go depth N`)
         Current_Control     := Fixed_Depth;
         Time_Allocated      := Time_Span_Last;
         Allocated_Budget_Ms := Integer'Last;
      else
         Current_Control     := Time_Management.Infinite;
         Time_Allocated      := Time_Span_Last;
         Allocated_Budget_Ms := Integer'Last;
      end if;
   end Start_Search;

   ----------------------------------------------------------------------------
   --  PERIODIC POLLING & ABORT
   ----------------------------------------------------------------------------
   procedure Check_Time is
   begin
      if Search_Aborted then
         return;
      end if;
      if Node_Limit_Reached then
         Search_Aborted := True;
         return;
      end if;
      if Current_Control = Infinite or else Current_Control = Fixed_Depth then
         return;
      end if;
      if Clock - Search_Start_Time >= Time_Allocated then
         Search_Aborted := True;
         --  A reserved cascade slice is an internal budget boundary; restoring
         --  the full budget clears it, while user stop and node-limit aborts
         --  remain terminal for this go command.
         if Slice_Active then
            Slice_Expired := True;
         end if;
      end if;
   end Check_Time;

   procedure Stop_Search is
   begin
      Search_Aborted := True;
   end Stop_Search;

   ----------------------------------------------------------------------------
   --  ELAPSED DURATION & PV PROBE BUDGET CHECK
   ----------------------------------------------------------------------------
   function Elapsed_Ms return Integer is
      Elapsed_Span : constant Time_Span := Clock - Search_Start_Time;
   begin
      if Elapsed_Span <= Time_Span_Zero then
         return 0;
      end if;
      return Elapsed_Span / Milliseconds (1);
   end Elapsed_Ms;

   function Allocated_Ms return Integer is
   begin
      return Allocated_Budget_Ms;
   end Allocated_Ms;

   procedure Reserve_Time_Slice (Reserve_Ms : Integer) is
      Cascade_Ms : Integer;
   begin
      if Slice_Active
        or else Allocated_Budget_Ms = Integer'Last
        or else Current_Control in Infinite | Fixed_Depth
      then
         return;
      end if;
      Slice_Active           := True;
      Saved_Time_Allocated   := Time_Allocated;
      Saved_Allocated_Budget := Allocated_Budget_Ms;
      Cascade_Ms := Allocated_Budget_Ms - Reserve_Ms;
      if Cascade_Ms < 1 then
         Cascade_Ms := 1;
      end if;
      Allocated_Budget_Ms := Cascade_Ms;
      Time_Allocated      := Milliseconds (Cascade_Ms);
   end Reserve_Time_Slice;

   procedure Restore_Time_Slice is
   begin
      if not Slice_Active then
         return;
      end if;
      Time_Allocated      := Saved_Time_Allocated;
      Allocated_Budget_Ms := Saved_Allocated_Budget;
      Slice_Active        := False;
      if Slice_Expired then
         Search_Aborted := False;
         Slice_Expired  := False;
      end if;
   end Restore_Time_Slice;

   function Allow_PV_Probe return Boolean is
   begin
      if Search_Aborted then
         return False;
      end if;

      case Current_Control is
         when Infinite | Fixed_Depth =>
            return True;                      --  clock not a resource here
         when Time_Per_Move | Tournament | All_In =>
            --  T1: cosmetic PV probes must never hold back bestmove.
            --  At most the first 12.5 % of the budget (the old 25 %
            --  tournament cap tightened; movetime no longer waits out
            --  the full allotment).
            return (Clock - Search_Start_Time) * 8 <= Time_Allocated;
      end case;
   end Allow_PV_Probe;

end Time_Management;
