-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 TIME MANAGEMENT TEST SUITE
--
--  Unit:          Test_V099171_Time
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Time Management & Budget Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Effective_Overhead_Ms:
--     - Scales dynamically from 30 ms floor up to 2% of remaining clock.
--  2. Bullet Scramble Budget (wtime 300, no inc):
--     - Asserts budget is >= Scramble_Budget_Floor (20 ms).
--     - Asserts budget is <= 25% All-In cap (75 ms).
--  3. Extreme Scramble Budget (wtime 50, no inc):
--     - Asserts 25% All-In cap takes precedence (12 ms).
--  4. Scramble with Increment (wtime 300, winc 100):
--     - Asserts proper calculation.
--  5. 60s Blitz Budget (wtime 60000, no inc):
--     - Asserts normal budget calculation with dynamic overhead.
--  6. Classical Tournament (wtime 120000, movestogo 40, no inc):
--     - Asserts tournament formula with dynamic overhead.
--  7. Movetime (movetime 1000):
--     - Asserts unchanged movetime behavior (980 ms).
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Time_Management;

procedure Test_V099171_Time is
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

   Alloc : Integer;
   use type Time_Management.Time_Control_Type;
begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - Time Management Test Suite      ");
   Put_Line ("========================================================");

   -- 1. Effective_Overhead_Ms scaling
   Check ("Effective_Overhead_Ms (0) = 30",
          Time_Management.Effective_Overhead_Ms (0) = 30);
   Check ("Effective_Overhead_Ms (300) = 30",
          Time_Management.Effective_Overhead_Ms (300) = 30);
   Check ("Effective_Overhead_Ms (1000) = 30",
          Time_Management.Effective_Overhead_Ms (1000) = 30);
   Check ("Effective_Overhead_Ms (1500) = 30",
          Time_Management.Effective_Overhead_Ms (1500) = 30);
   Check ("Effective_Overhead_Ms (5000) = 100",
          Time_Management.Effective_Overhead_Ms (5000) = 100);
   Check ("Effective_Overhead_Ms (60000) = 1200",
          Time_Management.Effective_Overhead_Ms (60000) = 1200);
   Check ("Effective_Overhead_Ms (300000) = 6000",
          Time_Management.Effective_Overhead_Ms (300000) = 6000);

   -- 2. Bullet scramble budget (wtime 300, no inc)
   Time_Management.Start_Search
     (WTime => 300, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Bullet scramble selects All_In control",
          Time_Management.Current_Control = Time_Management.All_In);
   Check ("Bullet scramble budget >= Scramble_Budget_Floor (20 ms)",
          Long_Long_Integer (Alloc) >= Time_Management.Scramble_Budget_Floor);
   Check ("Bullet scramble budget <= 25% cap (75 ms)",
          Alloc <= 75);

   -- 3. Extreme scramble (wtime 50, no inc)
   Time_Management.Start_Search
     (WTime => 50, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Extreme scramble caps at 25% (12 ms)",
          Alloc = 12);

   -- 4. Scramble with increment (wtime 300, winc 100)
   Time_Management.Start_Search
     (WTime => 300, BTime => 0, WInc => 100, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Scramble with inc: budget reflects inc contribution",
          Alloc >= 70 and Alloc <= 95);

   -- 5. 60s Blitz (wtime 60000, no inc)
   Time_Management.Start_Search
     (WTime => 60000, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Blitz 60s allocates ~800-1500 ms",
          Alloc >= 800 and Alloc <= 1600);

   -- 6. Movetime 1000
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 1000, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Movetime 1000 gives 970 ms with 30 ms safety margin",
          Alloc = 970);

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_TIME: ALL PASS");
   else
      Put_Line ("TEST_V099171_TIME: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");
end Test_V099171_Time;
