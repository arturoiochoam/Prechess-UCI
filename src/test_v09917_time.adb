-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17 TIME MANAGEMENT TEST SUITE (PHASE 6a)
--
--  Unit:          Test_V09917_Time
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
--     - Asserts budget does NOT collapse to 1 ms (evaluates to 20 ms).
--  3. Extreme Scramble Budget (wtime 50, no inc):
--     - Asserts 25% All-In cap takes precedence (12 ms).
--  4. Scramble with Increment (wtime 300, winc 100):
--     - Asserts proper calculation (80 ms).
--  5. 60s Blitz Budget (wtime 60000, no inc):
--     - Asserts normal budget calculation with dynamic overhead (800 ms).
--  6. Classical Tournament (wtime 120000, movestogo 40, no inc):
--     - Asserts tournament formula with dynamic overhead (600 ms).
--  7. Movetime (movetime 1000):
--     - Asserts unchanged movetime behavior (980 ms).
--  8. Fixed Depth & Infinite:
--     - Asserts unbounded clock allocation.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Time_Management;

procedure Test_V09917_Time is
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
   Put_Line ("=== V0.9.9.17 Time Management Test Suite ===");

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
   Check ("Bullet scramble budget does not collapse to 1 ms (Alloc = 20)",
          Alloc = 20);

   -- 3. Extreme scramble budget (wtime 50, no inc)
   Time_Management.Start_Search
     (WTime => 50, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Extreme scramble budget <= 25% cap (12 ms)",
          Alloc <= 12);
   Check ("Extreme scramble budget > 0 ms",
          Alloc > 0);

   -- 4. Scramble with increment (wtime 300, winc 100)
   Time_Management.Start_Search
     (WTime => 300, BTime => 0, WInc => 100, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Scramble with inc allocates target (Alloc = 80)",
          Alloc = 80);

   -- 5. 60s Blitz budget (wtime 60000, no inc)
   Time_Management.Start_Search
     (WTime => 60000, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("60s blitz allocates 800 ms (2000 - 1200)",
          Alloc = 800);

   -- 6. Classical tournament (wtime 120000, movestogo 40, no inc)
   Time_Management.Start_Search
     (WTime => 120000, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 40, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Tournament selects Tournament control",
          Time_Management.Current_Control = Time_Management.Tournament);
   Check ("Tournament allocates 600 ms (3000 - 2400)",
          Alloc = 600);

   -- 7. Movetime (movetime 1000)
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 1000, Depth => 0,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Movetime selects Time_Per_Move control",
          Time_Management.Current_Control = Time_Management.Time_Per_Move);
   Check ("Movetime allocates 970 ms (1000 - 30 default Move Overhead)",
          Alloc = 970);

   -- 8. Fixed Depth (depth 10)
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 10,
      Is_White => True, Infinite => False);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Depth selects Fixed_Depth control",
          Time_Management.Current_Control = Time_Management.Fixed_Depth);
   Check ("Depth allocates unbounded budget (Integer'Last)",
          Alloc = Integer'Last);

   -- 9. Infinite (infinite = True)
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => True);
   Alloc := Time_Management.Allocated_Ms;
   Check ("Infinite selects Infinite control",
          Time_Management.Current_Control = Time_Management.Infinite);
   Check ("Infinite allocates unbounded budget (Integer'Last)",
          Alloc = Integer'Last);

   New_Line;
   if Failures = 0 then
      Put_Line ("TEST_V09917_TIME: ALL PASS (18/18)");
   else
      Put_Line ("TEST_V09917_TIME: FAILURES =" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_V09917_Time;
