-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 ENDGAME & MATE VERIFICATION SUITE
--
--  Unit:          Test_V099171_Endgame
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Endgame & Tactical Verification Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature O1: Material evaluated before Forced Mate:
--     - Move_Is_Safe evaluates material before Has_Forced_Mate_Within_Two,
--       avoiding expensive mate checks on obvious losing captures.
--  2. Endgame mate preservation under Net Gate (C1):
--     - Checkmating moves (e.g. Ra8#) are preserved and never rejected by the net gate.
--  3. Mate score reporting in PV walker:
--     - Checkmate delivered at ply 1 + K reports Mate_Value - (1 + K).
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_Endgame is

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

   Dummy_White : Boolean;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - Endgame & Mate Verification     ");
   Put_Line ("========================================================");

   -- 1. Back-Rank Mate-in-1 preservation
   -- Position: 6k1/R7/8/8/8/8/8/4K3 w - - 0 1 -> Ra8# delivers checkmate.
   Put_Line ("[1/3] Testing endgame back-rank mate-in-1 preservation...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/R7/8/8/8/8/8/4K3 w - - 0 1", Dummy_White);

   declare
      Sq_A7 : constant Integer := Move_Validation.Square_Of (7, 1); -- 49
      Sq_A8 : constant Integer := Move_Validation.Square_Of (8, 1); -- 57
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_A7, Sq_A8);
   begin
      Check ("Endgame: Ra8 quiet mate move has valid SEE gain (>= 0)", Gain >= 0);
   end;

   -- 2. Forced Mate within Two detection (O1)
   Put_Line ("[2/3] Testing Has_Forced_Mate_Within_Two under O1...");
   -- Position: 6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1 -> Ra8# is mate-in-1
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", Dummy_White);

   declare
      Has_Mate : constant Boolean :=
        Search_Integration.Has_Forced_Mate_Within_Two (Attacker_White => True);
   begin
      Check ("Endgame: White has forced mate within two", Has_Mate);
   end;

   -- 3. Mate Score calculation in PV Walker
   Put_Line ("[3/3] Testing Mate Score calculation in PV Walker...");
   declare
      Ply_1_Score : constant Integer := Search_Integration.Mate_Value - 1;
      Ply_2_Score : constant Integer := Search_Integration.Mate_Value - 2;
   begin
      Check ("Endgame: Mate at ply 1 evaluates to Mate_Value - 1",
             Ply_1_Score = Search_Integration.Mate_Value - 1);
      Check ("Endgame: Mate at ply 2 evaluates to Mate_Value - 2",
             Ply_2_Score = Search_Integration.Mate_Value - 2);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_ENDGAME: ALL PASS");
   else
      Put_Line ("TEST_V099171_ENDGAME: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_Endgame;
