-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 CENTRAL PAWN FORK STRIKE SUITE
--
--  Unit:          Test_V099171_Fork_Strike
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI Architectural Verification)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature: Best_Central_Pawn_Fork_Strike:
--     - Position 1 (Move 7 blunder):
--       r1bqk2r/pp2ppbp/2np1np1/2p5/4P3/2NPB1PB/PPP2P1P/R2QK1NR b KQkq - 3 7
--       Black strikes with d6-d5 threatening fork d5-d4 against Nc3/Be3.
--     - Position 2 (Move 9 blunder):
--       2rq1rk1/pp2ppbp/2np1np1/2p5/4P3/2NPB1P1/PPP2P1P/R2Q1KNR b - - 1 9
--       Black strikes with d6-d5.
--     - Position 3 (Move 10 blunder):
--       2rq1rk1/pp3pbp/2np1np1/2p1p3/4P3/2NPBQP1/PPP2P1P/R4KNR b - - 1 10
--       Black strikes with d6-d5.
--     - Position 4 (Symmetrical White central fork strike):
--       r1bq1rk1/ppp2ppp/2n1pn2/3p4/4P3/2NP1N2/PPP1BPPP/R1BQK2R w KQ - 0 6
--       White strikes with d3-d4 threatening fork d4-d5 against Nc6/e6.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_Fork_Strike is

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
   Found       : Boolean;
   From_Sq     : Integer;
   To_Sq       : Integer;

   Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4); -- 44
   Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4); -- 36

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - Central Pawn Fork Strike Suite  ");
   Put_Line ("========================================================");

   -- 1. Position 1 (Move 7 blunder fix)
   Put_Line ("[1/4] Testing Position 1 (7... d6-d5 central fork strike)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk2r/pp2ppbp/2np1np1/2p5/4P3/2NPB1PB/PPP2P1P/R2QK1NR b KQkq - 3 7", Dummy_White);
   Search_Integration.Best_Central_Pawn_Fork_Strike (False, Found, From_Sq, To_Sq);
   Check ("Fork Strike: Position 1 finds d6-d5",
          Found and then From_Sq = Sq_D6 and then To_Sq = Sq_D5);
   Check ("Fork Strike: Position 1 See_Gain on d5 is non-negative",
          Search_Integration.See_Gain (False, From_Sq, To_Sq) >= 0);

   -- 2. Position 2 (Move 9 blunder fix)
   Put_Line ("[2/4] Testing Position 2 (9... d6-d5 central fork strike)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rq1rk1/pp2ppbp/2np1np1/2p5/4P3/2NPB1P1/PPP2P1P/R2Q1KNR b - - 1 9", Dummy_White);
   Search_Integration.Best_Central_Pawn_Fork_Strike (False, Found, From_Sq, To_Sq);
   Check ("Fork Strike: Position 2 finds d6-d5",
          Found and then From_Sq = Sq_D6 and then To_Sq = Sq_D5);
   Check ("Fork Strike: Position 2 See_Gain on d5 is non-negative",
          Search_Integration.See_Gain (False, From_Sq, To_Sq) >= 0);

   -- 3. Position 3 (Move 10 blunder fix)
   Put_Line ("[3/4] Testing Position 3 (10... d6-d5 central fork strike)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("2rq1rk1/pp3pbp/2np1np1/2p1p3/4P3/2NPBQP1/PPP2P1P/R4KNR b - - 1 10", Dummy_White);
   Search_Integration.Best_Central_Pawn_Fork_Strike (False, Found, From_Sq, To_Sq);
   Check ("Fork Strike: Position 3 finds d6-d5",
          Found and then From_Sq = Sq_D6 and then To_Sq = Sq_D5);
   Check ("Fork Strike: Position 3 See_Gain on d5 is non-negative",
          Search_Integration.See_Gain (False, From_Sq, To_Sq) >= 0);

   -- 4. Position 4 (Symmetrical White central fork strike d3-d4)
   Put_Line ("[4/4] Testing Symmetrical White d3-d4 central fork strike...");
   Search_Integration.Reset_Game;
   -- White has e4, c3, e3; Black has e5, c6, e6. White plays d3-d4
   Search_Integration.Parse_FEN
     ("r2q1rk1/ppp2ppp/2n1bn2/4p3/4P3/2NPBN2/PPP2PPP/R2Q1RK1 w - - 0 8", Dummy_White);
   declare
      Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4); -- 20
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4); -- 28
   begin
      Search_Integration.Best_Central_Pawn_Fork_Strike (True, Found, From_Sq, To_Sq);
      Check ("Fork Strike: Symmetrical White finds d3-d4",
             Found and then From_Sq = Sq_D3 and then To_Sq = Sq_D4);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_FORK_STRIKE: ALL PASS");
   else
      Put_Line ("TEST_V099171_FORK_STRIKE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_Fork_Strike;
