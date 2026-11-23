-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.25 TACTICAL REPAIR & ADVANCED ENGINE SUITE
--
--  Unit:          Test_V0991725_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991725_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.25 - Tactical & Strategic Engine Suite");
   Put_Line ("========================================================");

   -- 1. Test SEE Relative Pin Recognition:
   --    When Black captures on d5 with Nfxd5, White c4xd5 unmasks Rc8 attacking Qc3.
   --    SEE must recognize that c4xd5 hangs the queen and evaluate Nfxd5 as winning material.
   Put_Line ("[1/6] Testing SEE Relative Pin Detection on unmasked queen file...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rqk3/1p3p2/pn1p1npr/Q2Pp2p/2P5/1N3P2/PP4PP/2KR1B1R w - - 1 16", Dummy_White);

   declare
      Sq_A5 : constant Integer := Sq ('a', '5');
      Sq_C3 : constant Integer := Sq ('c', '3');
      Sq_F6 : constant Integer := Sq ('f', '6');
      Sq_D5 : constant Integer := Sq ('d', '5');
      Gain  : Integer;
      Hang  : Integer;
   begin
      -- Simulate White move 16. Qc3
      Pvalidade.Tabuleiro (Sq_C3) := Pvalidade.Tabuleiro (Sq_A5);
      Pvalidade.Tabuleiro (Sq_A5) := 0;

      Gain := Search_Integration.See_Gain (White_Captures => False, From_Sq => Sq_F6, To_Sq => Sq_D5);
      Check ("SEE Relative Pin: Nfxd5 evaluated as >= 100 cp gain for Black", Gain >= 100);

      Hang := Search_Integration.Max_Opponent_See (White_To_Move => True);
      Check ("Max_Opponent_See flags hanging pawn/queen exposure (Hang >= 100)", Hang >= 100);
   end;

   -- 2. Test Undefended Major Attack:
   --    Detects undefended enemy rook on h6 and launches tempo attack 15. Qd2!.
   Put_Line ("[2/6] Testing Best_Undefended_Major_Attack finds 15. Qd2!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk3/1p3p2/pn1p1npr/Q2Pp2p/8/1N3P2/PPP4P/2KR1B1R w q - 0 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A5 : constant Integer := Sq ('a', '5');
      Sq_D2 : constant Integer := Sq ('d', '2');
   begin
      Search_Integration.Best_Undefended_Major_Attack (True, Found, F, T);
      Check ("Best_Undefended_Major_Attack: Move found", Found);
      Check ("Best_Undefended_Major_Attack: From square is a5", F = Sq_A5);
      Check ("Best_Undefended_Major_Attack: To square is d2 (15. Qd2!)", T = Sq_D2);
   end;

   -- 3. Test Infiltration Guard & Double Attack Prevention:
   --    Moving knight to a6 leaves c2 undefended, allowing Black Rc2! double attack.
   --    Best_Infiltration_Guard finds 32. Bd3! sealing rank 2.
   Put_Line ("[3/6] Testing Best_Infiltration_Guard finds 32. Bd3!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4rk2/5p2/p5p1/3Rp2p/KN6/2r2P2/P3B2P/8 w - - 7 32", Dummy_White);

   declare
      Found    : Boolean := False;
      F, T     : Integer := 0;
      Sq_E2    : constant Integer := Sq ('e', '2');
      Sq_D3    : constant Integer := Sq ('d', '3');
      Sq_B4    : constant Integer := Sq ('b', '4');
      Sq_A6    : constant Integer := Sq ('a', '6');
      Has_Fork : Boolean;
   begin
      -- Test that Nxa6 allows double attack (Rc2)
      Pvalidade.Tabuleiro (Sq_A6) := Pvalidade.Tabuleiro (Sq_B4);
      Pvalidade.Tabuleiro (Sq_B4) := 0;
      Has_Fork := Search_Integration.Has_Opponent_Double_Attack (White_To_Move => True);
      Check ("Has_Opponent_Double_Attack flags Rc2 after 32. Nxa6", Has_Fork);

      -- Restore board
      Pvalidade.Tabuleiro (Sq_B4) := Pvalidade.Tabuleiro (Sq_A6);
      Pvalidade.Tabuleiro (Sq_A6) := -1;

      Search_Integration.Best_Infiltration_Guard (True, Found, F, T);
      Check ("Best_Infiltration_Guard: Move found", Found);
      Check ("Best_Infiltration_Guard: From square is e2", F = Sq_E2);
      Check ("Best_Infiltration_Guard: To square is d3 (32. Bd3!)", T = Sq_D3);
   end;

   -- 4. Test Passed Pawn Diagonal Control:
   --    Advanced passed pawn on d7: bishop activates along c8-h3 diagonal with 28. Bh3!.
   Put_Line ("[4/6] Testing Best_Passed_Pawn_Diagonal_Control finds Bh3!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rr4k1/3P1ppp/pb1N4/1pp3P1/1n3p2/5P2/2P4P/1K1R1B1R w - - 0 28", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F1 : constant Integer := Sq ('f', '1');
      Sq_H3 : constant Integer := Sq ('h', '3');
   begin
      Search_Integration.Best_Passed_Pawn_Diagonal_Control (True, Found, F, T);
      Check ("Best_Passed_Pawn_Diagonal_Control: Move found", Found);
      Check ("Best_Passed_Pawn_Diagonal_Control: From square is f1", F = Sq_F1);
      Check ("Best_Passed_Pawn_Diagonal_Control: To square is h3 (Bh3!)", T = Sq_H3);
   end;

   -- 5. Test Endgame Passed Pawn Push:
   --    In endgame, uncontested outside passed pawn h2 sprints with h4! avoiding king shuffles.
   Put_Line ("[5/6] Testing Best_Endgame_Passed_Pawn_Advance finds h4!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2k5/7R/8/5p2/2p2p2/2P1nP2/3K3P/8 w - - 2 61", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H2 : constant Integer := Sq ('h', '2');
      Sq_H4 : constant Integer := Sq ('h', '4');
   begin
      Search_Integration.Best_Endgame_Passed_Pawn_Advance (True, Found, F, T);
      Check ("Best_Endgame_Passed_Pawn_Advance: Move found", Found);
      Check ("Best_Endgame_Passed_Pawn_Advance: From square is h2", F = Sq_H2);
      Check ("Best_Endgame_Passed_Pawn_Advance: To square is h4 (h4!)", T = Sq_H4);
   end;

   -- 6. Test Color Invariance on Mirrored Positions (Black orientation):
   Put_Line ("[6/6] Testing Color Invariance on Mirrored Positions...");
   Search_Integration.Reset_Game;
   -- Mirrored position of Game 1 move 61: Black king on c1, Black rook on h2, Black pawn on h7, White pawns on c5, f5, f4, etc.
   Search_Integration.Parse_FEN
     ("8/3k3p/2p1Np2/2P2P2/5P2/8/7r/2K5 b - - 2 61", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H7 : constant Integer := Sq ('h', '7');
      Sq_H5 : constant Integer := Sq ('h', '5');
   begin
      Search_Integration.Best_Endgame_Passed_Pawn_Advance (False, Found, F, T);
      Check ("Color Invariance: Best_Endgame_Passed_Pawn_Advance finds h5 for Black", Found);
      Check ("Color Invariance: From square is h7", F = Sq_H7);
      Check ("Color Invariance: To square is h5", T = Sq_H5);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY (6/6)");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991725_Suite;
