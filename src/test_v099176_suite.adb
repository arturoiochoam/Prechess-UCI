-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.6 TACTICAL REPAIR & RELATIVE PIN ESCAPE TEST SUITE
--
--  Unit:          Test_V099176_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099176_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.6 - Tactical Repair & Pin Suite     ");
   Put_Line ("========================================================");

   -- 1. Test Task 2 Move 7: Piece Recapture Priority over King
   -- In French Steinitz (7. Bxe7), Black must play 7... Qxe7 (d8e7), NOT 7... Kxe7 (e8e7)
   Put_Line ("[1/4] Testing Move 7: Piece Recapture Priority (Qxe7 over Kxe7)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppnBpp1/4p2p/3pP3/3P3P/2N5/PPP2PP1/R2QKBNR b KQkq - 0 7", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Sq_E8 : constant Integer := Move_Validation.Square_Of (8, 5);
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
   begin
      Search_Integration.Best_Winning_Capture (False, Found, F, T);
      Check ("Move 7: Best_Winning_Capture must find recapture on e7", Found and then T = Sq_E7);
      Check ("Move 7: Recapturing piece must be Queen (d8), not King (e8)", F = Sq_D8);
   end;

   -- 2. Test Task 3A Move 21: Relative Pin Escape & Counter-Threat (21... Qc5!)
   -- Bishop on e6 is pinned to Queen on e7 along e-file by Re1 and attacked by Nd4.
   -- Best_En_Prise_Resolve must break the pin via 21... Qc5! (counter-attacking Nd4 and Bb5).
   Put_Line ("[2/4] Testing Move 21: Relative Pin Escape & Counter-Threat (21... Qc5!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r5k1/pp2qr1p/4bp2/nB1p3Q/3N4/P7/2P2PPP/R2KR3 b - - 5 21", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
      Sq_C5 : constant Integer := Move_Validation.Square_Of (5, 3);
      Sq_E6 : constant Integer := Move_Validation.Square_Of (6, 5);
      Sq_G4 : constant Integer := Move_Validation.Square_Of (4, 7);
   begin
      -- Verify e6g4 is identified as unsafe (hanged to Qxg4)
      Check ("Move 21: e6g4 is NOT deep material safe (hangs bishop to Qxg4)",
             not Search_Integration.Is_Deep_Material_Safe_60 (False, Sq_E6, Sq_G4));

      -- Verify e7c5 is safe
      Check ("Move 21: e7c5 is deep material safe",
             Search_Integration.Is_Deep_Material_Safe_60 (False, Sq_E7, Sq_C5));

      -- Verify Best_En_Prise_Resolve selects e7c5
      Search_Integration.Best_En_Prise_Resolve (False, Found, F, T);
      Check ("Move 21: Best_En_Prise_Resolve must resolve the relative pin", Found);
      Check ("Move 21: Best_En_Prise_Resolve must choose e7c5 (Stockfish move)",
             F = Sq_E7 and then T = Sq_C5);
   end;

   -- 3. Test Task 1 Move 22: Tactical Winning Capture (22. Qxd2)
   -- Black Knight on d2 is undefended and attacked by Queen on d1.
   Put_Line ("[3/4] Testing Move 22: Winning Capture of undefended Knight (22. Qxd2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1r1q1r2/2p2ppk/5n1p/p3p3/P1P1P1b1/R4N2/3n1PPP/1B1Q1RK1 w - - 0 22", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D1 : constant Integer := Move_Validation.Square_Of (1, 4);
      Sq_D2 : constant Integer := Move_Validation.Square_Of (2, 4);
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Move 22: Best_Winning_Capture must find d1xd2", Found and then F = Sq_D1 and then T = Sq_D2);
   end;

   -- 4. Test Task 4 Move 17: Anti-Blunder Check (Avoiding 17. Na5??)
   Put_Line ("[4/6] Testing Move 17: Prevention of 17. Na5 blunder...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rbbq1r2/1pp1np1k/3p3p/3Bp2n/p1P1P1pN/1N1P2B1/PP3PPP/R2Q1RK1 w - - 0 17", Dummy_White);

   declare
      Sq_B3 : constant Integer := Move_Validation.Square_Of (3, 2);
      Sq_A5 : constant Integer := Move_Validation.Square_Of (5, 1);
   begin
      Check ("Move 17: 17. Na5 is unsafe/hanging against 17... c6",
             Search_Integration.Max_Opponent_See_After (True, Sq_B3, Sq_A5) > 0);
   end;

   -- 5. Test Fried Liver Move 11: Queen En Prise Rescue (11. Qb3 vs 11. O-O??)
   -- Queen on h3 is attacked by Bishop on c8 along open diagonal.
   -- Best_En_Prise_Resolve must rescue the Queen via 11. Qb3!
   Put_Line ("[5/6] Testing Fried Liver Move 11: Queen Rescue (11. Qb3 vs 11. O-O??)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/2k5/3np3/1nB1N3/7Q/PPPP1PPP/R1B1K2R w KQ - 8 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H3 : constant Integer := Move_Validation.Square_Of (3, 8); -- 24
      Sq_B3 : constant Integer := Move_Validation.Square_Of (3, 2); -- 18
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5); -- 5
      Sq_G1 : constant Integer := Move_Validation.Square_Of (1, 7); -- 7
      Pre_Hang : constant Integer := Search_Integration.Max_Opponent_See (True);
      After_Castle : constant Integer := Search_Integration.Max_Opponent_See_After (True, Sq_E1, Sq_G1);
      After_Qb3    : constant Integer := Search_Integration.Max_Opponent_See_After (True, Sq_H3, Sq_B3);
   begin
      Check ("Move 11: Pre-move threat detects Queen on h3 under attack", Pre_Hang >= 500);
      Check ("Move 11: After castling e1-g1, Queen remains attacked", After_Castle >= 500);
      Check ("Move 11: After Qb3, Queen is completely safe", After_Qb3 = 0);
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Move 11: Best_En_Prise_Resolve rescues the Queen", Found and then F = Sq_H3 and then T = Sq_B3);
   end;

   -- 6. Test Fried Liver Move 9: Non-Defense Spite Check Veto (Qh3+ does not defend c2)
   -- Pawn on c2 is attacked by Knight on b4. Spite check Qh3+ must NOT be chosen as pawn defense.
   Put_Line ("[6/9] Testing Fried Liver Move 9: Spite Check Veto on c2 hang...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/4k3/3np3/1nB5/2N2Q2/PPPP1PPP/R1B1K2R w KQ - 4 9", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F3 : constant Integer := Move_Validation.Square_Of (3, 6);
      Sq_H3 : constant Integer := Move_Validation.Square_Of (3, 8);
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Move 9: Best_En_Prise_Resolve does not choose spite check Qh3+",
             not (Found and then F = Sq_F3 and then T = Sq_H3));
   end;

   -- 7. Test Task 4 Move 11: Minor Piece Exchange & Equal Trade Safety (11. Bxd4 vs 11. Qd1??)
   -- Black Knight on d4 attacks Queen on f3; Bishop on e3 captures d4 with equal minor trade.
   Put_Line ("[7/9] Testing Task 4 Move 11: Minor Piece Exchange (11. Bxd4)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/ppqbbppp/3ppn2/8/2BnPP2/2N1BQ2/PPP3PP/R4RK1 w kq - 0 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E3 : constant Integer := Move_Validation.Square_Of (3, 5);
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4);
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Task 4 Move 11: Best_En_Prise_Resolve finds e3xd4", Found and then F = Sq_E3 and then T = Sq_D4);
      Check ("Task 4 Move 11: e3xd4 is deep material safe",
             Search_Integration.Is_Deep_Material_Safe_60 (True, Sq_E3, Sq_D4));
   end;

   -- 8. Test Task 1 Move 11: Check Evasion Interposition with Tempo (11. Bd2 vs 11. Kf1)
   -- Queen on c3 gives check; Bishop on e3 interposes on d2 counter-attacking the Queen.
   Put_Line ("[8/9] Testing Task 1 Move 11: Check Evasion Interposition with Tempo (11. Bd2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k1nr/pp2pp1p/2nPb1p1/8/4P3/2q1B1P1/P1P2PBP/R2QK1NR w KQkq - 0 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_E3 : constant Integer := Move_Validation.Square_Of (3, 5);
      Sq_D2 : constant Integer := Move_Validation.Square_Of (2, 4);
   begin
      Search_Integration.Best_Check_Evasion (True, Found, F, T);
      Check ("Task 1 Move 11: Best_Check_Evasion chooses Bd2 (e3->d2) with tempo",
             Found and then F = Sq_E3 and then T = Sq_D2);
   end;

   -- 9. Test Task 5 Move 13: Decisive Tactical Pawn Capture Attacking Major Piece (13... Qxg2)
   -- Black Queen on d5 takes g2, creating an immediate winning threat on White's undefended Rook on h1.
   Put_Line ("[9/9] Testing Task 5 Move 13: Tactical Capture Attacking Major Piece (13... Qxg2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b4r/ppp1bkpp/8/3qp3/8/2Q5/PPPP1PPP/R1B1K2R b KQ - 3 13", Dummy_White);

   declare
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4);
      Sq_G2 : constant Integer := Move_Validation.Square_Of (2, 7);
      Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5);
   begin
      Check ("Task 5 Move 13: See_Gain captures pawn on g2 cleanly",
             Search_Integration.See_Gain (False, Sq_D5, Sq_G2) = 100);
      Check ("Task 5 Move 13: Creates_Major_Threat verifies threat on Rh1",
             Search_Integration.Creates_Major_Threat (False, Sq_D5, Sq_G2));
      Check ("Task 5 Move 13: Creates_Major_Threat is False for quiet move",
             not Search_Integration.Creates_Major_Threat (False, Sq_D5, Sq_E5));
   end;

   -- 10. Test Task 1 Move 13: Major Exchange Recapture (13. Bxh7 over 13. Bb5)
   Put_Line ("[10/13] Testing Task 1 Move 13: Rook Recapture on h7 (13. Bxh7)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k3/pppn1ppr/4p3/3pP3/3P4/3B1q2/PPP1NP2/R2QK3 w Qq - 0 13", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4);
      Sq_H7 : constant Integer := Move_Validation.Square_Of (7, 8);
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Task 1 Move 13: Best_Winning_Capture finds Rook recapture", Found and then F = Sq_D3 and then T = Sq_H7);
      Check ("Task 1 Move 13: See_Gain on h7 is 500 cp (winning exchange)",
             Search_Integration.See_Gain (True, Sq_D3, Sq_H7) = 500);
   end;

   -- 11. Test Task 4 Move 22: Minor Piece Recapture on f3 (22. Bxf3 over 22. Bc3)
   Put_Line ("[11/13] Testing Task 4 Move 22: Minor Piece Recapture (22. Bxf3)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2kr2r1/1p3p1p/p1n3p1/P4n2/7P/5bP1/3B1PB1/R4RK1 w - - 0 22", Dummy_White);

   declare
      Sq_G2 : constant Integer := Move_Validation.Square_Of (2, 7);
      Sq_F3 : constant Integer := Move_Validation.Square_Of (3, 6);
      Sq_D2 : constant Integer := Move_Validation.Square_Of (2, 4);
      Sq_C3 : constant Integer := Move_Validation.Square_Of (3, 3);
   begin
      Check ("Task 4 Move 22: See_Gain of g2xf3 is positive (+330 cp)",
             Search_Integration.See_Gain (True, Sq_G2, Sq_F3) >= 300);
      Check ("Task 4 Move 22: d2c3 is a quiet move (Gain = 0 cp)",
             Search_Integration.See_Gain (True, Sq_D2, Sq_C3) = 0);
   end;

   -- 12. Test Task 1 Move 11: Infiltrated Queen Protection Veto (Avoid 11. Rh2??)
   Put_Line ("[12/13] Testing Task 1 Move 11: Anti-Hang Veto on 11. Rh2...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pppn1ppp/4p3/3pP3/3P4/3B1N2/PPP1N1q1/R2QK2R w KQkq - 0 11", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H1 : constant Integer := Move_Validation.Square_Of (1, 8);
      Sq_H2 : constant Integer := Move_Validation.Square_Of (2, 8);
      Sq_F1 : constant Integer := Move_Validation.Square_Of (1, 6);
   begin
      Search_Integration.Best_Rook_Attack_On_Infiltrated_Queen (True, Found, F, T);
      Check ("Task 1 Move 11: Best_Rook_Attack_On_Infiltrated_Queen rejects h1h2 due to hanging Nf3",
             not (Found and then F = Sq_H1 and then T = Sq_H2));
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Task 1 Move 11: Best_En_Prise_Resolve protects piece via 11. Rf1",
             Found and then F = Sq_H1 and then T = Sq_F1);
   end;

   -- 13. Test Task 3 Move 20: Counter-Attack Piece Capture (20. exf6)
   Put_Line ("[13/13] Testing Task 3 Move 20: Counter-Attack Piece Capture (20. exf6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/pp1rQppp/5n2/q3P3/1nr1P1b1/2N1B3/PPP3PP/1R3RK1 w - - 3 20", Dummy_White);

   declare
      Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5);
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
   begin
      Check ("Task 3 Move 20: e5xf6 captures Knight (+320 cp)",
             Search_Integration.See_Gain (True, Sq_E5, Sq_F6) = 320);
      Check ("Task 3 Move 20: e5xf6 is Deep Material Safe",
             Search_Integration.Is_Deep_Material_Safe_60 (True, Sq_E5, Sq_F6));
   end;

   Put_Line ("========================================================");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY!");
   else
      Put_Line ("TOTAL FAILURES: " & Natural'Image (Failures));
   end if;
   Put_Line ("========================================================");

end Test_V099176_Suite;
