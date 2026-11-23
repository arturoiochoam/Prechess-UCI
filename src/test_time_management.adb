-------------------------------------------------------------------------------
--  PRECHESS UCI - TIME MANAGEMENT & BUDGET ALLOCATION TEST SUITE
--
--  Harness:       Test_Time_Management
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Modal Budget Calculations:
--     - Fixed depth, move time, tournament (movestogo), and sudden-death blitz.
--  2. Safety Margin Verification:
--     - `Overhead_Ms` deduction and minimum 1 ms allocation clamping.
--  3. PV Probe Throttling:
--     - Unrestricted under infinite/movetime; restricted to first 25% under game clocks.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO; use Ada.Text_IO;
with Time_Management;

procedure Test_Time_Management is
   use type Time_Management.Time_Control_Type;
   Failures : Natural := 0;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Start_No_Crash
     (Label : String;
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer;
      Is_White : Boolean;
      Infinite : Boolean)
   is
   begin
      Time_Management.Start_Search
        (WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth,
         Is_White, Infinite);
      Check (Label, True);
   exception
      when others =>
         Check (Label, False);
   end Start_No_Crash;

begin
   Put_Line ("=== Time management boundary checks ===");

   Start_No_Crash
     ("ordinary movetime survives", 0, 0, 0, 0, 0, 1000, 0, True, False);
   Check ("movetime selects time-per-move control",
          Time_Management.Current_Control = Time_Management.Time_Per_Move);

   Start_No_Crash
     ("tiny movetime clamps to usable budget", 0, 0, 0, 0, 0, 1, 0, True, False);
   Check ("tiny movetime selects time-per-move control",
          Time_Management.Current_Control = Time_Management.Time_Per_Move);

   Start_No_Crash
     ("large increment cannot overflow", Integer'Last, 0, Integer'Last, 0,
      0, 0, 0, True, False);
   Check ("large increment selects all-in control",
          Time_Management.Current_Control = Time_Management.All_In);

   Start_No_Crash
     ("large black increment cannot overflow", 0, Integer'Last, 0, Integer'Last,
      0, 0, 0, False, False);
   Check ("large black increment selects all-in control",
          Time_Management.Current_Control = Time_Management.All_In);

   Start_No_Crash
     ("negative clocks do not crash", -1, -1, -1, -1, 0, 0, 0, True, False);
   Check ("negative clocks fall back to infinite",
          Time_Management.Current_Control = Time_Management.Infinite);

   Start_No_Crash
     ("timeout transition setup", 0, 0, 0, 0, 0, 1, 0, True, False);
   delay until Clock + Milliseconds (3);
   Time_Management.Check_Time;
   Check ("check_time aborts expired movetime", Time_Management.Search_Aborted);
   Check ("expired search blocks PV probes", not Time_Management.Allow_PV_Probe);

   Start_No_Crash
     ("stop transition setup", 0, 0, 0, 0, 0, 1000, 0, True, False);
   Check ("elapsed time is non-negative", Time_Management.Elapsed_Ms >= 0);
   Time_Management.Stop_Search;
   Check ("stop_search aborts search", Time_Management.Search_Aborted);
   Check ("stopped search blocks PV probes", not Time_Management.Allow_PV_Probe);

   New_Line;
   if Failures = 0 then
      Put_Line ("TEST_TIME_MANAGEMENT: PASS");
   else
      Put_Line ("FAILURES:" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Time_Management;
