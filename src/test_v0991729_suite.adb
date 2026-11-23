-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.29 TACTICAL DEFENSE & KING HARMONY SUITE
--
--  Unit:          Test_V0991729_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991729_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.29 - Tactical Defense & Harmony");
   Put_Line ("========================================================");

   --  1. Best_Queen_Skewer_Escape: avoids blunder by safely tucking Queen to f3
   Put_Line ("[1/5] Best_Queen_Skewer_Escape resolves diagonal skewer...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4rrk1/1pqbbp2/p1n3pp/2p5/4QP2/1PNBP2P/P2N2P1/2R2RK1 w - - 0 22", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Queen_Skewer_Escape (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Skewer escape detected", Found);
      Check ("From square is e4", F_Sq = Sq ('e', '4'));
      Check ("To square is f3 (Qf3!)", T_Sq = Sq ('f', '3'));
   end;

   --  2. Best_Opening_Quiet_Alternative: develops Knight to h3 when f3 blocked
   Put_Line ("[2/5] Best_Opening_Quiet_Alternative develops Nh3...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp1n1pb1/2pp1npp/3Pp3/2P1P3/2N2P2/PP1BB1PP/R2QK1NR w KQ - 0 10", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Opening_Quiet_Alternative (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Quiet alternative detected", Found);
      Check ("From square is g1", F_Sq = Sq ('g', '1'));
      Check ("To square is h3 (Nh3!)", T_Sq = Sq ('h', '3'));
   end;

   --  3. Best_King_Pin_Shield: pushes pawn to e5 to shield pinned pawn f4
   Put_Line ("[3/5] Best_King_Pin_Shield shields pinned pawn with e5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1r3rk1/2qb1p2/7p/2p3p1/1nBbPP2/1P3Q1P/6PK/1N2RR2 w - - 0 35", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_King_Pin_Shield (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Pin shield detected", Found);
      Check ("From square is e4", F_Sq = Sq ('e', '4'));
      Check ("To square is e5 (e5!)", T_Sq = Sq ('e', '5'));
   end;

   --  4. Best_Central_King_Safety_Tuck: tucks King to g2 to connect rooks
   Put_Line ("[4/5] Best_Central_King_Safety_Tuck tucks King Kf1-g2...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r4rk1/pp1b1pb1/1q1p1n1p/2nPp1p1/4P3/1PN2BPP/P2BQ3/R4KNR w - - 1 19", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Central_King_Safety_Tuck (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("King tuck detected", Found);
      Check ("From square is f1", F_Sq = Sq ('f', '1'));
      Check ("To square is g2 (Kg2!)", T_Sq = Sq ('g', '2'));
   end;

   --  5. Black mirror orientation symmetry
   Put_Line ("[5/5] Black mirror symmetry verification...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk1nr/pp1bb1pp/2n2p2/2p1p3/3pP3/2PP1NPP/PP1N1PB1/R1BQ1RK1 b kq - 0 10", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Opening_Quiet_Alternative (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Black quiet alternative detected", Found);
      Check ("From square is g8", F_Sq = Sq ('g', '8'));
      Check ("To square is h6 (Nh6!)", T_Sq = Sq ('h', '6'));
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991729_Suite;
