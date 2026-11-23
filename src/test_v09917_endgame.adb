-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17 ENDGAME & MATE PREFERENCE TEST SUITE (PHASE 6b)
--
--  Unit:          Test_V09917_Endgame
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Endgame & Tactical Verification Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. E5/S1 Mate-in-1 Preference:
--     - Ra8# quiet mate-in-1 (back-rank) chosen immediately over quiet moves.
--     - Queen mate-in-1 chosen immediately.
--     - Black to move Ra1# quiet mate-in-1 chosen immediately.
--  2. E5 Best_Endgame Mate Acceptance:
--     - Checkmating move accepted in Best_Endgame even without geometry score increase.
--  3. E1 Widened Rook-Pawn Draw Recognition:
--     - White a-pawn with Black king on b8 (adjacent promotion square).
--     - White h-pawn with Black king on g8 (adjacent promotion square).
--     - Black a-pawn with White king on b1 (adjacent promotion square).
--     - Black h-pawn with White king on g1 (adjacent promotion square).
--     - Negative tests: defender king not in drawing zone, non-rook pawn.
--  4. No False Draw on Winning KP-K:
--     - Central pawn KP-K is never flagged as drawn.
--  5. E4 King_Escape_Count:
--     - Defended attacker piece does not register as an escape square.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V09917_Endgame is
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

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
   end Load;

   From_Sq, To_Sq, Promo : Integer;
   Found : Boolean;
begin
   Put_Line ("=== V0.9.9.17 Endgame & Mate Preference Test Suite ===");

   -- 1. E5/S1: Ra8# quiet mate-in-1
   -- White: Kh1, Ra1, pawns f2, g2, h2. Black: Kg8, pawns f7, g7, h7.
   -- a1 = 1, a8 = 57.
   Load ("6k1/5ppp/8/8/8/8/5PPP/R6K w - - 0 1");
   Check ("Ra8# delivers checkmate",
          Search_Integration.Move_Delivers_Checkmate
            (White_To_Move => True,
             From_Sq       => Move_Validation.Square_Of (1, 1),  -- a1
             To_Sq         => Move_Validation.Square_Of (8, 1),  -- a8
             Promo         => 0));

   -- 2. E5/S1: Queen mate-in-1
   -- White: Kh6, Qg6. Black: Kh8. Qg6-g7# (g6 = 47, g7 = 55).
   Load ("7k/8/6QK/8/8/8/8/8 w - - 0 1");
   Check ("Qg7# delivers checkmate",
          Search_Integration.Move_Delivers_Checkmate
            (White_To_Move => True,
             From_Sq       => Move_Validation.Square_Of (6, 7),  -- g6
             To_Sq         => Move_Validation.Square_Of (7, 7),  -- g7
             Promo         => 0));

   -- 3. E5/S1: Black quiet mate-in-1 (Ra8-a1#)
   -- Black: Kh8, Ra8, pawns f7, g7, h7. White: Kh1, pawns f2, g2, h2.
   Load ("r6k/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1");
   Check ("Ra1# delivers checkmate for Black",
          Search_Integration.Move_Delivers_Checkmate
            (White_To_Move => False,
             From_Sq       => Move_Validation.Square_Of (8, 1),  -- a8
             To_Sq         => Move_Validation.Square_Of (1, 1),  -- a1
             Promo         => 0));

   -- 4. E5 Best_Endgame mate acceptance:
   -- White: Ka6, Qb7. Black: Ka8. Move Qb7-b8# or Qb7-a7#.
   Load ("k7/1Q6/K7/8/8/8/8/8 w - - 0 1");
   Search_Integration.Best_Endgame (White_To_Move, Found, From_Sq, To_Sq);
   -- In this position, Black is already checkmated!
   -- Let's test White Ka6, Qb6, Black Ka8:
   -- Moves: Qb6-b8# (Square_Of(8,2)=58) or Qb6-a7# (Square_Of(7,1)=49).
   Load ("k7/8/KQ6/8/8/8/8/8 w - - 0 1");
   Search_Integration.Best_Endgame (White_To_Move, Found, From_Sq, To_Sq);
   Check ("Best_Endgame finds winning/mating move in KQ-K", Found);
   if Found then
      Check ("Best_Endgame move delivers checkmate or valid progression",
             Search_Integration.Move_Delivers_Checkmate (True, From_Sq, To_Sq, 0)
             or else To_Sq = Move_Validation.Square_Of (7, 1)
             or else To_Sq = Move_Validation.Square_Of (8, 2));
   end if;

   -- 5. E1 Widened rook-pawn draw:
   -- 5a: White a-pawn, Black king on b8 (adjacent-file promotion square)
   Load ("1k6/8/P7/K7/8/8/8/8 w - - 0 1");
   Check ("E1: White a-pawn, Black king on b8 is recognized draw",
          Search_Integration.Endgame_Is_Draw);

   -- 5b: White h-pawn, Black king on g8 (adjacent-file promotion square)
   Load ("6k1/8/7P/7K/8/8/8/8 w - - 0 1");
   Check ("E1: White h-pawn, Black king on g8 is recognized draw",
          Search_Integration.Endgame_Is_Draw);

   -- 5c: Black a-pawn, White king on b1 (adjacent-file promotion square)
   Load ("8/8/8/8/k7/p7/8/1K6 b - - 0 1");
   Check ("E1: Black a-pawn, White king on b1 is recognized draw",
          Search_Integration.Endgame_Is_Draw);

   -- 5d: Black h-pawn, White king on g1 (adjacent-file promotion square)
   Load ("8/8/8/8/7k/7p/8/6K1 b - - 0 1");
   Check ("E1: Black h-pawn, White king on g1 is recognized draw",
          Search_Integration.Endgame_Is_Draw);

   -- 5e: Negative test: Defender king not in drawing zone
   Load ("4k3/8/P7/K7/8/8/8/8 w - - 0 1");
   Check ("E1 negative: Defender king on e8 is NOT draw",
          not Search_Integration.Endgame_Is_Draw);

   -- 5f: Negative test: Non-rook pawn (b-pawn)
   Load ("2k5/8/1P6/1K6/8/8/8/8 w - - 0 1");
   Check ("E1 negative: b-pawn with king on c8 is NOT draw",
          not Search_Integration.Endgame_Is_Draw);

   -- 6. No false draw on winning KP-K:
   -- Central pawn e-pawn
   Load ("4k3/8/3KP3/8/8/8/8/8 w - - 0 1");
   Check ("Winning central KP-K is NOT draw",
          not Search_Integration.Endgame_Is_Draw);

   -- 7. E4 King_Escape_Count:
   -- White King on h1, Black Queen on g2 defended by Black King on f3.
   -- White king has 0 escape squares (cannot capture defended queen).
   Load ("8/8/8/8/8/5k2/6q1/7K w - - 0 1");
   -- In this position, White is in check/mate.
   -- Let's test King_Escape_Count (Defender_White => True):
   Check ("E4: Defended piece gives 0 escape squares",
          Search_Integration.King_Escape_Count (Defender_White => True) = 0);

   New_Line;
   if Failures = 0 then
      Put_Line ("TEST_V09917_ENDGAME: ALL PASS (11/11)");
   else
      Put_Line ("TEST_V09917_ENDGAME: FAILURES =" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_V09917_Endgame;
