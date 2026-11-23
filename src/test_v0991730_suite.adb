-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.30 TACTICAL MASTERY & OUTPOST DENIAL SUITE
--
--  Unit:          Test_V0991730_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991730_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.30 - Tactical Mastery & Outpost Denial");
   Put_Line ("========================================================");

   --  1. Best_En_Prise_Resolve: captures f6 with Bishop (Bxf6!) shattering enemy king shelter
   Put_Line ("[1/5] Best_En_Prise_Resolve plays Bxf6! shattering pawn shelter...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r4rk1/ppq2pp1/2nb1n1p/2p1p1B1/3pP1b1/1BPP1N2/PP2NPPP/1R1Q1RK1 w - - 0 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("En-prise resolve detected", Found);
      Check ("From square is g5", F_Sq = Sq ('g', '5'));
      Check ("To square is f6 (Bxf6!)", T_Sq = Sq ('f', '6'));
   end;

   --  2. Best_Knight_Outpost_Denial: denies enemy knight outpost on c4 by advancing b2-b3!
   Put_Line ("[2/5] Best_Knight_Outpost_Denial plays b2-b3! denying c4 leap...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r5k1/2q1rppp/pn1p4/1p1Pp1Pn/8/4BP2/PPPQ3P/2KR1B1R w - - 0 18", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Knight_Outpost_Denial (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Knight outpost denial detected", Found);
      Check ("From square is b2", F_Sq = Sq ('b', '2'));
      Check ("To square is b3 (b3!)", T_Sq = Sq ('b', '3'));
   end;

   --  3. Best_Central_Knight_Challenge: challenges dominating central knight with Ne2-g3!
   Put_Line ("[3/5] Best_Central_Knight_Challenge plays Ne2-g3! challenging e4...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1q2rk1/pp3pp1/2nb3p/4p3/P1Ppn2N/2P5/1P1BNPPP/1R1Q1RK1 w - - 0 20", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Central_Knight_Challenge (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Central knight challenge detected", Found);
      Check ("From square is e2", F_Sq = Sq ('e', '2'));
      Check ("To square is g3 (Ng3!)", T_Sq = Sq ('g', '3'));
   end;

   --  4. Best_Contested_File_Rook_Align: aligns rook on contested c-file with Re1-c1!
   Put_Line ("[4/5] Best_Contested_File_Rook_Align aligns rook on c-file (Rc1!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4r1k1/1pr2p2/p2p1np1/N2Pp3/1PPb3p/1R1B1P2/P5PP/1K2R3 w - - 4 25", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Contested_File_Rook_Align (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Contested file rook align detected", Found);
      Check ("From square is e1", F_Sq = Sq ('e', '1'));
      Check ("To square is c1 (Rc1!)", T_Sq = Sq ('c', '1'));
   end;

   --  5. Black mirror orientation symmetry for outpost denial
   Put_Line ("[5/10] Black mirror symmetry outpost denial (b7-b6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2kr1b1r/pppq3p/4bp2/8/1P1pP1pn/PN1P4/2Q1RPPP/R5K1 b - - 0 18", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Knight_Outpost_Denial (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Black knight outpost denial detected", Found);
      Check ("From square is b7", F_Sq = Sq ('b', '7'));
      Check ("To square is b6 (b6!)", T_Sq = Sq ('b', '6'));
   end;

   --  6. Best_Cramped_Central_Pawn_Break: breaks advanced cramping e5 pawn with d7-d6!
   Put_Line ("[6/10] Best_Cramped_Central_Pawn_Break plays d7-d6! breaking e5 cramp...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b1qrk1/1p1pbppp/p7/3QP3/3B4/8/P1PN1PPP/3R1RK1 b - - 1 14", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Cramped_Central_Pawn_Break (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Cramped central pawn break detected", Found);
      Check ("From square is d7", F_Sq = Sq ('d', '7'));
      Check ("To square is d6 (d6!)", T_Sq = Sq ('d', '6'));
   end;

   --  7. Best_Knight_Outpost_Denial (Occupied Outpost): expels knight on c5 with b7-b6!
   Put_Line ("[7/10] Best_Knight_Outpost_Denial plays b7-b6! expelling knight on c5...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1rb1qrk1/1p1p1ppp/p7/2NQP3/7b/2B5/P1P2PPP/3R1RK1 b - - 7 17", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Knight_Outpost_Denial (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Occupied outpost denial detected", Found);
      Check ("From square is b7", F_Sq = Sq ('b', '7'));
      Check ("To square is b6 (b6!)", T_Sq = Sq ('b', '6'));
   end;

   --  8. Best_Flank_Queen_Infiltration: infiltrates vulnerable queen flank with Qa8-a3!
   Put_Line ("[8/10] Best_Flank_Queen_Infiltration plays Qa8-a3! penetrating king flank...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("q2b1rk1/7p/2Np2p1/3Pp1P1/1P2P3/8/6QP/1K1R4 b - - 0 31", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Flank_Queen_Infiltration (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Flank queen infiltration detected", Found);
      Check ("From square is a8", F_Sq = Sq ('a', '8'));
      Check ("To square is a3 (Qa3!)", T_Sq = Sq ('a', '3'));
   end;

   --  9. Best_Sicilian_Najdorf_Queen_Develop: activates queen to c7 (Qd8-c7!) in Najdorf structure
   Put_Line ("[9/10] Best_Sicilian_Najdorf_Queen_Develop plays Qd8-c7! activating queen...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/3nbp2/pp1p1np1/3Pp2p/8/1N2BP2/PPPQB1PP/1K1RR3 b - - 1 15", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Sicilian_Najdorf_Queen_Develop (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Najdorf queen develop detected", Found);
      Check ("From square is d8", F_Sq = Sq ('d', '8'));
      Check ("To square is c7 (Qc7!)", T_Sq = Sq ('c', '7'));
   end;

   --  10. Best_Knight_Fork_Parry_Reposition: parries Na5-c6 fork threat with Nf6-d7!
   Put_Line ("[10/10] Best_Knight_Fork_Parry_Reposition plays Nf6-d7! covering c6 fork...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qr1k1/4bp2/p2p1np1/NpnP3p/3QP3/5B2/PPPB2PP/1K1RR3 b - - 9 21", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Knight_Fork_Parry_Reposition (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Knight fork parry reposition detected", Found);
      Check ("From square is f6", F_Sq = Sq ('f', '6'));
      Check ("To square is d7 (Nfd7!)", T_Sq = Sq ('d', '7'));
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991730_Suite;
