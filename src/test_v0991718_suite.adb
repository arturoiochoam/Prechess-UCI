-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.18 TIME-CONTROL AUDIT TEST SUITE
--
--  Unit:          Test_V0991718_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Time_Management; use Time_Management;

procedure Test_V0991718_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.18 - Time-Control Audit Suite       ");
   Put_Line ("========================================================");

   -- 1. Test Low Moves-To-Go 80% Clock Safety Cap:
   --    With Moves_To_Go = 1 and 1000 ms remaining, budget must NOT exceed 80% (800 ms)
   --    to guarantee clock safety on the final move before time control.
   Put_Line ("[1/4] Testing Low Moves-To-Go 80% Clock Safety Cap...");
   Time_Management.Start_Search
     (WTime       => 1000,
      BTime       => 1000,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 1,
      Move_Time   => 0,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Budget : constant Integer := Time_Management.Allocated_Ms;
   begin
      Check ("Moves_To_Go=1 with 1000 ms caps budget <= 800 ms", Budget <= 800);
      Check ("Budget is positive", Budget > 0);
   end;

   -- 2. Test Classical Tournament Time Control:
   --    40 moves in 600,000 ms (10 minutes).
   Put_Line ("[2/4] Testing Tournament 40 moves in 600 seconds...");
   Time_Management.Start_Search
     (WTime       => 600_000,
      BTime       => 600_000,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 40,
      Move_Time   => 0,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Budget : constant Integer := Time_Management.Allocated_Ms;
   begin
      -- Expected 600,000 / 40 = 15,000 ms minus dynamic overhead (600,000 / 50 = 12,000 ms) = 3,000 ms
      Check ("Tournament 40/600s allocates between 2s and 5s", Budget in 2_000 .. 5_000);
      Check ("Current control is Tournament", Time_Management.Current_Control = Time_Management.Tournament);
   end;

   -- 3. Test Sudden Death / All-In 25% Reserve Cap:
   --    No moves_to_go with 60,000 ms remaining must not allocate more than 25% (15,000 ms).
   Put_Line ("[3/4] Testing Sudden Death 25% Reserve Ceiling...");
   Time_Management.Start_Search
     (WTime       => 60_000,
      BTime       => 60_000,
      WInc        => 0,
      BInc        => 0,
      Moves_To_Go => 0,
      Move_Time   => 0,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);

   declare
      Budget : constant Integer := Time_Management.Allocated_Ms;
   begin
      Check ("Sudden death 60s allocates <= 25% (15s)", Budget <= 15_000);
      Check ("Current control is All_In", Time_Management.Current_Control = Time_Management.All_In);
   end;

   -- 4. Test Stop_Search Cooperative Interruption:
   Put_Line ("[4/4] Testing Cooperative Search Abort on Stop_Search...");
   Check ("Search is not aborted before stop", not Time_Management.Search_Aborted);
   Time_Management.Stop_Search;
   Check ("Search_Aborted is True after Stop_Search", Time_Management.Search_Aborted);

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991718_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991718_Suite;
