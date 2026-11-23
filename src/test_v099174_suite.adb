-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.4 TACTICAL INTEGRITY & GAME BLUNDER ELIMINATION SUITE
--
--  Unit:          Test_V099174_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099174_Suite is

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

   function Sq_Str (Sq : Integer) return String is
      File_Char : constant Character := Character'Val (Character'Pos ('a') + Move_Validation.File_Of (Sq) - 1);
      Rank_Char : constant Character := Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (Sq) - 1);
   begin
      return "" & File_Char & Rank_Char;
   end Sq_Str;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.4 - Tactical Integrity Test Suite  ");
   Put_Line ("========================================================");

   -- 1. Test Move 6: Anti-d5 Blunder Check
   -- In Sicilian Grand Prix / Closed, Black must not push d6-d5 blundering a pawn to exd5
   Put_Line ("[1/4] Testing Move 6: Prevention of 6... d5 blunder...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk1nr/pp2ppbp/2np2p1/2p5/4P3/2NPB1P1/PPP2PBP/R2QK1NR b KQkq - 1 6", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
   begin
      Search_Integration.Best_Central_Pawn_Fork_Strike (False, Found, F, T);
      Check ("Move 6: Best_Central_Pawn_Fork_Strike must NOT fire on d6-d5",
             not Found or else T /= Move_Validation.Square_Of (5, 4));
   end;

   -- 2. Test Move 15: Anti-Ra7 Suicide Check
   -- Black Rook on a8 must not jump to a7 where White Queen on b7 captures it
   Put_Line ("[2/4] Testing Move 15: Prevention of 15... Ra7 suicide...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k1nr/1Q1b2bp/3qnp2/p1p1p1p1/6P1/2NPB2N/PPP2PBP/2R1R1K1 b kq - 0 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A7 : constant Integer := Move_Validation.Square_Of (7, 1);
   begin
      Search_Integration.Best_Rook_Attack_On_Infiltrated_Queen (False, Found, F, T);
      Check ("Move 15: Best_Rook_Attack_On_Infiltrated_Queen must NOT target a7 (suicidal to Qb7)",
             not Found or else T /= Sq_A7);
   end;

   -- 3. Test Is_Bad_Queen_Sortie: Equal Queen Trade is NOT a Bad Sortie
   Put_Line ("[3/4] Testing Is_Bad_Queen_Sortie: Equal queen trade is legitimate...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pp1ppppp/2p5/8/8/1Q6/PPPPPPPP/RNB1KBNR b KQkq - 0 2", Dummy_White);

   declare
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Sq_B6 : constant Integer := Move_Validation.Square_Of (6, 2);
   begin
      Check ("Equal Queen Trade: Qd8-b6 challenging Qb3 is NOT a bad queen sortie",
             not Search_Integration.Is_Bad_Queen_Sortie (False, Sq_D8, Sq_B6));
   end;

   -- 4. Test Symmetrical Central Pawn Fork Strike Geometry
   -- White e4 vs Black d5, c4/e4 minors
   Put_Line ("[4/5] Testing Central Pawn Fork Strike True Geometry...");
   Search_Integration.Reset_Game;
   -- Genuine fork: Black has pawn on d7; White has Bishop on c4, Knight on e4, pawn on d3
   -- Black plays d7-d5! forking Bc4 and Ne4
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppp1pbp/5np1/8/2B1N3/3P4/PPP2PPP/R1BQK1NR b KQkq - 0 5", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D7 : constant Integer := Move_Validation.Square_Of (7, 4);
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4);
   begin
      Search_Integration.Best_Central_Pawn_Fork_Strike (False, Found, F, T);
      Check ("True Fork: Black d7-d5 forks minor pieces on c4 and e4",
             Found and then F = Sq_D7 and then T = Sq_D5);
   end;

   -- 5. Test Move 29: Prevention of 29... Nxb3 Pawn Promotion Blindness
   -- In 8/r3P1p1/1pp3kp/p1nn4/P3R3/1R5P/3B1PP1/6K1 b - - 0 29, White has advanced passed pawn
   -- on e7 threatening 30. e8=Q+. Black must NOT blunder 29... Nxb3 (taking rook on b3) and
   -- must detect the 800 cp quiet promotion threat.
   Put_Line ("[5/5] Testing Move 29: Detection of quiet passed pawn promotion threat...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/r3P1p1/1pp3kp/p1nn4/P3R3/1R5P/3B1PP1/6K1 b - - 0 29", Dummy_White);

   declare
      F_Nxb3 : constant Integer := Move_Validation.Square_Of (5, 3); -- c5
      T_Nxb3 : constant Integer := Move_Validation.Square_Of (3, 2); -- b3
      F_Rxe7 : constant Integer := Move_Validation.Square_Of (7, 1); -- a7
      T_Rxe7 : constant Integer := Move_Validation.Square_Of (7, 5); -- e7

      Saved_Cap, Saved_T : Integer;
      Hang_Nxb3, Hang_Rxe7 : Integer;
   begin
      -- Test hypothetical 29... Nxb3
      Saved_Cap := Pvalidade.Tabuleiro (F_Nxb3);
      Saved_T   := Pvalidade.Tabuleiro (T_Nxb3);
      Pvalidade.Tabuleiro (T_Nxb3) := Saved_Cap;
      Pvalidade.Tabuleiro (F_Nxb3) := 0;
      Hang_Nxb3 := Search_Integration.Max_Opponent_See (White_To_Move => False);
      Pvalidade.Tabuleiro (F_Nxb3) := Saved_Cap;
      Pvalidade.Tabuleiro (T_Nxb3) := Saved_T;

      -- Test hypothetical 29... Rxe7
      Saved_Cap := Pvalidade.Tabuleiro (F_Rxe7);
      Saved_T   := Pvalidade.Tabuleiro (T_Rxe7);
      Pvalidade.Tabuleiro (T_Rxe7) := Saved_Cap;
      Pvalidade.Tabuleiro (F_Rxe7) := 0;
      Hang_Rxe7 := Search_Integration.Max_Opponent_See (White_To_Move => False);
      Pvalidade.Tabuleiro (F_Rxe7) := Saved_Cap;
      Pvalidade.Tabuleiro (T_Rxe7) := Saved_T;

      Check ("Pawn Promotion Threat: Max_Opponent_See after Nxb3 must detect >= 800 cp promotion",
             Hang_Nxb3 >= 800);
      Check ("Pawn Elimination: Max_Opponent_See after Rxe7 must be <= 100 cp",
             Hang_Rxe7 <= 100);
      Check ("Safety Veto: Nxb3 (gain 500 cp) must have net material loss against 800 cp promotion",
             Hang_Nxb3 > 500);
   end;

   -- 6. Test Anti-Threefold Repetition Detection: Repetition_Count_After
   Put_Line ("[6/7] Testing Repetition_Count_After: 3-fold draw detection...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/8/8/8/R7/4K3 w - - 0 1", Dummy_White);

   -- King cycle: e1-e2, e8-e7, e2-e1, e7-e8 (first cycle)
   Search_Integration.Make_Move_UCI ("e1e2");
   Search_Integration.Make_Move_UCI ("e8e7");
   Search_Integration.Make_Move_UCI ("e2e1");
   Search_Integration.Make_Move_UCI ("e7e8");
   -- Second cycle: e1-e2, e8-e7, e2-e1, e7-e8
   Search_Integration.Make_Move_UCI ("e1e2");
   Search_Integration.Make_Move_UCI ("e8e7");
   Search_Integration.Make_Move_UCI ("e2e1");
   Search_Integration.Make_Move_UCI ("e7e8");

   -- Now board is back at 4k3/.../4K3 w - - 0 1, reached 3 times in History (start, after 1st cycle, after 2nd cycle).
   -- Playing e1-e2 now would reproduce the position after e1-e2 (which also occurred twice before)!
   declare
      F_E1 : constant Integer := Move_Validation.Square_Of (1, 5);
      T_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
      T_D1 : constant Integer := Move_Validation.Square_Of (1, 4);
      Rep_E2 : constant Integer :=
        Search_Integration.Repetition_Count_After (True, F_E1, T_E2, 0);
      Rep_D1 : constant Integer :=
        Search_Integration.Repetition_Count_After (True, F_E1, T_D1, 0);
   begin
      Check ("Repetition_Count_After: e1-e2 has occurred twice before (>= 2)",
             Rep_E2 >= 2);
      Check ("Repetition_Count_After: fresh move e1-d1 has occurred 0 times",
             Rep_D1 = 0);
   end;

   -- 7. Test False Mate Score Clamping & Score_To_UCI
   Put_Line ("[7/7] Testing Score_To_UCI: False Mate Suppression...");
   declare
      Mate_1_Str : constant String :=
        Search_Integration.Score_To_UCI (Search_Integration.Mate_Value - 1);
      Clamped_Pos : constant String := Search_Integration.Score_To_UCI (2500);
      Clamped_Neg : constant String := Search_Integration.Score_To_UCI (-2500);
   begin
      Check ("Score_To_UCI: True root mate outputs 'score mate 1'",
             Mate_1_Str = "score mate 1");
      Check ("Score_To_UCI: Clamped scratch score +2500 outputs 'score cp 2500'",
             Clamped_Pos = "score cp 2500");
      Check ("Score_To_UCI: Clamped scratch score -2500 outputs 'score cp -2500'",
             Clamped_Neg = "score cp -2500");
   end;

   if Failures = 0 then
      Put_Line ("TEST_V099174_SUITE: ALL PASS");
   else
      Put_Line ("TEST_V099174_SUITE: FAILURES DETECTED:" & Natural'Image (Failures));
   end if;

end Test_V099174_Suite;
