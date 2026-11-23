-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.17 INCREMENT & SLICE RESERVATION TEST SUITE
--
--  Unit:          Test_V0991717_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Time_Management; use Time_Management;

procedure Test_V0991717_Suite is

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

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.17 - Increment & Slice Suite        ");
   Put_Line ("========================================================");

   -- 1. Test Fischer Increment Scaling:
   --    Budget with increment (180s + 3s) must be strictly greater than without increment (180s + 0s).
   Put_Line ("[1/4] Testing Fischer Increment Scaling (180s + 3s vs 180s + 0s)...");
   declare
      Budget_No_Inc   : Integer;
      Budget_With_Inc : Integer;
   begin
      Time_Management.Start_Search
        (WTime       => 180_000,
         BTime       => 180_000,
         WInc        => 0,
         BInc        => 0,
         Moves_To_Go => 0,
         Move_Time   => 0,
         Depth       => 0,
         Is_White    => True,
         Infinite    => False);
      Budget_No_Inc := Time_Management.Allocated_Ms;

      Time_Management.Start_Search
        (WTime       => 180_000,
         BTime       => 180_000,
         WInc        => 3_000,
         BInc        => 3_000,
         Moves_To_Go => 0,
         Move_Time   => 0,
         Depth       => 0,
         Is_White    => True,
         Infinite    => False);
      Budget_With_Inc := Time_Management.Allocated_Ms;

      Check ("Budget with 3s increment is greater than without increment", Budget_With_Inc > Budget_No_Inc);
      Check ("Budget delta reflects increment contribution", (Budget_With_Inc - Budget_No_Inc) in 2_000 .. 4_000);
   end;

   -- 2. Test Time-Slice Reservation and Restoration:
   --    Reserving 500 ms for Stage 7 verification deducts 500 ms; restoring recovers it.
   Put_Line ("[2/4] Testing Verification Time-Slice Reservation and Restoration...");
   Time_Management.Start_Search
     (WTime       => 0,
      BTime       => 0,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 0,
      Move_Time   => 2000,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Base_Budget     : constant Integer := Time_Management.Allocated_Ms;
      Reserved_Budget : Integer;
      Restored_Budget : Integer;
   begin
      Check ("Base movetime budget is positive", Base_Budget in 1900 .. 2000);

      Time_Management.Reserve_Time_Slice (500);
      Reserved_Budget := Time_Management.Allocated_Ms;
      Check ("Reserved budget is reduced by slice (500 ms)", Reserved_Budget = Base_Budget - 500);

      Time_Management.Restore_Time_Slice;
      Restored_Budget := Time_Management.Allocated_Ms;
      Check ("Restored budget matches original base budget", Restored_Budget = Base_Budget);
   end;

   -- 3. Test Time Scramble Minimum Floor:
   --    With only 200 ms remaining, budget remains safe and positive (at least 1 ms).
   Put_Line ("[3/4] Testing Time Scramble Floor Protection...");
   Time_Management.Start_Search
     (WTime       => 200,
      BTime       => 200,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 0,
      Move_Time   => 0,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Scramble_Budget : constant Integer := Time_Management.Allocated_Ms;
   begin
      Check ("Scramble budget is strictly positive", Scramble_Budget >= 1);
      Check ("Scramble budget does not exceed remaining time", Scramble_Budget <= 200);
   end;

   -- 4. Test Fixed Movetime Bounds:
   Put_Line ("[4/4] Testing Fixed Movetime Boundary Handling...");
   Time_Management.Start_Search
     (WTime       => 0,
      BTime       => 0,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 0,
      Move_Time   => 5,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Tiny_Budget : constant Integer := Time_Management.Allocated_Ms;
   begin
      Check ("Tiny movetime (5 ms) clamps to floor of at least 1 ms", Tiny_Budget >= 1);
      Check ("Current control is Time_Per_Move", Time_Management.Current_Control = Time_Management.Time_Per_Move);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991717_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991717_Suite;
