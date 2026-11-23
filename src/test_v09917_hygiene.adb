-------------------------------------------------------------------------------
--  PRECHESS UCI - LEGACY DATA HYGIENE & LEGALITY SUITE (GATE G9)
--
--  Harness:       Test_V09917_Hygiene
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.17)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Protegida: pinned defender cannot legally recapture -> returns False (K3/B-M2).
--  2. Protegida: free (legal) defender -> returns True.
--  3. Protegida: king exclusion maintained (Tabuleiro(C) /= 999).
--  4. Person_Defends: pinned opponent defender cannot legally recapture -> returns False.
--  5. Person_Defends: free opponent defender -> returns True.
--  6. Move_Viable: king in check or capturable detected accurately.
--  7. Max_Opponent_See_After: castling moves do not return 999 sentinel (M5).
--  8. Max_Opponent_See_After: invalid moves return 0, not 999 sentinel (M5).
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Search_Integration;
with Move_Validation;
with Pvalidade;
with pprechess2;

procedure Test_V09917_Hygiene is

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

   --  Squares:
   --  e1 = 5, e2 = 13, d3 = 19, e8 = 61, a8 = 57, h8 = 64
   Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5); -- 5
   Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5); -- 13
   Sq_D3 : constant Integer := Move_Validation.Square_Of (3, 4); -- 20
   Sq_E8 : constant Integer := Move_Validation.Square_Of (8, 5); -- 61

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17 - Legacy Data Hygiene Gate (G9)     ");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Protegida: Pinned Defender (K3 / B-M2)
   ----------------------------------------------------------------------------
   Put_Line ("[1/5] Testing Protegida with pinned vs free defenders...");
   -- Board setup for engine (White):
   -- White King on e1 (+999), White Bishop on e2 (+3), Black Rook on e8 (-7).
   -- Opponent knight lands on d3 (-4).
   -- Bishop on e2 is absolutely pinned along the e-file by Re8 to Ke1.
   -- It cannot legally capture on d3.
   Pvalidade.Tabuleiro := (others => 0);
   Pvalidade.Tabuleiro (Sq_E1) := 999;  -- Ke1
   Pvalidade.Tabuleiro (Sq_E2) := 3;    -- Be2 (pinned!)
   Pvalidade.Tabuleiro (Sq_E8) := -7;   -- Re8 (pinning rook)
   Pvalidade.Tabuleiro (Sq_D3) := -4;   -- Nd3 (capturing knight)
   Pvalidade.Tabuleiro (64)    := -999; -- Kh8

   Check ("Move_Viable detects White King in check if pinned Bishop moves",
          not pprechess2.Defender_Is_Legal (Sq_E2, Sq_D3, White => True));

   Check ("Protegida rejects pinned Bishop defender (returns False)",
          not pprechess2.Protegida (Sq_D3, -pprechess2.Casc_Bishop));

   -- Now unpin: move the Black rook from e8 to a8. Bishop is now free!
   Pvalidade.Tabuleiro (Sq_E8) := 0;
   Pvalidade.Tabuleiro (57)    := -7;   -- Ra8 (no longer pinning e-file)

   Check ("Defender_Is_Legal confirms unpinned Bishop is legal",
          pprechess2.Defender_Is_Legal (Sq_E2, Sq_D3, White => True));

   Check ("Protegida accepts free Bishop defender (returns True)",
          pprechess2.Protegida (Sq_D3, -pprechess2.Casc_Bishop));

   ----------------------------------------------------------------------------
   -- 2. Protegida: King Exclusion Invariant
   ----------------------------------------------------------------------------
   Put_Line ("[2/5] Testing Protegida King defender exclusion...");
   -- Only the King attacks the target square.
   -- King on e2 (+999), opponent piece on d3 (-4). No other White pieces.
   Pvalidade.Tabuleiro := (others => 0);
   Pvalidade.Tabuleiro (Sq_E2) := 999;  -- Ke2
   Pvalidade.Tabuleiro (Sq_D3) := -4;   -- Nd3
   Pvalidade.Tabuleiro (64)    := -999; -- Kh8

   Check ("Protegida maintains King exclusion (returns False when only King defends)",
          not pprechess2.Protegida (Sq_D3, -pprechess2.Casc_Bishop));

   ----------------------------------------------------------------------------
   -- 3. Person_Defends: Pinned Opponent Defender
   ----------------------------------------------------------------------------
   Put_Line ("[3/5] Testing Person_Defends with pinned opponent defenders...");
   -- Black King on e8 (-999), Black Bishop on e7 (-3), White Rook on e1 (+7).
   -- White piece lands on d6 (+4).
   -- Black Bishop on e7 is absolutely pinned along the e-file by Re1 to Ke8.
   declare
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
      Sq_D6 : constant Integer := Move_Validation.Square_Of (6, 4);
   begin
      Pvalidade.Tabuleiro := (others => 0);
      Pvalidade.Tabuleiro (Sq_E8) := -999; -- Ke8
      Pvalidade.Tabuleiro (Sq_E7) := -3;   -- Be7 (pinned!)
      Pvalidade.Tabuleiro (Sq_E1) := 7;    -- Re1 (pinning rook)
      Pvalidade.Tabuleiro (Sq_D6) := 4;    -- Nd6 (white piece)
      Pvalidade.Tabuleiro (1)     := 999;  -- Ka1

      Check ("Person_Defends rejects pinned opponent defender (returns False)",
             not pprechess2.Person_Defends (Sq_D6));

      -- Unpin: move White rook from e1 to a1.
      Pvalidade.Tabuleiro (Sq_E1) := 0;
      Pvalidade.Tabuleiro (2)     := 7;    -- Rb1

      Check ("Person_Defends accepts free opponent defender (returns True)",
             pprechess2.Person_Defends (Sq_D6));
   end;

   ----------------------------------------------------------------------------
   -- 4. Move_Viable Invariants
   ----------------------------------------------------------------------------
   Put_Line ("[4/5] Testing Move_Viable invariants...");
   -- Normal peaceful position
   Pvalidade.Tabuleiro := (others => 0);
   Pvalidade.Tabuleiro (Sq_E1) := 999;
   Pvalidade.Tabuleiro (Sq_E8) := -999;
   Check ("Move_Viable returns True for White in quiet position",
          pprechess2.Move_Viable (White => True));
   Check ("Move_Viable returns True for Black in quiet position",
          pprechess2.Move_Viable (White => False));

   -- Place White King in check by Black Rook
   Pvalidade.Tabuleiro (Sq_E2) := -7; -- Re2 checking Ke1
   Check ("Move_Viable returns False for White when King in check",
          not pprechess2.Move_Viable (White => True));
   Check ("Move_Viable returns True for Black when Black King safe",
          pprechess2.Move_Viable (White => False));

   ----------------------------------------------------------------------------
   -- 5. Max_Opponent_See_After (M5 Sentinel 999 Elimination)
   ----------------------------------------------------------------------------
   Put_Line ("[5/5] Testing Max_Opponent_See_After sentinel 999 elimination (M5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
      Dummy_White);

   declare
      -- White Kingside castling: e1 (5) -> g1 (7)
      See_OO : constant Integer :=
        Search_Integration.Max_Opponent_See_After (White_To_Move => True, From_Sq => 5, To_Sq => 7);
      -- White Queenside castling: e1 (5) -> c1 (3)
      See_OOO : constant Integer :=
        Search_Integration.Max_Opponent_See_After (White_To_Move => True, From_Sq => 5, To_Sq => 3);
      -- Geometrically invalid move: e1 (5) -> a8 (57)
      See_Invalid : constant Integer :=
        Search_Integration.Max_Opponent_See_After (White_To_Move => True, From_Sq => 5, To_Sq => 57);
   begin
      Check ("White O-O does not return 999 sentinel (returns <= 0)", See_OO <= 0 and then See_OO /= 999);
      Check ("White O-O-O does not return 999 sentinel (returns <= 0)", See_OOO <= 0 and then See_OOO /= 999);
      Check ("Geometrically invalid move returns 0, NOT 999", See_Invalid = 0);
   end;

   -- Black castling tests
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
      Dummy_White);

   declare
      -- Black Kingside castling: e8 (61) -> g8 (63)
      See_B_OO : constant Integer :=
        Search_Integration.Max_Opponent_See_After (White_To_Move => False, From_Sq => 61, To_Sq => 63);
      -- Black Queenside castling: e8 (61) -> c8 (59)
      See_B_OOO : constant Integer :=
        Search_Integration.Max_Opponent_See_After (White_To_Move => False, From_Sq => 61, To_Sq => 59);
   begin
      Check ("Black O-O does not return 999 sentinel (returns <= 0)", See_B_OO <= 0 and then See_B_OO /= 999);
      Check ("Black O-O-O does not return 999 sentinel (returns <= 0)", See_B_OOO <= 0 and then See_B_OOO /= 999);
   end;

   ----------------------------------------------------------------------------
   -- SUMMARY
   ----------------------------------------------------------------------------
   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09917_HYGIENE: PASS");
   else
      Put_Line ("TEST_V09917_HYGIENE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V09917_Hygiene;
