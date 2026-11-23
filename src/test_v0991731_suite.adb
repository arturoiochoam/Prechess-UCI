-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.31 TACTICAL PRECISION & PIN-BREAK SUITE
--
--  Unit:          Test_V0991731_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991731_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.31 - Tactical Precision & Pin-Break");
   Put_Line ("========================================================");

   --  1. Best_En_Prise_Resolve: avoids trapped rim square h5, chooses active central Ng4!
   Put_Line ("[1/10] Best_En_Prise_Resolve plays 11... Ng4! avoiding trapped rim h5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp1nppbp/2p2np1/3PP1B1/2P5/2N2N2/PP4PP/R2QKB1R b KQ - 0 11", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("En-prise resolve detected", Found);
      Check ("From square is f6", F_Sq = Sq ('f', '6'));
      Check ("To square is g4 (Ng4!)", T_Sq = Sq ('g', '4'));
   end;

   --  2. Best_King_Unpin_Step: steps off pinned file with Kf7! unpinning knight on f6
   Put_Line ("[2/10] Best_King_Unpin_Step plays 28... Kf7! unpinning Nf6...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rn3r2/6k1/1Rb1pn2/3p4/p2P2p1/P1NB2R1/2PN2P1/6K1 b - - 0 28", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_King_Unpin_Step (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("King unpin step detected", Found);
      Check ("From square is g7", F_Sq = Sq ('g', '7'));
      Check ("To square is f7 (Kf7!)", T_Sq = Sq ('f', '7'));
   end;

   --  3. Best_Pinning_Bishop_Kick: kicks pinning bishop on b5 with a7-a6!
   Put_Line ("[3/10] Best_Pinning_Bishop_Kick plays 9... a6! expelling pinning Bb5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/pppn1ppp/4p3/1B1pP3/3P4/2N2N2/PPP2PP1/R2QK2R b KQkq - 3 9", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Pinning_Bishop_Kick (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Pinning bishop kick detected", Found);
      Check ("From square is a7", F_Sq = Sq ('a', '7'));
      Check ("To square is a6 (a6!)", T_Sq = Sq ('a', '6'));
   end;

   --  4. Best_Attacked_Queen_Zwischenzug_Push: counter-attacks enemy queen with c5-c4!
   Put_Line ("[4/10] Best_Attacked_Queen_Zwischenzug_Push plays 14... c4! hitting Qb3...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3kb1r/pp1q1pp1/1n2p2p/2p1N3/3P4/1QN1P3/PP3PPP/R4RK1 b kq - 1 14", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Attacked_Queen_Zwischenzug_Push (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Queen counter-attack push detected", Found);
      Check ("From square is c5", F_Sq = Sq ('c', '5'));
      Check ("To square is c4 (c4!)", T_Sq = Sq ('c', '4'));
   end;

   --  5. Best_Rook_Cramping_Pawn_Pressure: shifts rook along 5th rank to Rb5! attacking e5
   Put_Line ("[5/10] Best_Rook_Cramping_Pawn_Pressure plays 28... Rb5! attacking e5 cramp...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("5rk1/5p2/1r2p3/4P1p1/8/8/PP1R2PP/5RK1 b - - 0 28", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Rook_Cramping_Pawn_Pressure (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Rook cramping pawn pressure detected", Found);
      Check ("From square is b6", F_Sq = Sq ('b', '6'));
      Check ("To square is b5 (Rb5!)", T_Sq = Sq ('b', '5'));
   end;

   --  6. Mirror symmetry: White King Unpin Step (Kg2-f2!)
   Put_Line ("[6/10] White mirror: Best_King_Unpin_Step plays Kg2-f2! unpinning Nf3...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/2pn2p1/p1nb2r1/3p4/p2P2P1/1rB1PN2/6K1/RN3R2 w - - 0 28", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_King_Unpin_Step (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White king unpin step detected", Found);
      Check ("From square is g2", F_Sq = Sq ('g', '2'));
      Check ("To square is f2 (Kf2!)", T_Sq = Sq ('f', '2'));
   end;

   --  7. Mirror symmetry: White Pinning Bishop Kick (a2-a3!)
   Put_Line ("[7/10] White mirror: Best_Pinning_Bishop_Kick plays a2-a3! kicking Bb4...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk2r/ppp2pp1/2n2n2/3p4/1b1Pp3/4P3/PPPN1PPP/R1BQK2R w KQkq - 3 9", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Pinning_Bishop_Kick (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White pinning bishop kick detected", Found);
      Check ("From square is a2", F_Sq = Sq ('a', '2'));
      Check ("To square is a3 (a3!)", T_Sq = Sq ('a', '3'));
   end;

   --  8. Mirror symmetry: White Attacked Queen Zwischenzug Push (c4-c5!)
   Put_Line ("[8/10] White mirror: Best_Attacked_Queen_Zwischenzug_Push plays c4-c5! hitting Qb6...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r4rk1/pp3ppp/1qn1p3/3p4/2P1n3/1N2P2P/PP1Q1PP1/R3KB1R w KQ - 1 14", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Attacked_Queen_Zwischenzug_Push (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White queen counter-attack push detected", Found);
      Check ("From square is c4", F_Sq = Sq ('c', '4'));
      Check ("To square is c5 (c5!)", T_Sq = Sq ('c', '5'));
   end;

   --  9. Mirror symmetry: White Rook Cramping Pawn Pressure (Rb3-b4!)
   Put_Line ("[9/10] White mirror: Best_Rook_Cramping_Pawn_Pressure plays Rb3-b4! attacking e4...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("5rk1/pp1r2pp/8/8/4p1P1/1R2P3/5P2/5RK1 w - - 0 28", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Rook_Cramping_Pawn_Pressure (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White rook cramping pressure detected", Found);
      Check ("From square is b3", F_Sq = Sq ('b', '3'));
      Check ("To square is b4 (Rb4!)", T_Sq = Sq ('b', '4'));
   end;

   --  10. Mirror symmetry: White En-Prise Resolve (Nf3-g5!)
   Put_Line ("[10/10] White mirror: Best_En_Prise_Resolve plays Nf3-g5! avoiding rim h4...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qkb1r/pp4pp/2n2n2/2p5/3pp1b1/2P2NP1/PP1NPPBP/R1BQ1RK1 w kq - 0 11", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("White en-prise resolve detected", Found);
      Check ("From square is f3", F_Sq = Sq ('f', '3'));
      Check ("To square is g5 (Ng5!)", T_Sq = Sq ('g', '5'));
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991731_Suite;
