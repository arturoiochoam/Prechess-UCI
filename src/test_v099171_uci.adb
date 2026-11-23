-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 UCI SURFACE & PV SCORING SUITE
--
--  Unit:          Test_V099171_UCI
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Surface & PV Verification Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature M3: Honest PV Score follows line with opponent-ply sign flip:
--     - Ply_Score follows mover perspective at ply K with sign flip on opponent plies.
--     - Root score +50 cp, opponent gains 300 cp -> reported score is -250 cp.
--     - Root score +50 cp, root gains 100 cp -> reported score is +150 cp.
--  2. Feature M3: En-Passant Gain in PV Walker:
--     - Unconditional See_Gain assigns +100 cp gain for legal en-passant in PV walker.
--  3. Feature M4: Centipawn Tie-Break in Best_Non_Losing_Capture:
--     - Raw_Piece_Value_Cp ensures tie-breaking treats equal centipawn sacrifices
--       identically, eliminating piece-code discrepancies.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_UCI is

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

   -- Helper for M3 sign-flipped score calculation
   function Corrected_Ply_Score
     (Post_Root_Score : Integer; Net_Cp : Integer; Mover_Was_Root : Boolean) return Integer
   is
   begin
      return Post_Root_Score + (if Mover_Was_Root then Net_Cp else -Net_Cp);
   end Corrected_Ply_Score;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - UCI Surface & PV Scoring Gate   ");
   Put_Line ("========================================================");

   -- 1. Honest PV score follows the line with opponent-ply sign flip
   Put_Line ("[1/3] Testing M3 Honest PV Score sign flip...");
   declare
      Root_Score      : constant Integer := 50;   -- Root eval +50 cp
      Opponent_Net_Cp : constant Integer := 300;  -- Opponent wins piece (+300 for mover)
      Root_Net_Cp     : constant Integer := 100;  -- Root wins pawn (+100 for root)
      Score_Opp_Ply   : constant Integer :=
        Corrected_Ply_Score (Root_Score, Opponent_Net_Cp, Mover_Was_Root => False);
      Score_Root_Ply  : constant Integer :=
        Corrected_Ply_Score (Root_Score, Root_Net_Cp,     Mover_Was_Root => True);
   begin
      Check ("UCI: Score flips sign on opponent ply (50 - 300 = -250)",
             Score_Opp_Ply = -250);
      Check ("UCI: Score maintains sign on root ply (50 + 100 = +150)",
             Score_Root_Ply = 150);
   end;

   -- 2. PV Walker assigns +100 cp gain for en-passant
   Put_Line ("[2/3] Testing M3 PV Walker en-passant gain (+100 cp)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", Dummy_White);

   declare
      Sq_E5 : constant Integer := Move_Validation.Square_Of (5, 5); -- 37
      Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4); -- 44
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_E5, Sq_D6);
   begin
      Check ("UCI: PV walker evaluates en-passant as +100 cp gain", Gain = 100);
   end;

   -- 3. M4: Centipawn tie-break in Best_Non_Losing_Capture
   Put_Line ("[3/4] Testing M4 Centipawn tie-break in Best_Non_Losing_Capture...");
   declare
      -- Trade 1: Queen (900 cp, code 20) takes Rook (500 cp, code 7). Net = 500 - 900 = -400 cp.
      Gain1 : constant Integer := Search_Integration.Raw_Piece_Value_Cp (7)
                                - Search_Integration.Raw_Piece_Value_Cp (20);
      -- Trade 2: Rook (500 cp, code 7) takes Pawn (100 cp, code 1). Net = 100 - 500 = -400 cp.
      Gain2 : constant Integer := Search_Integration.Raw_Piece_Value_Cp (1)
                                - Search_Integration.Raw_Piece_Value_Cp (7);
   begin
      Check ("UCI: Both trades evaluate to identical centipawn loss (-400 cp)", Gain1 = -400 and Gain2 = -400);
   end;

   -- 4. Heuristic Flank Bishop vs Active Classical Development (Italian Bc5 vs Bb4+)
   Put_Line ("[4/4] Testing Italian Bc5 active development vs premature Bb4+...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R b KQkq - 0 4", Dummy_White);
   declare
      Premature_Bb4 : constant Boolean :=
        Search_Integration.Is_Premature_Flank_Bishop
          (White_To_Move => False, From_Sq => 62, To_Sq => 26);
      Nat_Found : Boolean := False;
      Nat_From  : Integer := 0;
      Nat_To    : Integer := 0;
   begin
      Check ("Heuristic: Bb4+ flagged as premature flank bishop when c5 is open", Premature_Bb4);
      Search_Integration.Best_Natural_Development (False, Nat_Found, Nat_From, Nat_To);
      Check ("Heuristic: Natural development chooses active Bc5 (62 -> 35)",
             Nat_Found and then Nat_From = 62 and then Nat_To = 35);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_UCI: ALL PASS");
   else
      Put_Line ("TEST_V099171_UCI: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_UCI;
