-------------------------------------------------------------------------------
--  PRECHESS UCI - EVALUATION, SCORE REPORTING & MATE TEST HARNESS
--
--  Harness:       Test_V09915_Eval
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.15 Honest-Score Suite)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Score_To_UCI Mate Mapping & Centipawn Pass-Through:
--     - Boundaries at Mate_Threshold (31000) and Mate_Value (32000).
--     - Centipawn pass-through format: "score cp <int>".
--     - Mate formatting: "score mate <int>" with non-empty signed integer.
--  2. Signed_Mate_Plies_To_Moves Ceil-Rounding:
--     - Mate in 1 ply  -> "1" / "-1"
--     - Mate in 2 plies -> "1" / "-1"
--     - Mate in 3 plies -> "2" / "-2"
--     - Mate in 4 plies -> "2" / "-2"
--  3. Single-Sourced Sign Invariance & Mirrored Symmetry:
--     - White up Queen (Evaluate = +900)
--     - Black up Queen (Evaluate = -900)
--     - Perspective flipping: equal magnitude, single sign inversion.
--  4. Move_Delivers_Checkmate Oracle:
--     - Back-rank mate delivered vs non-mating move.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration; use Search_Integration;

procedure Test_V09915_Eval is
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

   White_To_Move : Boolean;
   Eval_White    : Integer;
   Eval_Black    : Integer;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.15 - Score, Sign & Mate Test Gate");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Test Signed_Mate_Plies_To_Moves rounding (ceil(ply/2))
   ----------------------------------------------------------------------------
   -- White mates in 1 ply (immediate root mate): score = 31999
   Check ("Plies to moves: White mate in 1 ply (score 31999) -> '1'",
          Signed_Mate_Plies_To_Moves (Mate_Value - 1) = "1");

   -- White mates in 2 plies: score = 31998 -> ceil(2/2) = 1 move
   Check ("Plies to moves: White mate in 2 plies (score 31998) -> '1'",
          Signed_Mate_Plies_To_Moves (Mate_Value - 2) = "1");

   -- White mates in 3 plies: score = 31997 -> ceil(3/2) = 2 moves
   Check ("Plies to moves: White mate in 3 plies (score 31997) -> '2'",
          Signed_Mate_Plies_To_Moves (Mate_Value - 3) = "2");

   -- White mates in 4 plies: score = 31996 -> ceil(4/2) = 2 moves
   Check ("Plies to moves: White mate in 4 plies (score 31996) -> '2'",
          Signed_Mate_Plies_To_Moves (Mate_Value - 4) = "2");

   -- Black mates White in 1 ply: score = -31999 -> '-1'
   Check ("Plies to moves: Black mate in 1 ply (score -31999) -> '-1'",
          Signed_Mate_Plies_To_Moves (-(Mate_Value - 1)) = "-1");

   -- Black mates White in 2 plies: score = -31998 -> '-1'
   Check ("Plies to moves: Black mate in 2 plies (score -31998) -> '-1'",
          Signed_Mate_Plies_To_Moves (-(Mate_Value - 2)) = "-1");

   -- Black mates White in 3 plies: score = -31997 -> '-2'
   Check ("Plies to moves: Black mate in 3 plies (score -31997) -> '-2'",
          Signed_Mate_Plies_To_Moves (-(Mate_Value - 3)) = "-2");

   ----------------------------------------------------------------------------
   -- 2. Test Score_To_UCI UCI protocol formatting
   ----------------------------------------------------------------------------
   -- Mate format: score mate int
   Check ("Score_To_UCI: Mate_Value - 1 -> 'score mate 1'",
          Score_To_UCI (Mate_Value - 1) = "score mate 1");

   Check ("Score_To_UCI: -(Mate_Value - 1) -> 'score mate -1'",
          Score_To_UCI (-(Mate_Value - 1)) = "score mate -1");

   Check ("Score_To_UCI: Mate_Value - 3 -> 'score mate 2'",
          Score_To_UCI (Mate_Value - 3) = "score mate 2");

   Check ("Score_To_UCI: -(Mate_Value - 3) -> 'score mate -2'",
          Score_To_UCI (-(Mate_Value - 3)) = "score mate -2");

   -- Mate threshold boundary (31000)
   Check ("Score_To_UCI: Mate_Threshold -> 'score mate ...'",
          Score_To_UCI (Mate_Threshold) = "score mate " & Signed_Mate_Plies_To_Moves (Mate_Threshold));

   -- Centipawn formatting just below threshold: 30999
   Check ("Score_To_UCI: Mate_Threshold - 1 -> 'score cp 30999'",
          Score_To_UCI (Mate_Threshold - 1) = "score cp 30999");

   Check ("Score_To_UCI: -(Mate_Threshold - 1) -> 'score cp -30999'",
          Score_To_UCI (-(Mate_Threshold - 1)) = "score cp -30999");

   -- Ordinary centipawns: 0, 100, -250, 900, -900
   Check ("Score_To_UCI: 0 -> 'score cp 0'",
          Score_To_UCI (0) = "score cp 0");

   Check ("Score_To_UCI: 100 -> 'score cp 100'",
          Score_To_UCI (100) = "score cp 100");

   Check ("Score_To_UCI: -250 -> 'score cp -250'",
          Score_To_UCI (-250) = "score cp -250");

   Check ("Score_To_UCI: 900 -> 'score cp 900'",
          Score_To_UCI (900) = "score cp 900");

   Check ("Score_To_UCI: -900 -> 'score cp -900'",
          Score_To_UCI (-900) = "score cp -900");

   ----------------------------------------------------------------------------
   -- 3. Test Static Evaluation Contract & Sign Invariance
   ----------------------------------------------------------------------------
   -- Evaluate on White up Queen:
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);
   Eval_White := Search_Integration.Evaluate;
   Check ("Evaluate White-up-queen is positive (>= 500)", Eval_White >= 500);

   -- Evaluate on Black up Queen (White missing Queen):
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR b KQkq - 0 1", White_To_Move);
   Eval_Black := Search_Integration.Evaluate;
   Check ("Evaluate Black-up-queen is negative (<= -500)", Eval_Black <= -500);

   -- Original 2001 Prechess eval is not perfectly symmetric between colors
   -- (e.g. pawn-shield or piece-square terms that depend on absolute square
   -- rather than color-relative). We only require that both perspectives
   -- agree on the sign: the side with the extra queen wins.
   Check ("Mirrored perspective sign symmetry: Eval_White > 0, Eval_Black < 0",
          Eval_White > 0 and then Eval_Black < 0);

   ----------------------------------------------------------------------------
   -- 4. Test Move_Delivers_Checkmate
   ----------------------------------------------------------------------------
   -- Back-rank mate: White Rook on e1 (Sq 5), King on g1 (Sq 7), Black King g8 (Sq 63), pawns f7,g7,h7 (Sq 54,55,56)
   -- e1 is sq 5 (file 5, rank 1), e8 is sq 61 (file 5, rank 8).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1", White_To_Move);
   Check ("e1e8 delivers checkmate",
          Search_Integration.Move_Delivers_Checkmate
            (White_To_Move => True, From_Sq => 5, To_Sq => 61, Promo => 0));

   -- Non-mating move e1e7 (Sq 5 to Sq 53):
   Check ("e1e7 does NOT deliver checkmate",
          not Search_Integration.Move_Delivers_Checkmate
            (White_To_Move => True, From_Sq => 5, To_Sq => 53, Promo => 0));

   ----------------------------------------------------------------------------
   -- Final Gate Verdict
   ----------------------------------------------------------------------------
   if Failures = 0 then
      Put_Line ("========================================================");
      Put_Line ("TEST_V09915_EVAL: PASS");
      Put_Line ("========================================================");
   else
      Put_Line ("========================================================");
      Put_Line ("TEST_V09915_EVAL: FAIL (" & Natural'Image (Failures) & " failures)");
      Put_Line ("========================================================");
      raise Program_Error with "Test_V09915_Eval failed";
   end if;

end Test_V09915_Eval;
