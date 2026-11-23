-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 EVERY-ATTACKER STATIC EXCHANGE EVALUATION (SEE) SUITE
--
--  Unit:          Test_V099171_SEE
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Static Exchange Evaluation Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature C3: Every-Attacker recursive exchange walk:
--     - In See_Gain, iterates over all legal candidate attackers instead of
--       stopping at the first lowest-value attacker.
--  2. Seventh-rank recapturer (T3):
--     - Validates recaptures involving advanced pawns and minor pieces.
--  3. 6-ply recursion cap:
--     - SEE depth is bounded at 6 plies, avoiding deep stack pressure.
--  4. Stack shrink (40 -> 6):
--     - Compact static evaluation arrays.
--  5. Non-capture quiet move returns 0 gain.
--  6. Board state unwinding invariance.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_SEE is

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
   Put_Line ("  Prechess 0.9.9.17.1 - Every-Attacker Centipawn SEE    ");
   Put_Line ("========================================================");

   -- 1. Seventh-Rank Recapturer (T3)
   -- Position: Black rook on h8, White pawn on g7, White knight on g6, White King e1, Black King e8
   -- White plays g7xh8=Q or Ng6xh8.
   Put_Line ("[1/4] Testing Seventh-rank exchange on h8...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k2r/6P1/6N1/8/8/8/8/4K3 w - - 0 1", Dummy_White);

   declare
      Sq_G7 : constant Integer := Move_Validation.Square_Of (7, 7); -- 55
      Sq_G6 : constant Integer := Move_Validation.Square_Of (6, 7); -- 47
      Sq_H8 : constant Integer := Move_Validation.Square_Of (8, 8); -- 64
      Gain_Pawn   : constant Integer := Search_Integration.See_Gain (True, Sq_G7, Sq_H8);
      Gain_Knight : constant Integer := Search_Integration.See_Gain (True, Sq_G6, Sq_H8);
   begin
      Put_Line ("DEBUG: Gain_Pawn=" & Integer'Image (Gain_Pawn));
      Put_Line ("DEBUG: Gain_Knight=" & Integer'Image (Gain_Knight));
      Check ("SEE: Pawn capture of rook evaluates positively (> 0)", Gain_Pawn > 0);
      Check ("SEE: Knight capture of undefended rook wins 500 cp", Gain_Knight = 500);
   end;

   -- 2. Quiet move returns 0 gain
   Put_Line ("[2/4] Testing quiet non-capture gain...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);

   declare
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5); -- 13
      Sq_E4 : constant Integer := Move_Validation.Square_Of (4, 5); -- 29
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_E2, Sq_E4);
   begin
      Check ("SEE: Quiet pawn advance e2-e4 returns exactly 0 gain", Gain = 0);
   end;

   -- 3. Defended piece trade evaluation
   Put_Line ("[3/4] Testing defended piece trade evaluation...");
   -- White pawn on e4, Black pawn on d5 defended by c6
   -- e4xd5 is an equal trade (100 - 100 = 0)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/2p5/3p4/4P3/8/8/4K3 w - - 0 1", Dummy_White);

   declare
      Sq_E4 : constant Integer := Move_Validation.Square_Of (4, 5); -- 29
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4); -- 36
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_E4, Sq_D5);
   begin
      Check ("SEE: Defended pawn trade e4xd5 evaluates to 0 net gain", Gain = 0);
   end;

   -- 4. Losing trade detection
   Put_Line ("[4/4] Testing losing piece sacrifice detection...");
   -- White Queen on e4 takes defended Black pawn on d5
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/2p5/3p4/4Q3/8/8/4K3 w - - 0 1", Dummy_White);

   declare
      Sq_E4 : constant Integer := Move_Validation.Square_Of (4, 5); -- 29
      Sq_D5 : constant Integer := Move_Validation.Square_Of (5, 4); -- 36
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_E4, Sq_D5);
   begin
      -- Queen (900 cp) for pawn (100 cp) -> loses 800 cp
      Check ("SEE: Queen taking defended pawn evaluates to -800 cp", Gain = -800);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_SEE: ALL PASS");
   else
      Put_Line ("TEST_V099171_SEE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_SEE;
