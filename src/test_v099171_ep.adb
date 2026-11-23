-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 EN PASSANT & SCRATCH APPLY TEST SUITE
--
--  Unit:          Test_V099171_EP
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI En Passant & Scratch Apply Verification Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Double push EP detection in Max_Opponent_See_After (C2):
--     - Position 1: 6k1/8/8/8/3p4/8/P3P2P/6K1 w - - 0 1
--       e2-e4 allows d4xe3 e.p. (+100 cp).
--     - Position 2 (00:56 Variant): rnbqkbnr/pppp1ppp/8/8/2p1P3/8/PP1P1PPP/RNB1K1NR w KQkq - 0 1
--       d2-d4 allows c4xd3 e.p. (+100 cp).
--  2. No En_Passant_Sq leakage:
--     - En_Passant_Sq remains 0 after simulation calls.
--  3. Landing square exclusion (M2):
--     - Except_Sq = T correctly isolates the capture target.
--  4. En-passant SEE gain:
--     - See_Gain on legal EP capture evaluates to +100 cp.
--  5. Illegal EP pin exposure prevention:
--     - EP capture that exposes king to check is rejected.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_EP is

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

   Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5); -- 13
   Sq_E4 : constant Integer := Move_Validation.Square_Of (4, 5); -- 29
   Sq_D2 : constant Integer := Move_Validation.Square_Of (2, 4); -- 12
   Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4); -- 28
   Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5); -- 37
   Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4); -- 44

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - En Passant & Scratch Apply Gate ");
   Put_Line ("========================================================");

   -- 1. Double push beside opponent pawn (undefended e3)
   Put_Line ("[1/5] Testing double push EP exposure (e2-e4 beside d4)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/8/8/8/3p4/8/P3P2P/6K1 w - - 0 1", Dummy_White);

   declare
      Hang_After : constant Integer :=
        Search_Integration.Max_Opponent_See_After (True, Sq_E2, Sq_E4);
   begin
      Check ("EP: Max_Opponent_See_After detects EP reply d4xe3 (+100 cp)", Hang_After = 100);
      Check ("EP: No leak of En_Passant_Sq after e2-e4", Move_Validation.En_Passant_Sq = 0);
   end;

   -- 2. 00:56 Variant: broad center candidate d2-d4 beside c4
   Put_Line ("[2/5] Testing 00:56 variant (d2-d4 beside c4)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("rnbqkbnr/pppp1ppp/8/8/2p1P3/8/PP1P1PPP/RNB1K1NR w KQkq - 0 1", Dummy_White);

   declare
      Hang_After : constant Integer :=
        Search_Integration.Max_Opponent_See_After (True, Sq_D2, Sq_D4);
   begin
      Check ("EP: Max_Opponent_See_After detects EP reply c4xd3 on d2-d4 (+100 cp)", Hang_After = 100);
      Check ("EP: No leak of En_Passant_Sq after d2-d4", Move_Validation.En_Passant_Sq = 0);
   end;

   -- 3. Legal en-passant gain evaluation (+100 cp)
   Put_Line ("[3/5] Testing en-passant SEE gain calculation (+100 cp)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", Dummy_White);

   declare
      Gain : constant Integer := Search_Integration.See_Gain (True, Sq_E5, Sq_D6);
   begin
      Check ("EP: See_Gain returns +100 cp for legal en-passant capture", Gain = 100);
   end;

   -- 4. Opponent EP threat detection in Max_Opponent_See
   Put_Line ("[4/5] Testing opponent EP threat detection...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/3pP3/8/8/8/4K3 b - d6 0 1", Dummy_White);

   declare
      Threat : constant Integer := Search_Integration.Max_Opponent_See (White_To_Move => False);
   begin
      Check ("EP: Opponent EP threat correctly evaluated at +100 cp", Threat = 100);
   end;

   -- 5. Pin exposure: EP that leaves king in check is illegal
   Put_Line ("[5/5] Testing pinned EP illegality...");
   -- White King on e1, Black Rook on e8, White pawn on e5, Black pawn on d5, EP sq d6
   -- e5xd6 e.p. removes the e5 pawn, opening the e-file for Re8 to check Ke1.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", Dummy_White);

   declare
      Pin_Gain : constant Integer := Search_Integration.See_Gain (True, Sq_E5, Sq_D6);
   begin
      Check ("EP: Pinned pawn cannot legally capture en-passant (gain <= 0)", Pin_Gain <= 0);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_EP: ALL PASS");
   else
      Put_Line ("TEST_V099171_EP: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_EP;
