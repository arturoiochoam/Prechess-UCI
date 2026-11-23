-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 KNIGHT OUTPOST & TACTICAL PRESERVATION SUITE
--
--  Unit:          Test_V099171_Outpost
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Knight Outpost & Capture Preservation Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Central Knight Outpost Pressure (White):
--     - Position: 2rqk2r/pp1bbppp/2nppn2/8/2BNPP2/2N1B3/PPP3PP/R2Q1RK1 w k - 3 10
--     - Knight on d4 leaps to b5, attacking backward central pawn on d6.
--     - Verifies Best_Central_Knight_Outpost_Pressure finds d4->b5.
--  2. Central Knight Outpost Pressure (Black - Symmetrical):
--     - Mirrored position with Black Knight on d5 leaping to b4.
--     - Verifies Best_Central_Knight_Outpost_Pressure finds d5->b4.
--  3. Pawn Tempo Kick Safety:
--     - Best_Pawn_Tempo_Kick_Knight must not push e4->e5 when d6 attacks e5.
--     - Verifies pawn moves into enemy pawn attacks with negative SEE are rejected.
--  4. Legacy Winning Capture Preservation:
--     - Position: 2rqk2r/pp2bppp/3ppn2/4P3/3B1P2/2N5/PPP3PP/R2Q1bK1 w k - 0 13
--     - Legacy 16-ply search move e5xf6 (SEE +220 cp) is preserved against
--       1-ply greedy overwrite by Qxf1 (SEE +330 cp) because Black bishop on f1
--       is doomed.
--  5. Net Material Evaluation on Knight Outpost:
--     - Verifies See_Gain and Max_Opponent_See_After on d4->b5.
--  6. Queenside B-Pawn Plan & Fianchetto Coordination (Tasks 1 & 2):
--     - In Task 2 (f8-bishop home), finds c8->b7.
--     - In Task 1 (c5-bishop already moved), c8->b7 is not forced, preserving d5->f6.
--  7. Displaced King Shield Development (Task 3):
--     - Position with King on e6: Best_Opening_Quiet_Alternative prefers f8->e7 over f8->c5.
--  8. Central Pawn Defense & Counter-Tempo (Tasks 4 & 5):
--     - Position: 1rbq3r/p1p1k1pp/2Q5/4p3/2Pp1n2/8/PP3PPP/R1B1R1K1 b - - 3 19
--     - Best_Defend_Central_Pawn rejects hanging f4->e2, finds safe queen tempo d8->d6.
--  9. Checking Fork Interposition Refutation (Task 6):
--     - Position: 1rbB3r/p1p2kpp/2Q5/4p3/2Pp4/3n4/PP3PPP/R3R1K1 b - - 0 21
--     - After Rh8xd8, Qxc7+ is refuted by Bc8-d7 interposition blocking the fork ray.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_Outpost is

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
   Put_Line ("  Prechess 0.9.9.17.1 - Knight Outpost & Preservation   ");
   Put_Line ("========================================================");

   -- 1. Central Knight Outpost Pressure (White d4->b5)
   Put_Line ("[1/9] Testing White Knight Outpost Leap d4->b5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rqk2r/pp1bbppp/2nppn2/8/2BNPP2/2N1B3/PPP3PP/R2Q1RK1 w k - 3 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4);
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
   begin
      Search_Integration.Best_Central_Knight_Outpost_Pressure (True, Found, F, T);
      Check ("White Outpost: Found is True", Found);
      Check ("White Outpost: From is d4", F = Sq_D4);
      Check ("White Outpost: To is b5", T = Sq_B5);
      Check ("White Outpost: SEE Gain is non-negative", Search_Integration.See_Gain (True, F, T) >= 0);
   end;

   -- 2. Central Knight Outpost Pressure (Black d5->b4 Symmetrical)
   Put_Line ("[2/9] Testing Black Knight Outpost Leap d5->b4...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/ppp3pp/2n1b3/2bnpp2/8/2NPPN2/PP1BBPPP/2RQK2R b K - 3 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4);
      Sq_B4 : constant Integer := Move_Validation.Square_Of (4, 2);
   begin
      Search_Integration.Best_Central_Knight_Outpost_Pressure (False, Found, F, T);
      Check ("Black Outpost: Found is True", Found);
      Check ("Black Outpost: From is d5", F = Sq_D5);
      Check ("Black Outpost: To is b4", T = Sq_B4);
      Check ("Black Outpost: SEE Gain is non-negative", Search_Integration.See_Gain (False, F, T) >= 0);
   end;

   -- 3. Pawn Tempo Kick Safety against Pawn Attacks
   Put_Line ("[3/9] Testing Pawn Tempo Kick safety against pawn attacks...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rqk2r/pp1bbppp/2nppn2/8/2BNPP2/2N1B3/PPP3PP/R2Q1RK1 w k - 3 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E4 : constant Integer := Move_Validation.Square_Of (4, 5);
      Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5);
   begin
      Search_Integration.Best_Pawn_Tempo_Kick_Knight (True, Found, F, T);
      Check ("Pawn Kick Safety: e4->e5 rejected due to pawn attack on e5", not (Found and then F = Sq_E4 and then T = Sq_E5));
   end;

   -- 4. SEE and Net Material Calculation on Tactical Exchanges
   Put_Line ("[4/9] Testing SEE evaluation on trapped piece tactical exchange...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rqk2r/pp2bppp/3ppn2/4P3/3B1P2/2N5/PPP3PP/R2Q1bK1 w k - 0 13", Dummy_White);

   declare
      Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5);
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
      Sq_D1 : constant Integer := Move_Validation.Square_Of (1, 4);
      Sq_F1 : constant Integer := Move_Validation.Square_Of (1, 6);
      See_E5F6 : constant Integer := Search_Integration.See_Gain (True, Sq_E5, Sq_F6);
      See_D1F1 : constant Integer := Search_Integration.See_Gain (True, Sq_D1, Sq_F1);
   begin
      Check ("Tactical SEE: e5xf6 wins minor piece (SEE >= 200)", See_E5F6 >= 200);
      Check ("Tactical SEE: d1xf1 wins undefended bishop (SEE = 330)", See_D1F1 = 330);
      Check ("Tactical SEE: Delta between 1-ply capture and piece capture < 300 cp", See_D1F1 - See_E5F6 < 300);
   end;

   -- 5. Safe Quiet Outpost
   Put_Line ("[5/9] Testing Safe Quiet Outpost square integrity...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rqk2r/pp1bbppp/2nppn2/8/2BNPP2/2N1B3/PPP3PP/R2Q1RK1 w k - 3 10", Dummy_White);

   declare
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4);
   begin
      Check ("Outpost Square: b5 not attacked by enemy pawn",
             not Search_Integration.Is_Square_Attacked_By_Pawn (True, Sq_B5));
      Check ("Outpost Square: After Nd4-b5, opponent max SEE is 0",
             Search_Integration.Max_Opponent_See_After (True, Sq_D4, Sq_B5) = 0);
   end;

   -- 6. Queenside B-Pawn Fianchetto & Coordination (Task 2 vs Task 1)
   Put_Line ("[6/9] Testing Queenside B-Pawn Plan coordination...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/p1p3pp/1p2k3/3np3/8/2NQ4/PPPP1PPP/R1B2RK1 b - - 1 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C8 : constant Integer := Move_Validation.Square_Of (8, 3);
      Sq_B7 : constant Integer := Move_Validation.Square_Of (7, 2);
   begin
      Search_Integration.Best_Queenside_B_Pawn_Plan (False, Found, F, T);
      Check ("Task 2 Fianchetto: Found is True", Found);
      Check ("Task 2 Fianchetto: From is c8", F = Sq_C8);
      Check ("Task 2 Fianchetto: To is b7", T = Sq_B7);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq3r/p1p3pp/1p2k3/2bnp3/4N3/3Q4/PPPP1PPP/R1B2RK1 b - - 3 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
   begin
      Search_Integration.Best_Queenside_B_Pawn_Plan (False, Found, F, T);
      Check ("Task 1 Guard: b-pawn plan suppressed when bishop already on c5", not Found);
   end;

   -- 7. Displaced King Shield Development (Task 3)
   Put_Line ("[7/9] Testing Displaced King Shield Development...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/4k3/3np3/8/2NQ4/PPPP1PPP/R1B1K2R b KQ - 1 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F8 : constant Integer := Move_Validation.Square_Of (8, 6);
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
   begin
      Search_Integration.Best_Opening_Quiet_Alternative (False, Found, F, T);
      Check ("Task 3 King Shield: Found is True", Found);
      Check ("Task 3 King Shield: From is f8", F = Sq_F8);
      Check ("Task 3 King Shield: To is e7", T = Sq_E7);
   end;

   -- 8. Central Pawn Defense & Counter-Tempo (Tasks 4 & 5)
   Put_Line ("[8/9] Testing Central Pawn Defense & Counter-Tempo...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1rbq3r/p1p1k1pp/2Q5/4p3/2Pp1n2/8/PP3PPP/R1B1R1K1 b - - 3 19", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4);
      Sq_F4 : constant Integer := Move_Validation.Square_Of (4, 6);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_Defend_Central_Pawn (False, Found, F, T);
      Check ("Task 4 Defense: Rejects hanging f4->e2", not (Found and then F = Sq_F4 and then T = Sq_E2));
      Check ("Task 4 Defense: Selects central queen tempo d8->d6", Found and then F = Sq_D8 and then T = Sq_D6);

      Search_Integration.Best_Queen_Tempo_On_Queen (False, Found, F, T);
      Check ("Task 4 Queen Tempo: Found is True", Found);
      Check ("Task 4 Queen Tempo: From is d8", F = Sq_D8);
      Check ("Task 4 Queen Tempo: To is d6", T = Sq_D6);
   end;

   -- 9. Checking Fork Interposition Refutation (Task 6)
   Put_Line ("[9/13] Testing Checking Fork Refutation on Rh8xd8...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1rbB3r/p1p2kpp/2Q5/4p3/2Pp4/3n4/PP3PPP/R3R1K1 b - - 0 21", Dummy_White);

   declare
      Sq_H8 : constant Integer := Move_Validation.Square_Of (8, 8);
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Saved_T : Integer;
      Fork_Detected : Boolean;
   begin
      -- Apply trial move Rh8xd8:
      Pvalidade.Tabuleiro (Sq_H8) := 0;
      Pvalidade.Tabuleiro (Sq_D8) := -7;

      Fork_Detected := Search_Integration.Has_Opponent_Checking_Fork (False, Sq_D8);
      Check ("Task 6 Fork Refuted: Qxc7+ refuted by Bc8-d7 interposition", not Fork_Detected);

      Pvalidade.Tabuleiro (Sq_D8) := 3;
      Pvalidade.Tabuleiro (Sq_H8) := -7;
   end;

   -- 10. Check Evasion Arbitration (Tasks 1 & 2)
   Put_Line ("[10/13] Testing Best_Check_Evasion...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/4k3/3np3/2B5/P1N2Q2/1PnP1PPP/R1B1K2R w KQ - 0 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5);
      Sq_D1 : constant Integer := Move_Validation.Square_Of (1, 4);
   begin
      Search_Integration.Best_Check_Evasion (True, Found, F, T);
      Check ("Task 1 Check Evasion: Found is True", Found);
      Check ("Task 1 Check Evasion: Selects e1->d1 counter-attacking c2", F = Sq_E1 and then T = Sq_D1);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/4k3/3np3/2Bn4/P1N2Q2/1P1PKPPP/R1B4R w - - 2 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
      Sq_F1 : constant Integer := Move_Validation.Square_Of (1, 6);
   begin
      Search_Integration.Best_Check_Evasion (True, Found, F, T);
      Check ("Task 2 Check Evasion: Found is True", Found);
      Check ("Task 2 Check Evasion: Selects e2->f1 retreating to home rank", F = Sq_E2 and then T = Sq_F1);
   end;

   -- 11. Winning Capture MVV-LVA (Task 3)
   Put_Line ("[11/13] Testing Winning Capture MVV-LVA (g2xf3)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/4k3/3np3/2B5/P1NK1n2/1P1P1PPP/R1B4R w - - 0 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_G2 : constant Integer := Move_Validation.Square_Of (2, 7);
      Sq_F3 : constant Integer := Move_Validation.Square_Of (3, 6);
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Task 3 Winning Capture: Found is True", Found);
      Check ("Task 3 Winning Capture: From is g2", F = Sq_G2);
      Check ("Task 3 Winning Capture: To is f3", T = Sq_F3);
   end;

   -- 12. Central King Safety Tuck (Tasks 4 & 5)
   Put_Line ("[12/13] Testing Central King Safety Tuck (Kd3-c2 & Kd3-e2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b1qb1r/ppp1k1pp/8/3Bp3/8/P1NK1P2/1P1P1P1P/R1B4R w - - 1 14", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4);
      Sq_C2 : constant Integer := Move_Validation.Square_Of (2, 3);
   begin
      Search_Integration.Best_Central_King_Safety_Tuck (True, Found, F, T);
      Check ("Task 4 King Tuck: Found is True", Found);
      Check ("Task 4 King Tuck: Selects d3->c2 behind b2 pawn", F = Sq_D3 and then T = Sq_C2);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bkqb1r/ppp3pp/8/3Bp3/8/PPNK1P2/3P1P1P/R1B4R w - - 1 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_Central_King_Safety_Tuck (True, Found, F, T);
      Check ("Task 5 King Tuck: Found is True", Found);
      Check ("Task 5 King Tuck: Selects d3->e2 when b-pawn pushed", F = Sq_D3 and then T = Sq_E2);
   end;

   -- 13. Rook on Central Open File Facing Queen (Task 6)
   Put_Line ("[13/17] Testing Best_Rook_Open_File_Facing_Queen (h1->e1)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bkqb1r/ppp4p/6p1/8/1P2B3/P1NK1P2/3P1P1P/R1B4R w - - 0 17", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H1 : constant Integer := Move_Validation.Square_Of (1, 8);
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5);
   begin
      Search_Integration.Best_Rook_Open_File_Facing_Queen (True, Found, F, T);
      Check ("Task 6 Rook Battery: Found is True", Found);
      Check ("Task 6 Rook Battery: From is h1", F = Sq_H1);
      Check ("Task 6 Rook Battery: To is e1", T = Sq_E1);
   end;

   -- 14. Development Tempo on Queen (New Task 1: Bf1-d3 hitting Qf5)
   Put_Line ("[14/17] Testing Best_Development_Tempo_On_Queen (f1->d3 hitting Qf5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pppn1ppp/4p3/3pPq2/3P4/2N2N2/PPP2PP1/R2QKB1R w KQkq - 2 9", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F1 : constant Integer := Move_Validation.Square_Of (1, 6);
      Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4);
   begin
      Search_Integration.Best_Development_Tempo_On_Queen (True, Found, F, T);
      Check ("New Task 1 Bd3 Tempo: Found is True", Found);
      Check ("New Task 1 Bd3 Tempo: From is f1", F = Sq_F1);
      Check ("New Task 1 Bd3 Tempo: To is d3", T = Sq_D3);
   end;

   -- 15. Ensnaring Overextended Queen (New Task 2: Nc3-e2 cutting off Qg4)
   Put_Line ("[15/17] Testing Best_Ensnare_Overextended_Queen (c3->e2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pp1n1ppp/2p1p3/3pP3/3P2q1/2NB1N2/PPP2PP1/R2QK2R w KQkq - 2 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C3 : constant Integer := Move_Validation.Square_Of (3, 3);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_Ensnare_Overextended_Queen (True, Found, F, T);
      Check ("New Task 2 Ne2 Ensnare: Found is True", Found);
      Check ("New Task 2 Ne2 Ensnare: From is c3", F = Sq_C3);
      Check ("New Task 2 Ne2 Ensnare: To is e2", T = Sq_E2);
   end;

   -- 16. Rook Attacking Infiltrated Queen (New Tasks 3 & 4: Rh1-h2 & Rh4-h2)
   Put_Line ("[16/17] Testing Best_Rook_Attack_On_Infiltrated_Queen (h1->h2 & h4->h2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pp1n1ppB/2p1p3/3pP3/3P4/2N2N2/PPP2Pq1/R2QK2R w KQkq - 0 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H1 : constant Integer := Move_Validation.Square_Of (1, 8);
      Sq_H2 : constant Integer := Move_Validation.Square_Of (2, 8);
   begin
      Search_Integration.Best_Rook_Attack_On_Infiltrated_Queen (True, Found, F, T);
      Check ("New Task 3 Rh2 Attack: Found is True", Found);
      Check ("New Task 3 Rh2 Attack: From is h1", F = Sq_H1);
      Check ("New Task 3 Rh2 Attack: To is h2", T = Sq_H2);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pp1n1p1B/2p1p3/3pP1p1/3P3R/2N2N2/PPP2Pq1/R2QK3 w Qkq g6 0 13", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H4 : constant Integer := Move_Validation.Square_Of (4, 8);
      Sq_H2 : constant Integer := Move_Validation.Square_Of (2, 8);
   begin
      Search_Integration.Best_Rook_Attack_On_Infiltrated_Queen (True, Found, F, T);
      Check ("New Task 4 Rh2 Retreat Attack: Found is True", Found);
      Check ("New Task 4 Rh2 Retreat Attack: From is h4", F = Sq_H4);
      Check ("New Task 4 Rh2 Retreat Attack: To is h2", T = Sq_H2);
   end;

   -- 17. Central King Step Behind Trapped Queen (New Tasks 5 & 6: Ke1-e2)
   Put_Line ("[17/17] Testing Best_King_Step_To_Trap_Queen (e1->e2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pp1n1p2/2p1p3/3pP3/3P3p/2NB1N2/PPP2Pq1/R2QK3 w Qkq - 0 14", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_King_Step_To_Trap_Queen (True, Found, F, T);
      Check ("New Task 5 Ke2 King Step: Found is True", Found);
      Check ("New Task 5 Ke2 King Step: From is e1", F = Sq_E1);
      Check ("New Task 5 Ke2 King Step: To is e2", T = Sq_E2);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pp1n1p2/2p1p3/3pP3/3P4/1PNB1N1p/P1P2Pq1/R2QK3 w Qkq - 0 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_King_Step_To_Trap_Queen (True, Found, F, T);
      Check ("New Task 6 Ke2 King Step (h3): Found is True", Found);
      Check ("New Task 6 Ke2 King Step (h3): From is e1", F = Sq_E1);
      Check ("New Task 6 Ke2 King Step (h3): To is e2", T = Sq_E2);
   end;

   -- 18. Discovered Attack on Queen (Task 4: Nd7-f6 hitting Qe6 via Bc8)
   Put_Line ("[18/21] Testing Discovered Attack on Queen (d7->f6 hitting Qe6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk2r/pp1nb1p1/2p1Q2p/8/3P4/2N1PN2/PP3PPP/R3K2R b KQkq - 0 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D7 : constant Integer := Move_Validation.Square_Of (7, 4);
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
   begin
      Search_Integration.Best_Development_Tempo_On_Queen (False, Found, F, T);
      Check ("Task 4 Discovered Attack: Found is True", Found);
      Check ("Task 4 Discovered Attack: From is d7", F = Sq_D7);
      Check ("Task 4 Discovered Attack: To is f6", T = Sq_F6);
   end;

   -- 19. Direct Tempo Attack on Queen (Task 3: Nd7-f6 hitting Qh7)
   Put_Line ("[19/21] Testing Direct Attack on Queen (d7->f6 hitting Qh7)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk3/pp1n1rpQ/2p4p/8/1b1P4/2N1PN2/PP3PPP/R2K3R b q - 6 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D7 : constant Integer := Move_Validation.Square_Of (7, 4);
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
   begin
      Search_Integration.Best_Development_Tempo_On_Queen (False, Found, F, T);
      Check ("Task 3 Direct Attack: Found is True", Found);
      Check ("Task 3 Direct Attack: From is d7", F = Sq_D7);
      Check ("Task 3 Direct Attack: To is f6", T = Sq_F6);
   end;

   -- 20. Central Bishop Reorganization against Queen (Task 5: Be7-d6)
   Put_Line ("[20/21] Testing Central Bishop Reorganization (e7->d6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk3/pp1nbrpQ/2p4p/8/3P4/2N1PN2/PP3PPP/R3K2R b KQq - 4 14", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
      Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4);
   begin
      Search_Integration.Best_Development_Tempo_On_Queen (False, Found, F, T);
      Check ("Task 5 Bishop Reorganization: Found is True", Found);
      Check ("Task 5 Bishop Reorganization: From is e7", F = Sq_E7);
      Check ("Task 5 Bishop Reorganization: To is d6", T = Sq_D6);
   end;

   -- 21. Queen's Gambit Declined (Task 6: e7-e6 over d5xc4)
   Put_Line ("[21/21] Testing Flank Gambit Offer Detection & QGD (e7->e6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2", Dummy_White);

   declare
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4);
      Sq_C4 : constant Integer := Move_Validation.Square_Of (4, 3);
      Is_Gambit : Boolean;
      Found     : Boolean := False;
      F, T      : Integer := 0;
      Sq_E7     : constant Integer := Move_Validation.Square_Of (7, 5);
      Sq_E6     : constant Integer := Move_Validation.Square_Of (6, 5);
   begin
      Is_Gambit := Search_Integration.Is_Flank_Gambit_Pawn_Offer (False, Sq_D5, Sq_C4);
      Check ("Task 6 Flank Gambit Offer: Is_Flank_Gambit_Pawn_Offer is True", Is_Gambit);

      Search_Integration.Best_Natural_Development (False, Found, F, T);
      Check ("Task 6 QGD Development: Found is True", Found);
      Check ("Task 6 QGD Development: From is e7", F = Sq_E7);
      Check ("Task 6 QGD Development: To is e6", T = Sq_E6);
   end;


   -- 22. Samisch King's Indian Central Pawn Strike (Task 1: c7 to c5)
   Put_Line ("[22/25] Testing Samisch KID Central Pawn Strike (c7 to c5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbq1rk1/ppp1ppbp/3p1np1/6B1/2PPP3/2N2P2/PP4PP/R2QKBNR b KQ - 2 6", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C7 : constant Integer := Move_Validation.Square_Of (7, 3);
      Sq_C5 : constant Integer := Move_Validation.Square_Of (5, 3);
   begin
      Search_Integration.Best_King_Indian_Central_Pawn_Strike (False, Found, F, T);
      Check ("Samisch KID Strike: Found is True", Found);
      Check ("Samisch KID Strike: From is c7", F = Sq_C7);
      Check ("Samisch KID Strike: To is c5", T = Sq_C5);
   end;

   -- 23. Central Pawn Wedge Strike (Task 3: c7 to c6)
   Put_Line ("[23/25] Testing Central Pawn Wedge Strike (c7 to c6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/ppp1ppbp/3p1np1/3P2B1/2P1PPn1/2N2Q2/PP4PP/R3KBNR b KQ - 2 9", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C7 : constant Integer := Move_Validation.Square_Of (7, 3);
      Sq_C6 : constant Integer := Move_Validation.Square_Of (6, 3);
   begin
      Search_Integration.Best_Central_Pawn_Wedge_Strike (False, Found, F, T);
      Check ("Wedge Strike: Found is True", Found);
      Check ("Wedge Strike: From is c7", F = Sq_C7);
      Check ("Wedge Strike: To is c6", T = Sq_C6);
   end;

   -- 24. Doubled F-Pawn Strike (Task 7: f6 to f5)
   Put_Line ("[24/25] Testing Doubled F-Pawn Strike (f6 to f5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qnrk1/pppb1p1p/3p1pp1/3P3n/2PNP3/2N2Q1P/PP4P1/R3KB1R b KQ - 1 15", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
      Sq_F5 : constant Integer := Move_Validation.Square_Of (5, 6);
   begin
      Search_Integration.Best_Doubled_F_Pawn_Strike (False, Found, F, T);
      Check ("Doubled F-Pawn Strike: Found is True", Found);
      Check ("Doubled F-Pawn Strike: From is f6", F = Sq_F6);
      Check ("Doubled F-Pawn Strike: To is f5", T = Sq_F5);
   end;

   -- 25. Benoni Queenside Flank Break (Task 8B: b7 to b5)
   Put_Line ("[25/25] Testing Benoni Queenside Flank Break (b7 to b5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/ppnb1p1p/3p1pp1/2p5/2P1P3/1NN2Q1P/PP4P1/R2K1B1R b - - 3 17", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_B7 : constant Integer := Move_Validation.Square_Of (7, 2);
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
   begin
      Search_Integration.Best_Benoni_Queenside_Break (False, Found, F, T);
      Check ("Benoni Queenside Break: Found is True", Found);
      Check ("Benoni Queenside Break: From is b7", F = Sq_B7);
      Check ("Benoni Queenside Break: To is b5", T = Sq_B5);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V099171_OUTPOST: ALL PASS");
   else
      Put_Line ("TEST_V099171_OUTPOST: FAILURES =" & Natural'Image (Failures));
   end if;

end Test_V099171_Outpost;
