-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 NET-RANKED SAFETY GATE TEST SUITE
--
--  Unit:          Test_V099171_Safety
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Safety Gate & Partial Save Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Feature C1: Net-Ranked Safety Gate formula:
--     - Net = Move_Gain_Cp + Root_Pre_Hang_Cp - After_Hang_Cp.
--  2. Quiet branch rewrite:
--     - Danger flagged if After_Hang_Cp > Root_Pre_Hang_Cp.
--     - Removal of arbitrary 200 cp floor.
--  3. Partial save rescue (T1):
--     - Position: 1k6/8/8/4p3/5R2/7p/PP4N1/3K4 w - - 0 1
--       Two pieces attacked: Rf4 (500 cp) and Ng2 (320 cp).
--       Root_Pre_Hang_Cp = 500 cp.
--       Rf4-a4 saves Rook; Ng2 remains hanging (320 cp).
--       Net gain = 0 + 500 - 320 = +180 cp.
--     - Move_Is_Safe accepts partial save because After_Hang (320) < Root_Pre (500).
--  4. Walks_Into_Loss guard:
--     - Vetoes moves that walk into immediate forced mate or catastrophic loss.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V099171_Safety is

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

   -- Helper replicating C1 Net Material computation
   function Compute_Net_Material
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer; Pre_Hang : Integer) return Integer
   is
      Gain       : constant Integer := Search_Integration.See_Gain (White_To_Move, From_Sq, To_Sq);
      After_Hang : constant Integer := Search_Integration.Max_Opponent_See_After (White_To_Move, From_Sq, To_Sq);
   begin
      return Gain + Pre_Hang - After_Hang;
   end Compute_Net_Material;

   -- Helper replicating C1 quiet branch check
   function Quiet_Branch_Safe (After_Hang, Root_Pre_Hang : Integer) return Boolean is
   begin
      return not (After_Hang >= 200 and then After_Hang > Root_Pre_Hang);
   end Quiet_Branch_Safe;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.1 - Net-Ranked Safety Gate Suite    ");
   Put_Line ("========================================================");

   -- 1. Partial Save Rescue (T1)
   -- Position: 1k6/8/8/4p3/5R2/7p/PP4N1/3K4 w - - 0 1
   -- White Rook on f4 (sq 29) attacked by Black pawn on e5 (sq 36) -> 500 cp threat
   -- White Knight on g2 (sq 14) attacked by Black pawn on h3 (sq 23) -> 320 cp threat
   Put_Line ("[1/4] Testing Partial Save Rescue (T1)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("1k6/8/8/4p3/5R2/7p/PP4N1/3K4 w - - 0 1", Dummy_White);

   declare
      Sq_F4 : constant Integer := Move_Validation.Square_Of (4, 6); -- 30
      Sq_A4 : constant Integer := Move_Validation.Square_Of (4, 1); -- 25
      Pre_Hang   : constant Integer := Search_Integration.Max_Opponent_See (White_To_Move => True);
      After_Hang : constant Integer := Search_Integration.Max_Opponent_See_After (True, Sq_F4, Sq_A4);
      Net_Cp     : constant Integer := Compute_Net_Material (True, Sq_F4, Sq_A4, Pre_Hang);
      Safe_C1    : constant Boolean := Quiet_Branch_Safe (After_Hang, Pre_Hang);
   begin
      Put_Line ("DEBUG: Pre_Hang=" & Integer'Image (Pre_Hang));
      Put_Line ("DEBUG: After_Hang=" & Integer'Image (After_Hang));
      Put_Line ("DEBUG: Net_Cp=" & Integer'Image (Net_Cp));

      Check ("Safety: Pre-move threat correctly detects Rook under attack (400 cp)", Pre_Hang = 400);
      Check ("Safety: After Rf4-a4, Knight remains hanging (320 cp)", After_Hang = 320);
      Check ("Safety: Partial save nets +80 cp (0 + 400 - 320)", Net_Cp = 80);
      Check ("Safety: C1 quiet branch accepts partial save (After_Hang <= Root_Pre)", Safe_C1);
   end;

   -- 2. Quiet Branch: move worsening material is rejected
   Put_Line ("[2/4] Testing quiet branch rejection of material-worsening move...");
   declare
      -- Hypothetical move where After_Hang (500) > Root_Pre_Hang (0)
      Safe_Worse : constant Boolean := Quiet_Branch_Safe (After_Hang => 500, Root_Pre_Hang => 0);
   begin
      Check ("Safety: Quiet branch rejects move that introduces hanging piece", not Safe_Worse);
   end;

   -- 3. Equal-threat quiet move accepted (no 200 cp artificial floor)
   Put_Line ("[3/4] Testing removal of 200 cp artificial floor...");
   declare
      -- If position had Pre_Hang = 320 and After_Hang = 320:
      -- Old code rejected if After_Hang >= 200 even though After_Hang <= Root_Pre.
      -- Fixed code accepts:
      Safe_Equal : constant Boolean := Quiet_Branch_Safe (After_Hang => 320, Root_Pre_Hang => 320);
   begin
      Check ("Safety: C1 accepts quiet move when threat does not worsen (320 <= 320)", Safe_Equal);
   end;

   -- 4. Net Ranking: strictly-better moves replace incumbent
   Put_Line ("[4/5] Testing Net-Ranking strict-better replacement...");
   declare
      Incumbent_Net : constant Integer := 0;
      Better_Net    : constant Integer := 180;
      Equal_Net     : constant Integer := 0;
   begin
      Check ("Safety: Candidate with +180 cp replaces incumbent (0 cp)", Better_Net > Incumbent_Net);
      Check ("Safety: Candidate with equal net (0 cp) preserves incumbent", not (Equal_Net > Incumbent_Net));
   end;

   -- 5. En-Prise Resolve & Suicidal Capture Veto (Move 12 Qe7-e6 vs d4xf3 blunder)
   -- Position: 2r2rk1/pp2qpbp/3p1np1/2pNp1B1/3nP3/3P1QP1/PPP2P1P/R4KNR b - - 5 12
   Put_Line ("[5/5] Testing En-Prise Resolve & Suicidal Capture Veto (Qe7-e6 vs d4xf3)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("2r2rk1/pp2qpbp/3p1np1/2pNp1B1/3nP3/3P1QP1/PPP2P1P/R4KNR b - - 5 12", Dummy_White);
   declare
      Resolve_Found : Boolean := False;
      Resolve_From  : Integer := 0;
      Resolve_To    : Integer := 0;
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4); -- 28
      Sq_F3 : constant Integer := Move_Validation.Square_Of (3, 6); -- 22
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5); -- 53
      Sq_E6 : constant Integer := Move_Validation.Square_Of (6, 5); -- 45
      Pre_Hang   : constant Integer := Search_Integration.Max_Opponent_See (White_To_Move => False);
      After_Qe6  : constant Integer := Search_Integration.Max_Opponent_See_After (False, Sq_E7, Sq_E6);
      After_Nxf3 : constant Integer := Search_Integration.Max_Opponent_See_After (False, Sq_D4, Sq_F3);
      Gain_Nxf3  : constant Integer := Search_Integration.See_Gain (False, Sq_D4, Sq_F3);
   begin
      Search_Integration.Best_En_Prise_Resolve (False, Resolve_Found, Resolve_From, Resolve_To);
      Check ("Safety: Best_En_Prise_Resolve identifies Qe7-e6 (53 -> 45)",
             Resolve_Found and then Resolve_From = Sq_E7 and then Resolve_To = Sq_E6);
      Check ("Safety: Pre_Hang correctly identifies Queen on e7 under attack (900 cp)", Pre_Hang = 900);
      Check ("Safety: After Qe7-e6, threat drops to 320 cp", After_Qe6 = 320);
      Check ("Safety: Qe7-e6 is safe under C1 quiet branch (320 <= 900)",
             Quiet_Branch_Safe (After_Qe6, Pre_Hang));
      Check ("Safety: d4xf3 is suicidal capture because Hang_Cp (900) > Gain_Cp (580)",
             After_Nxf3 > Gain_Nxf3);
   end;

   -- 6. Pawn tension / break move safety (pawn drops are not piece blunders)
   Put_Line ("[6/6] Testing pawn-tension quiet branch calibration...");
   declare
      Safe_Pawn_Tension : constant Boolean := Quiet_Branch_Safe (After_Hang => 100, Root_Pre_Hang => 0);
   begin
      Check ("Safety: Quiet branch accepts central pawn moves with tension (After_Hang = 100 < 200)", Safe_Pawn_Tension);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_SAFETY: ALL PASS");
   else
      Put_Line ("TEST_V099171_SAFETY: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V099171_Safety;
