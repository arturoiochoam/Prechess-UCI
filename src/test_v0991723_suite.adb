-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.23 TACTICAL REPAIR & MATE PREVENTION TEST SUITE
--
--  Unit:          Test_V0991723_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991723_Suite is

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

   function Sq (File_Char : Character; Rank_Char : Character) return Integer is
      F : constant Integer := Character'Pos (File_Char) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Char) - Character'Pos ('0');
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.23 - Tactical & Mate Prevention Suite");
   Put_Line ("========================================================");

   -- 1. Test Game 2 Move 15: Is_Premature_Flank_Bishop must return FALSE for
   --    15. Bb5! pinning the Nc6 to King on e8 when queens are off the board.
   Put_Line ("[1/5] Testing Nimzo-Indian Move 15: Queenless pin (Bb5 vs Be2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b1k2r/ppp2ppp/2n5/2Pp4/3p4/P4P2/1P1K2PP/R2N1B1R w kq - 1 15", Dummy_White);

   declare
      Sq_F1 : constant Integer := Sq ('f', '1');
      Sq_B5 : constant Integer := Sq ('b', '5');
      Is_Premature : constant Boolean :=
        Search_Integration.Is_Premature_Flank_Bishop (True, Sq_F1, Sq_B5);
   begin
      Check ("Nimzo-Indian Move 15: Bb5 pin must NOT be flagged premature", not Is_Premature);
   end;

   -- 2. Test Game 1 Move 10: Best_Fried_Liver_Central_Break must find 10. d4!
   --    sacrificing pawn to open lines against exposed King on e6.
   Put_Line ("[2/5] Testing Two Knights Fried Liver: Central breakthrough (10. d4!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/pp4pp/2p1k3/3np3/1nB5/2N2Q2/PPPP1PPP/R1B2RK1 w - - 0 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D2 : constant Integer := Sq ('d', '2');
      Sq_D4 : constant Integer := Sq ('d', '4');
   begin
      Search_Integration.Best_Fried_Liver_Central_Break (True, Found, F, T);
      Check ("Two Knights Move 10: Best_Fried_Liver_Central_Break finds move", Found);
      Check ("Two Knights Move 10: Source square must be d2", F = Sq_D2);
      Check ("Two Knights Move 10: Target square must be d4 (central break)", T = Sq_D4);
   end;

   -- 3. Test Black-side symmetry for Fried Liver central break (d7-d5):
   Put_Line ("[3/5] Testing Fried Liver central break symmetry (Black d7-d5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b2rk1/pppp1ppp/2n2q2/1nb5/3NP3/2P1K3/PP4PP/RNBQ1B1R b - - 0 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D7 : constant Integer := Sq ('d', '7');
      Sq_D5 : constant Integer := Sq ('d', '5');
   begin
      Search_Integration.Best_Fried_Liver_Central_Break (False, Found, F, T);
      Check ("Black-side: Best_Fried_Liver_Central_Break finds move", Found);
      Check ("Black-side: Source square must be d7", F = Sq_D7);
      Check ("Black-side: Target square must be d5", T = Sq_D5);
   end;

   -- 4. Test Game 2 Move 41: Constricted King escape from mating net (41. Kd3!).
   Put_Line ("[4/5] Testing Constricted King Escape from Mating Net (41. Kd3!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/kp4p1/8/2pp1n2/p7/P1K5/1P4r1/1R6 w - - 0 41", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C3 : constant Integer := Sq ('c', '3');
      Sq_D3 : constant Integer := Sq ('d', '3');
   begin
      Search_Integration.Best_Constricted_King_Escape (True, Found, F, T);
      Check ("Game 2 Move 41: Best_Constricted_King_Escape finds move", Found);
      Check ("Game 2 Move 41: King moves from c3", F = Sq_C3);
      Check ("Game 2 Move 41: King steps to d3 escaping mating net", T = Sq_D3);
   end;

   -- 5. Test Game 1 Move 48: Attack on infiltrating back-rank rook (48. Bb4!).
   Put_Line ("[5/5] Testing Infiltrating Rook Attack (48. Bb4!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/pk1r3p/p1p5/2B5/2B4b/5P2/1PK5/4r3 w - - 6 48", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C5 : constant Integer := Sq ('c', '5');
      Sq_B4 : constant Integer := Sq ('b', '4');
   begin
      Search_Integration.Best_Infiltrating_Rook_Attacker (True, Found, F, T);
      Check ("Game 1 Move 48: Best_Infiltrating_Rook_Attacker finds move", Found);
      Check ("Game 1 Move 48: Bishop attacks from c5", F = Sq_C5);
      Check ("Game 1 Move 48: Bishop moves to b4 attacking e1 rook", T = Sq_B4);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991723_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991723_Suite;
