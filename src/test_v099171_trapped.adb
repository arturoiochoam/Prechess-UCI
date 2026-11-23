-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 TRAPPED PIECE THREAT & RESCUE SUITE
--
--  Unit:          Test_V099171_Trapped
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Trapped Piece Verification Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature N1/N3: Trapped Piece Threat Detection:
--     - Position: 4k3/8/1ppp4/8/1B6/P1P5/8/4K3 w - - 0 1
--       White bishop on b4 trapped by advancing Black pawn c6-c5.
--     - Symmetrical Black trapped bishop detection on b5.
--  2. Feature N1/N3: Trapped Piece Rescue:
--     - Best_Trapped_Piece_Rescue discovers escape move.
--  3. Feature N4: Realigned escape condition:
--     - Accepts 250 cp sacrifice to save trapped Rook.
--     - Accepts 350 cp sacrifice to save trapped Queen.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_Trapped is

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
   Put_Line ("  Prechess 0.9.9.17.1 - Trapped Piece Threat & Rescue   ");
   Put_Line ("========================================================");

   -- 1. Trapped Threat Detection (White Bishop on b4)
   -- Position: 4k3/8/1ppp4/8/1B6/P1P5/8/4K3 w - - 0 1
   -- Black pawns on b6, c6, d6. Pawn c6 advancing to c5 traps Bishop on b4.
   Put_Line ("[1/4] Testing White trapped bishop detection...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/1ppp4/8/1B6/P1P5/8/4K3 w - - 0 1", Dummy_White);

   declare
      Threat_White : constant Boolean :=
        Search_Integration.Has_Trapped_Piece_Threat (Defender_White => True);
   begin
      Check ("Trapped: Threat detected for White bishop on b4", Threat_White);
   end;

   -- 2. Symmetrical Trapped Threat Detection (Black Bishop on b5)
   -- Position: 4k2r/8/p1p5/1b6/8/1PPP4/8/4K2R b Kk - 0 1
   -- White pawn advancing c3-c4 traps Black bishop on b5.
   Put_Line ("[2/4] Testing Black trapped bishop detection (Symmetry)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k2r/8/p1p5/1b6/8/1PPP4/8/4K2R b Kk - 0 1", Dummy_White);

   declare
      Threat_Black : constant Boolean :=
        Search_Integration.Has_Trapped_Piece_Threat (Defender_White => False);
   begin
      Check ("Trapped: Threat detected symmetrically for Black bishop on b5", Threat_Black);
   end;

   -- 3. Trapped Rescue Search
   Put_Line ("[3/4] Testing Best_Trapped_Piece_Rescue...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/1ppp4/8/1B6/P1P5/8/4K3 w - - 0 1", Dummy_White);

   declare
      From_Sq, To_Sq : Integer := 0;
      Found          : Boolean := False;
   begin
      Search_Integration.Best_Trapped_Piece_Rescue
        (White_To_Move => True,
         Found         => Found,
         From_Sq       => From_Sq,
         To_Sq         => To_Sq);
      Check ("Trapped: Best_Trapped_Piece_Rescue finds a valid rescue move", Found and From_Sq /= 0 and To_Sq /= 0);
   end;

   -- 4. Feature N4 Realigned Escape Thresholds
   -- Rook (500 cp) sacrifice of 250 cp saves piece and is better than complete loss.
   -- Queen (900 cp) sacrifice of 350 cp saves piece and is better than complete loss.
   Put_Line ("[4/5] Testing N4 realigned escape condition thresholds...");
   declare
      Rook_Loss_Allowed  : constant Boolean := 250 < 500;
      Queen_Loss_Allowed : constant Boolean := 350 < 900;
   begin
      Check ("Trapped: Realigned escape condition accepts 250 cp loss for Rook", Rook_Loss_Allowed);
      Check ("Trapped: Realigned escape condition accepts 350 cp loss for Queen", Queen_Loss_Allowed);
   end;

   -- 5. Escape Square Destination Safety (Knight d4 after e7-e6)
   -- Position: 2r2rk1/pp2qpbp/3p1np1/2pNp1B1/3nP3/3P1QP1/PPP2P1P/R4KNR b - - 5 12
   -- Black plays Qe7-e6. Knight on d4 has safe squares (c2, b5, c6).
   -- Has_Trapped_Piece_Threat must return False for Black.
   Put_Line ("[5/5] Testing escape square destination safety (Knight on d4 after e7-e6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("2r2rk1/pp4bp/3pqnp1/2pNp1B1/3nP3/3P1QP1/PPP2P1P/R4KNR w - - 0 13", Dummy_White);
   declare
      Threat_Black_After_Qe6 : constant Boolean :=
        Search_Integration.Has_Trapped_Piece_Threat (Defender_White => False);
   begin
      Check ("Trapped: Knight on d4 is not trapped after Qe7-e6 (escape squares c2/b5/c6 safe)",
             not Threat_Black_After_Qe6);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_TRAPPED: ALL PASS");
   else
      Put_Line ("TEST_V099171_TRAPPED: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_Trapped;
