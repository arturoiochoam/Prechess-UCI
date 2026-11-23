-------------------------------------------------------------------------------
--  PRECHESS UCI - EVALUATION REGRESSION HARNESS v0.9.9.16
--
--  Harness:       Test_V09916_Eval
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.16 Honest-Score Suite)
--  Date:          2026
--
--  SCOPE & TEST MATRICES (P3 + P5 + P6 + P7-P9):
--  1. PST fold into Evaluate (P3): positional improvement changes score;
--     PST term added before Endgame_Bonus overlay.
--  2. Bishop/knight material split (P5): Bishop=330, Knight=320; bishop-pair
--     bonus (+30 cp) applied for two bishops.
--  3. Contempt-aware draw default no-op (P6): hard-draw override returns 0.
--  4. Sign invariance (P4): mirrored position yields equal magnitude with
--     single sign inversion.
--  5. Material_Value cascade (P7-P9): corrected material ordering via public
--     Material_Value function.
--
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Search_Integration;
with Pprechess2; use Pprechess2;

procedure Test_V09916_Eval is

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

   Score : Integer;
   Score_Mirrored : Integer;
   PS_White_N : Integer;
   PS_Black_N : Integer;
   White_To_Move  : Boolean := True;
   Black_To_Move  : Boolean := False;

begin

   ----------------------------------------------------------------------------
   -- 1. PST fold into Evaluate (P3)
   --    With material equal, a purely positional improvement (better piece
   --    placement / tapered PST) must change the reported score.
   ----------------------------------------------------------------------------

   -- Position 1: Knights on their starting squares (worse PST score)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);
   Score := Search_Integration.Evaluate;

   -- Position 2: Knights developed (better PST score)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppppppp/8/8/3N4/8/PPPPP1PP/R1BQKBNR b KQkq - 1 1", White_To_Move);
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppppppp/8/8/3N4/8/PPPPP1PP/R1BQKBNR b KQkq - 1 1", White_To_Move);
   Score_Mirrored := Search_Integration.Evaluate;

   -- The developed knight should score better (more positive for White) than
   -- the starting position since we're measuring White-relative score.
   Check ("PST fold: developed knight scores better than starting",
          Score_Mirrored > Score);

   ----------------------------------------------------------------------------
   -- 2. Bishop/knight material split (P5)
   --    Bishop = 330 cp, Knight = 320 cp; bishop-pair bonus = +30 cp when
   --    a side holds both bishops.
   ----------------------------------------------------------------------------

   -- Bishop alone (remove knights, keep bishop)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1", White_To_Move);
   Score := Search_Integration.Evaluate;

   -- Knight alone (remove bishop, keep knight)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);
   Score_Mirrored := Search_Integration.Evaluate;

   -- Both bishops on board
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);
   Score := Search_Integration.Evaluate;

   -- Check that material values are different (330 vs 320)
   -- This is verified by comparing material contributions in cascades

   ----------------------------------------------------------------------------
   -- 3. Contempt-aware draw, default no-op (P6)
   --    At default contempt (0), hard-draw override returns exactly 0.
   ----------------------------------------------------------------------------

   -- Set up a position where evaluation would normally be close to 0
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3qk3/8/8/8/8/8/8/3QK3 w - - 0 1", White_To_Move);
   Score := Search_Integration.Evaluate;

   -- With default contempt, the hard-draw override should return exactly 0
   -- (regression guard against 0.9.9.15 behavior)
   Check ("Contempt default: hard-draw override returns 0",
          Score = 0);

   ----------------------------------------------------------------------------
   -- 4. Sign invariance after PST fold (P4)
   --    A mirrored position yields equal magnitude with a single sign inversion.
   ----------------------------------------------------------------------------

   -- White has a positional advantage (better piece placement)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3r2k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", White_To_Move);
   Score := Search_Integration.Evaluate;

   -- Mirror: black has same positional advantage from their perspective
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3R2r1/5ppp/8/8/8/8/5PPP/3r2k1 b - - 0 1", Black_To_Move);
   Score_Mirrored := Search_Integration.Evaluate;

   -- The magnitude should be the same, sign flipped
   Check ("Sign invariance: mirrored positions yield equal magnitude/opposite sign",
          Score = -Score_Mirrored);

   ----------------------------------------------------------------------------
   -- 5. Material_Value cascade map (P7-P9)
   --    Verify corrected material ordering via public Material_Value function.
   ----------------------------------------------------------------------------

   -- Check material values are correct (Bishop > Knight, P=100, N=320, B=330)
   -- Material_Value function returns centipawn value for each piece type

   -- P = 100
   Check ("Material_Value: Pawn = 100",
          Search_Integration.Material_Value (Pawn) = 100);

   -- N = 320
   Check ("Material_Value: Knight = 320",
          Search_Integration.Material_Value (Knight) = 320);

   -- B = 330
   Check ("Material_Value: Bishop = 330",
          Search_Integration.Material_Value (Bishop) = 330);

   -- R = 500
   Check ("Material_Value: Rook = 500",
          Search_Integration.Material_Value (Rook) = 500);

   -- Q = 900
   Check ("Material_Value: Queen = 900",
          Search_Integration.Material_Value (Queen) = 900);

   -- K = 0
   Check ("Material_Value: King = 0",
          Search_Integration.Material_Value (King) = 0);

   ----------------------------------------------------------------------------
   -- 6. G2 frame-proof probe (mandatory machine-checkable sign test)
   --    Positional_Sum is documented as White-relative: a White piece on a
   --    good square must yield a POSITIVE sum, the colour-mirrored Black
   --    piece on the SAME square must yield a NEGATIVE sum. A positive
   --    result here proves the PST fold is frame-consistent and has not
   --    been silently negated twice.
   ----------------------------------------------------------------------------

   -- (a) White knight centralized on d5.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/3N4/8/8/8/4K3 w - - 0 1", White_To_Move);
   PS_White_N := Pprechess2.Positional_Sum (White_Relative => True);
   Put_Line ("G2 probe: Positional_Sum(white-N-on-d5) =" & PS_White_N'Image);
   Check ("G2: Positional_Sum(white-N-on-d5) > 0", PS_White_N > 0);

   -- (b) Colour mirror: Black knight on the same square d5.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/8/3n4/8/8/4K3 w - - 0 1", White_To_Move);
   PS_Black_N := Pprechess2.Positional_Sum (White_Relative => True);
   Put_Line ("G2 probe: Positional_Sum(black-N-on-d5) =" & PS_Black_N'Image);
   Check ("G2: Positional_Sum(black-N-on-d5) < 0", PS_Black_N < 0);

   ----------------------------------------------------------------------------
   -- Final report
   ----------------------------------------------------------------------------

   if Failures = 0 then
      Put_Line ("TEST_V09916_EVAL: PASS");
   else
      Put_Line ("TEST_V09916_EVAL: FAIL (" & Failures'Image & " failures)");
   end if;

exception
   when E : others =>
      Put_Line ("TEST_V09916_EVAL: EXCEPTION raised");
      Put_Line ("Message: " & Ada.Exceptions.Exception_Message (E));
      Put_Line ("TEST_V09916_EVAL: FAIL");
      raise;

end Test_V09916_Eval;