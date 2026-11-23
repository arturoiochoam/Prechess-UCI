-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.27 DEEPENED VERIFIER SUITE
--
--  Unit:          Test_V0991727_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Tactical_Search;
with TT_Table;

procedure Test_V0991727_Suite is

   Failures : Natural := 0;
   Dummy_White : Boolean;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function Sq (File_Char : Character; Rank_Char : Character) return Integer is
      F : constant Integer := Character'Pos (File_Char) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Char) - Character'Pos ('0');
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.27 - Deepened Verifier Suite");
   Put_Line ("========================================================");
   TT_Table.Init_TT (16);

   --  1. A 16-ply verifier still refutes a quiet cascade choice when a mate
   --     is available (back-rank Rd8#).
   Put_Line ("[1/2] Verify (Max_Depth 16) replaces a quiet move by Rd8#...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", Dummy_White);
   declare
      R : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => Sq ('g', '1'), Chosen_To => Sq ('f', '1'), Chosen_Promo => 0,
           Budget_Ms     => 3000,
           Max_Depth     => 16);
   begin
      Check ("Result valid", R.Valid);
      Check ("Cascade move replaced", R.Replaced);
      Check ("Best move is d1d8", R.Best.From = Sq ('d', '1') and then R.Best.To = Sq ('d', '8'));
      Check ("Mate score reported", R.Best_Score >= Tactical_Search.Mate_Threshold);
   end;

   --  2. The deeper horizon is clock-safe: iterative deepening keeps the last
   --     completed depth and never exceeds the requested cap.
   Put_Line ("[2/2] Verify (Max_Depth 16) respects budget and cap...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 9", Dummy_White);
   declare
      R : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => Sq ('f', '1'), Chosen_To => Sq ('d', '3'), Chosen_Promo => 0,
           Budget_Ms     => 1500,
           Max_Depth     => 16);
   begin
      Check ("Result valid", R.Valid);
      Check ("Completed depth within 1 .. 16", R.Depth in 1 .. 16);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991727_Suite;
