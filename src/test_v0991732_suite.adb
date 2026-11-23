-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.32 TACTICAL BLUNDER REPAIR SUITE
--
--  Unit:          Test_V0991732_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991732_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.32 - Tactical Blunder Repair Suite");
   Put_Line ("========================================================");

   --  1. Best_En_Prise_Resolve in G3_M23: rescues Queen on d1 (d1f3 / d1e1)
   Put_Line ("[1/10] Best_En_Prise_Resolve rescues Queen on d1 (d1f3/d1e1)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2r2k1/pp3ppp/4p3/4P3/bq3P2/1B6/P5PP/R2Q1R1K w - - 0 23", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("En-prise resolve detected for Queen", Found);
      Check ("From square is d1", F_Sq = Sq ('d', '1'));
      Check ("To square is safe rescue f3 or e1",
             T_Sq = Sq ('f', '3') or else T_Sq = Sq ('e', '1'));
   end;

   --  2. Mirror symmetry: Black Queen rescue on d8
   Put_Line ("[2/10] Black mirror: Best_En_Prise_Resolve rescues Queen on d8...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1r1k/p5pp/1b6/bq3p2/4p3/4P3/PP3PPP/R2R2K1 b - - 0 23", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Black mirror en-prise resolve detected", Found);
      Check ("From square is d8", F_Sq = Sq ('d', '8'));
      Check ("To square is safe rescue f6 or e8",
             T_Sq = Sq ('f', '6') or else T_Sq = Sq ('e', '8'));
   end;

   --  3. Best_En_Prise_Resolve in G5_M17: Bishop on b5 retreats to c4 (Bc4!)
   Put_Line ("[3/10] Best_En_Prise_Resolve retreats bishop safely to c4 (Bc4!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b2rk1/pp3pp1/1q2pb1p/1B6/3P4/1P3N2/P1Q2PPP/R4RK1 w - - 0 17", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("En-prise resolve detected for Bishop", Found);
      Check ("From square is b5", F_Sq = Sq ('b', '5'));
      Check ("To square is c4 (Bc4!)", T_Sq = Sq ('c', '4'));
   end;

   --  4. Mirror symmetry: Black Bishop on b4 retreats to c5 (Bc5!)
   Put_Line ("[4/10] Black mirror: Best_En_Prise_Resolve retreats bishop to c5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r4rk1/p1q2ppp/1p3n2/3p4/1b6/1Q2PB1P/PP3PP1/R1B2RK1 b - - 0 17", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Black mirror en-prise resolve detected", Found);
      Check ("From square is b4", F_Sq = Sq ('b', '4'));
      Check ("To square is c5 (Bc5!)", T_Sq = Sq ('c', '5'));
   end;

   --  5. G1_M27: Pawn self-hang prevention on a3
   Put_Line ("[5/10] Pawn self-hang check: a2-a3 is recognized as losing material...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3r1rk1/1p3pb1/3p3p/p2Pp1p1/1qPpR1P1/1P1P3N/P1RQ1P1P/6K1 w - - 2 27", Dummy_White);
   declare
      --  Simulate a2-a3 push onto board
      Gain : Integer;
   begin
      Pvalidade.Tabuleiro (Sq ('a', '3')) := 1;
      Pvalidade.Tabuleiro (Sq ('a', '2')) := 0;
      Gain := Search_Integration.See_Gain
        (White_Captures => False, From_Sq => Sq ('b', '4'), To_Sq => Sq ('a', '3'));
      Pvalidade.Tabuleiro (Sq ('a', '2')) := 1;
      Pvalidade.Tabuleiro (Sq ('a', '3')) := 0;
      Check ("Enemy Queen wins hanging pawn on a3 (SEE > 0)", Gain > 0);
   end;

   --  6. Mirror symmetry: Black pawn self-hang on a6
   Put_Line ("[6/10] Black mirror: pawn self-hang on a6 recognized...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/p1rq1p1p/1p1p3n/1Q1Pr3/1PpPr1p1/3p3P/1P3PB1/3R1RK1 b - - 2 27", Dummy_White);
   declare
      Gain : Integer;
   begin
      Pvalidade.Tabuleiro (Sq ('a', '6')) := -1;
      Pvalidade.Tabuleiro (Sq ('a', '7')) := 0;
      Gain := Search_Integration.See_Gain
        (White_Captures => True, From_Sq => Sq ('b', '5'), To_Sq => Sq ('a', '6'));
      Pvalidade.Tabuleiro (Sq ('a', '7')) := -1;
      Pvalidade.Tabuleiro (Sq ('a', '6')) := 0;
      Check ("White Queen wins hanging pawn on a6 (SEE > 0)", Gain > 0);
   end;

   --  7. G4_M12: Queenside castling into semi-open c-file vetoed
   Put_Line ("[7/10] Is_Castling_Into_Open_File vetoes queenside castling (O-O-O)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b2rk1/ppp2ppp/2n1pq2/8/2pP4/P3B3/1P1QPPPP/R3KB1R w KQ - 0 12", Dummy_White);
   declare
      Vetoed : constant Boolean :=
        Search_Integration.Is_Castling_Into_Open_File
          (White_To_Move => True, F => Sq ('e', '1'), T => Sq ('c', '1'));
   begin
      Check ("Queenside castling into semi-open c-file is vetoed", Vetoed);
   end;

   --  8. Mirror symmetry: Black queenside castling into semi-open c-file vetoed
   Put_Line ("[8/10] Black mirror: Queenside castling into semi-open c-file vetoed...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3kb1r/1p1qpppp/p3b3/2Pp4/8/2N1PQ2/PPP2PPP/R1B2RK1 b kq - 0 12", Dummy_White);
   declare
      Vetoed : constant Boolean :=
        Search_Integration.Is_Castling_Into_Open_File
          (White_To_Move => False, F => Sq ('e', '8'), T => Sq ('c', '8'));
   begin
      Check ("Black queenside castling into semi-open c-file is vetoed", Vetoed);
   end;

   --  9. G2_M13: King pawn shield protection avoids c2-c4
   Put_Line ("[9/10] King pawn shield protection avoids c2-c4 with King on c1...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qkb1r/1p3p2/pn1p1np1/3Pp2p/8/1N2BP2/PPPQ2PP/2KR1B1R w kq - 2 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Defend_Central_Pawn
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Best_Defend_Central_Pawn does not play c2-c4",
             not (Found and then F_Sq = Sq ('c', '2') and then T_Sq = Sq ('c', '4')));
   end;

   --  10. G2_M20: Best_King_Unpin_Step avoids dangerous king step to a1
   Put_Line ("[10/10] Best_King_Unpin_Step avoids dangerous step to a1...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2q1k2r/1p2bp2/pB1p1np1/1r1Pp2p/8/1N2QP2/PP4PP/1K1RR3 w k - 8 20", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_King_Unpin_Step
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("King on b1 does not step to a1",
             not (Found and then F_Sq = Sq ('b', '1') and then T_Sq = Sq ('a', '1')));
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991732_Suite;
