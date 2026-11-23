-------------------------------------------------------------------------------
--  PRECHESS UCI - STEP 2 EVALUATE_WHITE RULE-GENERALIZATION & G-MIRROR SUITE
--
--  Unit:          Test_V0991734_Step2
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Search_Integration;
with Tactical_Search;

procedure Test_V0991734_Step2 is
   Failures   : Natural := 0;
   White_Move : Boolean := True;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function Eval_FEN (FEN : String) return Integer is
      OK : Boolean;
   begin
      Search_Integration.Reset_Game;
      OK := Search_Integration.Try_Parse_FEN (FEN, White_Move);
      if not OK then
         Failures := Failures + 1;
         Put_Line ("FAIL: Could not parse FEN " & FEN);
         return 0;
      end if;
      return Tactical_Search.Evaluate_White;
   end Eval_FEN;
begin
   Put_Line ("=== Step 2: Remove Non-King Exact-Square Patches & Verify G-mirror ===");

   --  1. Removal of L294/L327 hardcoded c7/c2 (+110 cp) stop-square bonus:
   --     Symmetric c6+Nb5 (stop c7) vs f6+Ng5 (stop f7) with Ke8 must score identically.
   declare
      E_C7_Stop : constant Integer :=
        Eval_FEN ("4k3/8/2P5/1N6/8/8/8/4K3 w - - 0 1");
      E_F7_Stop : constant Integer :=
        Eval_FEN ("4k3/8/5P2/6N1/8/8/8/4K3 w - - 0 1");
      --  Black colour-mirrored pair (c3+Nb4 stop c2 vs f3+Ng4 stop f2 with Ke1):
      E_C2_Stop : constant Integer :=
        Eval_FEN ("4k3/8/8/8/1n6/2p5/8/4K3 b - - 0 1");
      E_F2_Stop : constant Integer :=
        Eval_FEN ("4k3/8/8/8/6n1/5p2/8/4K3 b - - 0 1");
   begin
      Put_Line ("  Stop-square evals: c7=" & Integer'Image (E_C7_Stop) &
                " f7=" & Integer'Image (E_F7_Stop) &
                " c2=" & Integer'Image (E_C2_Stop) &
                " f2=" & Integer'Image (E_F2_Stop));
      Check ("c7 knight-covered stop square matches symmetric f7 (no +110 c7 hack)",
             E_C7_Stop = E_F7_Stop);
      Check ("c2 knight-covered stop square matches symmetric f2 (no -110 c2 hack)",
             E_C2_Stop = E_F2_Stop);
      Check ("G-mirror parity between c6+Nb5 and c3+nb4",
             E_C7_Stop = -E_C2_Stop and then E_F7_Stop = -E_F2_Stop);
   end;

   --  2. Removal of L412-423 hardcoded Tabuleiro(13)=20 / Tabuleiro(53)=-20 (+80)
   --     and BK_Sq in 60..62 / WK_Sq in 4..6 (+160) exact-square bonus
   --     (Kf8/Kf1 with f7+g7 / f2+g2 shield intact, testing 60..62/4..6 cleanly):
   declare
      E_Qe2_Kf8 : constant Integer :=
        Eval_FEN ("5k2/5pp1/2P5/8/8/8/4Q3/4K3 w - - 0 1");
      E_Qc2_Kf8 : constant Integer :=
        Eval_FEN ("5k2/5pp1/2P5/8/8/8/2Q5/4K3 w - - 0 1");
      E_Qb2_Ka8 : constant Integer :=
        Eval_FEN ("k7/5pp1/2P5/8/8/8/1Q6/4K3 w - - 0 1");
      --  Black colour-mirrored equivalents:
      E_Qe7_Kf1 : constant Integer :=
        Eval_FEN ("4k3/4q3/8/8/8/2p5/5PP1/5K2 b - - 0 1");
      E_Qc7_Kf1 : constant Integer :=
        Eval_FEN ("4k3/2q5/8/8/8/2p5/5PP1/5K2 b - - 0 1");
      E_Qb7_Ka1 : constant Integer :=
        Eval_FEN ("4k3/1q6/8/8/8/2p5/5PP1/K7 b - - 0 1");
   begin
      Put_Line ("  Q+passer evals: Qe2/Kf8=" & Integer'Image (E_Qe2_Kf8) &
                " Qc2/Kf8=" & Integer'Image (E_Qc2_Kf8) &
                " Qb2/Ka8=" & Integer'Image (E_Qb2_Ka8));
      Check ("No exact-square Tabuleiro(13)=20 Qe2 bonus over Qc2",
             E_Qe2_Kf8 = E_Qc2_Kf8);
      Check ("No exact-square BK_Sq in 60..62 (+160) cliff vs Ka8",
             E_Qc2_Kf8 = E_Qb2_Ka8);
      Check ("No exact-square Tabuleiro(53)=-20 Qe7 bonus over Qc7",
             E_Qe7_Kf1 = E_Qc7_Kf1);
      Check ("No exact-square WK_Sq in 4..6 (-160) cliff vs Ka1",
             E_Qc7_Kf1 = E_Qb7_Ka1);
      Check ("G-mirror parity on Q+passer endgames",
             E_Qe2_Kf8 = -E_Qe7_Kf1
             and then E_Qc2_Kf8 = -E_Qc7_Kf1
             and then E_Qb2_Ka8 = -E_Qb7_Ka1);
   end;

   --  3. Preservation of untouched L425-498 king-safety block (BQ > 0 / WQ > 0 shield)
   --     and general rule-based knight stop-square bonus (+90 equal-material isolation):
   declare
      E_Shield_OK   : constant Integer :=
        Eval_FEN ("q5k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1");
      E_Shield_Open : constant Integer :=
        Eval_FEN ("q5k1/5ppp/8/8/8/8/5P1P/6K1 w - - 0 1");
      E_Shield_B_OK   : constant Integer :=
        Eval_FEN ("6k1/5ppp/8/8/8/8/5PPP/Q5K1 b - - 0 1");
      E_Shield_B_Open : constant Integer :=
        Eval_FEN ("6k1/5p1p/8/8/8/8/5PPP/Q5K1 b - - 0 1");
      --  Equal-material symmetric PST isolation: Nb5 controls c7; Ng5 does not.
      E_Stop_Nb5    : constant Integer :=
        Eval_FEN ("7k/8/2P5/1N6/8/8/8/4K3 w - - 0 1");
      E_Stop_Ng5    : constant Integer :=
        Eval_FEN ("7k/8/2P5/6N1/8/8/8/4K3 w - - 0 1");
      --  7th-rank promotion stop-square isolation (Nd6 controls c8; Ne6 does not).
      E_Rank7_Nd6   : constant Integer :=
        Eval_FEN ("6k1/2P5/3N4/8/8/8/8/4K3 w - - 0 1");
      E_Rank7_Ne6   : constant Integer :=
        Eval_FEN ("6k1/2P5/4N3/8/8/8/8/4K3 w - - 0 1");
   begin
      --  Missing g2 loses pawn (100) + shield penalty (-75) = 175 cp gap
      Check ("Untouched BQ > 0 king-shield penalty adds >= 175 cp loss on missing g2",
             E_Shield_OK - E_Shield_Open >= 175);
      Check ("G-mirror parity on WQ > 0 king-shield penalty",
             E_Shield_OK = -E_Shield_B_OK and then E_Shield_Open = -E_Shield_B_Open);
      Check ("Equal-material Nb5 stop control over c7 yields exact +90 cp",
             E_Stop_Nb5 - E_Stop_Ng5 = 90);
      Check ("7th-rank c7 passer with Nd6 controlling c8 yields exact +90 cp",
             E_Rank7_Nd6 - E_Rank7_Ne6 = 90);
   end;

   --  4. Perft invariance sanity check:
   Search_Integration.Reset_Game;
   Check ("Parse Startpos for Perft",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
   Check ("Perft_Fast(3) matches Move_Gen.Perft(3) = 8902",
          Tactical_Search.Perft_Fast (3, True) = 8_902
          and then Move_Gen.Perft (3, True) = 8_902);

   if Failures = 0 then
      Put_Line ("TEST_V0991734_STEP2: PASS");
   else
      Put_Line ("TEST_V0991734_STEP2: FAIL (" & Natural'Image (Failures) & ")");
   end if;
end Test_V0991734_Step2;
