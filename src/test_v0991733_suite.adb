-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.33 TACTICAL BLUNDER REPAIR SUITE
--
--  Unit:          Test_V0991733_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991733_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.33 - Tactical Blunder Repair Suite");
   Put_Line ("========================================================");

   --  1. G2_M13: Best_Pinning_Bishop_Kick kicks enemy Bishop on g5 with f7-f6!
   Put_Line ("[1/14] Best_Pinning_Bishop_Kick kicks Bishop on g5 (f7-f6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k1nr/1b1p1p1p/p2bp1p1/2p3B1/4P3/2N2N2/PPP2PPP/R3R1K1 b kq - 1 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Pinning_Bishop_Kick
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Pinning bishop kick detected for Black", Found);
      Check ("From square is f7", F_Sq = Sq ('f', '7'));
      Check ("To square is f6 (f7-f6!)", T_Sq = Sq ('f', '6'));
   end;

   --  2. Mirror symmetry: White kicks enemy Bishop on g4 with f2-f3!
   Put_Line ("[2/14] White mirror: Best_Pinning_Bishop_Kick kicks Bishop on g4 (f2-f3!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3r1k1/ppp2ppp/2n2n2/4p3/2P3b1/P2BP1P1/1B1P1P1P/R3K1NR w KQ - 1 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Pinning_Bishop_Kick
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Pinning bishop kick detected for White mirror", Found);
      Check ("From square is f2", F_Sq = Sq ('f', '2'));
      Check ("To square is f3 (f2-f3!)", T_Sq = Sq ('f', '3'));
   end;

   --  3. G3_M13: Best_Queen_Fork_Counter_Attack executes 13...Qb6!
   Put_Line ("[3/14] Best_Queen_Fork_Counter_Attack executes 13...Qb6!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp1np1bp/2p1P1p1/6B1/2P3n1/2N2N2/PP4PP/R2QKB1R b KQ - 0 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Queen_Fork_Counter_Attack
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Queen fork counter-attack detected", Found);
      Check ("From square is d8", F_Sq = Sq ('d', '8'));
      Check ("To square is b6 (13...Qb6!)", T_Sq = Sq ('b', '6'));
   end;

   --  4. Mirror symmetry: White executes Qb3! counter-attacking b7 and f7
   Put_Line ("[4/14] White mirror: Best_Queen_Fork_Counter_Attack executes Qb3!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qkb1r/pp4pp/2n2n2/2p3N1/6b1/2P1p1P1/PP1NP1BP/R1BQ1RK1 w kq - 0 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Queen_Fork_Counter_Attack
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White mirror queen fork counter-attack detected", Found);
      Check ("From square is d1", F_Sq = Sq ('d', '1'));
      Check ("To square is b3 (Qb3!)", T_Sq = Sq ('b', '3'));
   end;

   --  5. G5_M24: Best_Central_Knight_Challenge plays 24...Nbc6!
   Put_Line ("[5/14] Best_Central_Knight_Challenge challenges d4 knight (24...Nbc6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb3R1/1pk5/p3p3/3pnB2/3N4/2N5/PPP1KP2/8 b - - 4 24", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Central_Knight_Challenge
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Queenside knight challenge detected", Found);
      Check ("From square is b8", F_Sq = Sq ('b', '8'));
      Check ("To square is c6 (24...Nbc6!)", T_Sq = Sq ('c', '6'));
   end;

   --  6. Mirror symmetry: White challenges d5 knight with Nb1-c3!
   Put_Line ("[6/14] White mirror: Best_Central_Knight_Challenge plays Nb1-c3!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/ppp1kp2/2n5/3n4/3PNb2/P3P3/1PK5/RNB3r1 w - - 4 24", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Central_Knight_Challenge
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White mirror knight challenge detected", Found);
      Check ("From square is b1", F_Sq = Sq ('b', '1'));
      Check ("To square is c3 (Nb1-c3!)", T_Sq = Sq ('c', '3'));
   end;

   --  7. G5_M24: Allows_Uncontested_Checking_Fork detects 25.Nxd5+ threat after e6xf5
   Put_Line ("[7/14] Allows_Uncontested_Checking_Fork detects knight check after e6xf5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb3R1/1pk5/p3p3/3pnB2/3N4/2N5/PPP1KP2/8 b - - 4 24", Dummy_White);
   declare
      Saved_T : constant Integer := Pvalidade.Tabuleiro (Sq ('f', '5'));
      Fork_Detected : Boolean;
   begin
      Pvalidade.Tabuleiro (Sq ('f', '5')) := Pvalidade.Tabuleiro (Sq ('e', '6'));
      Pvalidade.Tabuleiro (Sq ('e', '6')) := 0;
      Fork_Detected := Search_Integration.Allows_Uncontested_Checking_Fork (False);
      Pvalidade.Tabuleiro (Sq ('e', '6')) := Pvalidade.Tabuleiro (Sq ('f', '5'));
      Pvalidade.Tabuleiro (Sq ('f', '5')) := Saved_T;
      Check ("Uncontested checking fork detected after e6xf5", Fork_Detected);
   end;

   --  8. Mirror symmetry: Allows_Uncontested_Checking_Fork for White mirror
   Put_Line ("[8/14] White mirror: Allows_Uncontested_Checking_Fork detects knight check...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/ppp1kp2/2n5/3n4/3PNb2/P3P3/1PK5/RNB3r1 w - - 4 24", Dummy_White);
   declare
      Saved_T : constant Integer := Pvalidade.Tabuleiro (Sq ('f', '4'));
      Fork_Detected : Boolean;
   begin
      Pvalidade.Tabuleiro (Sq ('f', '4')) := Pvalidade.Tabuleiro (Sq ('e', '3'));
      Pvalidade.Tabuleiro (Sq ('e', '3')) := 0;
      Fork_Detected := Search_Integration.Allows_Uncontested_Checking_Fork (True);
      Pvalidade.Tabuleiro (Sq ('e', '3')) := Pvalidade.Tabuleiro (Sq ('f', '4'));
      Pvalidade.Tabuleiro (Sq ('f', '4')) := Saved_T;
      Check ("White mirror checking fork detected after e3xf4", Fork_Detected);
   end;

   --  9. G5_M8: Best_En_Prise_Resolve retreats Queen safely to e7 (Qe7!)
   Put_Line ("[9/14] Best_En_Prise_Resolve retreats Queen safely to e7 (Qe7!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/pppn1ppp/4p3/3pP1q1/3P4/2N2N2/PPP2PP1/R2QKB1R b KQkq - 1 8", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("En-prise resolve detected for Queen", Found);
      Check ("From square is g5", F_Sq = Sq ('g', '5'));
      Check ("To square is e7 (8...Qe7!)", T_Sq = Sq ('e', '7'));
   end;

   --  10. Mirror symmetry: White retreats Queen safely to e2 (Qe2!)
   Put_Line ("[10/14] White mirror: Best_En_Prise_Resolve retreats Queen safely to e2...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qkb1r/ppp2pp1/2n2n2/3p4/3Pp1Q1/4P3/PPPN1PPP/RNB1K2R w KQkq - 1 8", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White mirror en-prise resolve detected for Queen", Found);
      Check ("From square is g4", F_Sq = Sq ('g', '4'));
      Check ("To square is e2 (Qe2!)", T_Sq = Sq ('e', '2'));
   end;

   
   --  11. G1_M39: Allows_Major_Pin detects self-pin 39...Nb7?? to King on f7
   Put_Line ("[11/14] G1_M39: Allows_Major_Pin detects self-pin 39...Nb7??...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/5k2/6p1/Rpn5/8/8/PPP4P/1K6 b - - 2 39", Dummy_White);
   declare
      Pin_Detected : Boolean;
      Undef_Found  : Boolean;
      U_From, U_To : Integer;
   begin
      Pin_Detected := Search_Integration.Allows_Major_Pin
        (White_To_Move => False,
         Target_Sq     => Sq ('b', '7'),
         Attacker_Sq   => Sq ('a', '5'));
      Check ("Self-pin detected for 39...Nb7 against King on f7", Pin_Detected);

      Search_Integration.Best_Undefended_Major_Attack
        (White_To_Move => False,
         Found         => Undef_Found,
         From_Sq       => U_From,
         To_Sq         => U_To);
      Check ("Best_Undefended_Major_Attack avoids 39...Nb7",
             not (Undef_Found and then U_To = Sq ('b', '7')));
   end;

   --  12. Mirror symmetry: White mirror Allows_Major_Pin detects self-pin to King on f2
   Put_Line ("[12/14] White mirror: Allows_Major_Pin detects self-pin Nb2??...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1k6/ppp4p/8/8/rPN5/6P1/5K2/8 w - - 2 39", Dummy_White);
   declare
      Pin_Detected : Boolean;
      Undef_Found  : Boolean;
      U_From, U_To : Integer;
   begin
      Pin_Detected := Search_Integration.Allows_Major_Pin
        (White_To_Move => True,
         Target_Sq     => Sq ('b', '2'),
         Attacker_Sq   => Sq ('a', '4'));
      Check ("White mirror self-pin detected for Nb2 against King on f2", Pin_Detected);

      Search_Integration.Best_Undefended_Major_Attack
        (White_To_Move => True,
         Found         => Undef_Found,
         From_Sq       => U_From,
         To_Sq         => U_To);
      Check ("White mirror avoids self-pinning Nb2",
             not (Undef_Found and then U_To = Sq ('b', '2')));
   end;

   --  13. G4_M36: Best_Passed_Pawn_Blockade_King_Step plays 36.Kc1!
   Put_Line ("[13/14] G4_M36: Best_Passed_Pawn_Blockade_King_Step plays 36.Kc1!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/p3r1p1/8/8/1pp1r3/1P6/3Rp3/3KR3 w - - 0 36", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Passed_Pawn_Blockade_King_Step
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Passed pawn blockade king step detected for White", Found);
      Check ("From square is d1", F_Sq = Sq ('d', '1'));
      Check ("To square is c1 (36.Kc1!)", T_Sq = Sq ('c', '1'));
   end;

   --  14. Mirror symmetry: Black plays Kc8! holding blockade against e7 passed pawn
   Put_Line ("[14/14] Black mirror: Best_Passed_Pawn_Blockade_King_Step plays Kc8!...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3kr3/3rP3/1p6/1PP1R3/8/8/P3R1P1/6K1 b - - 0 36", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Passed_Pawn_Blockade_King_Step
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Black mirror passed pawn blockade king step detected", Found);
      Check ("From square is d8", F_Sq = Sq ('d', '8'));
      Check ("To square is c8 (Kc8!)", T_Sq = Sq ('c', '8'));
   end;

Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991733_Suite;
