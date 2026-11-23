-------------------------------------------------------------------------------
--  PRECHESS UCI - STEP 0B ROOT-STAGE GUARD & MOVE_COST AUDIT SUITE
--
--  Unit:          Test_V0991734_Step0b
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Validation;
with Pvalidade;
with Search_Integration;

procedure Test_V0991734_Step0b is
   Failures   : Natural := 0;
   White_Move : Boolean := True;

   function Sq (File_Ch, Rank_Ch : Character) return Integer is
      F : constant Integer := Character'Pos (File_Ch) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Ch) - Character'Pos ('1') + 1;
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;
begin
   Put_Line ("=== Step 0b: Root Guard, Exemptions, Double-Attack Capture & G-mirror ===");

   --  1. Central guard keeps threat-resolving Legacy over non-exempt stages.
   Check ("Guard keeps Legacy over Best_Defend_Central_Pawn",
          Search_Integration.Should_Keep_Legacy_Over_Correction
            (Stage            => "Best_Defend_Central_Pawn",
             Legacy_Valid     => True,
             Legacy_Hang_Cp   => 0,
             Root_Pre_Hang_Cp => 100,
             Legacy_Safe      => True,
             Legacy_Mate      => False,
             Legacy_Fork      => False,
             Legacy_Threat    => False,
             Legacy_Gain_Cp   => 0,
             Cand_Is_Capture  => False,
             Cand_Gain_Cp     => 0));

   Check ("Guard keeps Legacy over Best_Sicilian_Najdorf_Queen_Develop",
          Search_Integration.Should_Keep_Legacy_Over_Correction
            (Stage            => "Best_Sicilian_Najdorf_Queen_Develop",
             Legacy_Valid     => True,
             Legacy_Hang_Cp   => 0,
             Root_Pre_Hang_Cp => 0,
             Legacy_Safe      => True,
             Legacy_Mate      => False,
             Legacy_Fork      => False,
             Legacy_Threat    => False,
             Legacy_Gain_Cp   => 0,
             Cand_Is_Capture  => False,
             Cand_Gain_Cp     => 0));

   Check ("Guard keeps Legacy over non-winning Stage3_Resolve_Override",
          Search_Integration.Should_Keep_Legacy_Over_Correction
            (Stage            => "Stage3_Resolve_Override",
             Legacy_Valid     => True,
             Legacy_Hang_Cp   => 0,
             Root_Pre_Hang_Cp => 100,
             Legacy_Safe      => True,
             Legacy_Mate      => False,
             Legacy_Fork      => False,
             Legacy_Threat    => False,
             Legacy_Gain_Cp   => 0,
             Cand_Is_Capture  => True,
             Cand_Gain_Cp     => 0));

   --  2. Exempt stages & winning captures still override.
   Check ("Exempt: Best_Check_Evasion overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Check_Evasion", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Best_Opening_Trap_Response overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Opening_Trap_Response", True, 0, 100, True, False, False, False, 0, False, 0));
   Check ("Exempt: Stage1a_Best_Central_Pawn_Capture overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage1a_Best_Central_Pawn_Capture", True, 0, 0, True, False, False, False, 0, True, 0));
   Check ("Exempt: Stage2e_Central_Pawn_Capture overrides (P6 mirror)",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage2e_Central_Pawn_Capture", True, 0, 0, True, False, False, False, 0, True, 0));
   Check ("Exempt: Stage2f_KBP_Attacker_Trade overrides (P11 Bxb3)",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage2f_KBP_Attacker_Trade", True, 0, 0, True, False, False, False, 0, True, 0));
   Check ("Exempt: Best_Advanced_Central_Pawn_Recapture overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Advanced_Central_Pawn_Recapture", True, 100, 230, True, False, False, False, 100, True, 100));
   Check ("Exempt: Best_Pawn_Tempo_Kick_Knight overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Pawn_Tempo_Kick_Knight", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Best_Broad_Pawn_Center_Occupation overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Broad_Pawn_Center_Occupation", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Stage2e_Natural_Dev_Post_Flank_Bishop overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage2e_Natural_Dev_Post_Flank_Bishop", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Stage2e_Dev_Tempo_On_Queen overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage2e_Dev_Tempo_On_Queen", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Stage6_Safety_Quiet_Alt overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage6_Safety_Quiet_Alt", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Stage6_Safety_Natural_Dev overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage6_Safety_Natural_Dev", True, 0, 0, True, False, False, False, 0, False, 0));
   Check ("Exempt: Winning capture > Legacy gain overrides",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage3_Resolve_Override", True, 0, 100, True, False, False, False, 0, True, 100));
   Check ("Guard keeps Legacy on equal-gain capture tie (100 = 100)",
          Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Stage3_Resolve_Override", True, 0, 100, True, False, False, False, 100, True, 100));
   Check ("Guard yields when Legacy_Valid is False",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", False, 0, 100, True, False, False, False, 0, False, 0));

   --  3. Guard yields when Legacy leaves threat unresolved or unsafe.
   Check ("Guard yields when Legacy Hang_Cp > Root_Pre_Hang_Cp",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", True, 100, 0, True, False, False, False, 0, False, 0));
   Check ("Guard yields when Legacy creates Fork",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", True, 0, 100, True, False, True, False, 0, False, 0));
   Check ("Guard yields when Legacy creates Threat",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", True, 0, 100, True, False, False, True, 0, False, 0));
   Check ("Guard yields when Legacy creates Mate",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", True, 0, 100, True, True, False, False, 0, False, 0));
   Check ("Guard yields when Legacy is unsafe",
          not Search_Integration.Should_Keep_Legacy_Over_Correction
            ("Best_Defend_Central_Pawn", True, 0, 100, False, False, False, False, 0, False, 0));

   --  4. P5 equal trade e4xd5 and colour-mirror e5xd4 (G-mirror):
   --     Except_Sq => T prevents Qa5+/Qa4+ targeting T as a double attack.
   Search_Integration.Reset_Game;
   Check ("Parse P5 Caro W FEN",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq d6 0 3", White_Move));
   Check ("P5 White_Move output = True", White_Move);
   Check ("P5 White pre-move Max_Opponent_See = 100",
          Search_Integration.Max_Opponent_See (True) = 100);
   declare
      E4 : constant Integer := Sq ('e', '4');
      D5 : constant Integer := Sq ('d', '5');
      P  : constant Integer := Pvalidade.Tabuleiro (E4);
      V  : constant Integer := Pvalidade.Tabuleiro (D5);
   begin
      Pvalidade.Tabuleiro (D5) := P;
      Pvalidade.Tabuleiro (E4) := 0;
      Check ("P5 e4xd5 double-attack check excluding capture square d5 is False",
             not Search_Integration.Has_Opponent_Double_Attack
               (White_To_Move => True, Target_Sq => 0, Except_Sq => D5));
      Pvalidade.Tabuleiro (E4) := P;
      Pvalidade.Tabuleiro (D5) := V;
   end;

   Search_Integration.Reset_Game;
   Check ("Parse P5 Colour-Mirror FEN",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/ppp2ppp/8/3pp3/3P4/2P5/PP2PPPP/RNBQKBNR b KQkq d3 0 3", White_Move));
   Check ("P5 Mirror White_Move output = False (G-mirror)", not White_Move);
   Check ("P5 Mirror Black pre-move Max_Opponent_See = 100 (G-mirror)",
          Search_Integration.Max_Opponent_See (False) = 100);
   declare
      E5 : constant Integer := Sq ('e', '5');
      D4 : constant Integer := Sq ('d', '4');
      P  : constant Integer := Pvalidade.Tabuleiro (E5);
      V  : constant Integer := Pvalidade.Tabuleiro (D4);
   begin
      Pvalidade.Tabuleiro (D4) := P;
      Pvalidade.Tabuleiro (E5) := 0;
      Check ("P5 Mirror e5xd4 double-attack check excluding capture square d4 is False",
             not Search_Integration.Has_Opponent_Double_Attack
               (White_To_Move => False, Target_Sq => 0, Except_Sq => D4));
      Pvalidade.Tabuleiro (E5) := P;
      Pvalidade.Tabuleiro (D4) := V;
   end;

   --  5. True double attacks still flagged when Except_Sq = 0.
   Search_Integration.Reset_Game;
   Check ("Parse Rc2 double-attack FEN",
          Search_Integration.Try_Parse_FEN
            ("4rk2/5p2/p5p1/3Rp2p/KN6/2r2P2/P3B2P/8 w - - 7 32", White_Move));
   Pvalidade.Tabuleiro (Sq ('a', '6')) := Pvalidade.Tabuleiro (Sq ('b', '4'));
   Pvalidade.Tabuleiro (Sq ('b', '4')) := 0;
   Check ("32. Nxa6 still flags Rc2 double attack",
          Search_Integration.Has_Opponent_Double_Attack (White_To_Move => True));

   --  6. G-mirror SEE & Pre_Hang parity for P10, P11, P12.
   declare
      P10_B_See, P10_W_See : Integer;
      P10_B_Gain, P10_W_Gain : Integer;
      P12_B_See, P12_W_See : Integer;
   begin
      Search_Integration.Reset_Game;
      Check ("Parse P10 Black FEN",
             Search_Integration.Try_Parse_FEN
               ("rn1q1rk1/p3bppp/2ppbn2/1p2p3/P3P3/1BPP1N1P/1P3PP1/RNBQ1RK1 b - a3 0 9", White_Move));
      P10_B_See  := Search_Integration.Max_Opponent_See (False);
      P10_B_Gain := Search_Integration.See_Gain (False, Sq ('e', '6'), Sq ('b', '3'));

      Search_Integration.Reset_Game;
      Check ("Parse P10 Mirrored White FEN",
             Search_Integration.Try_Parse_FEN
               ("rnbq1rk1/1p3pp1/1bpp1n1p/p3p3/1P2P3/2PPBN2/P3BPPP/RN1Q1RK1 w - a6 0 9", White_Move));
      P10_W_See  := Search_Integration.Max_Opponent_See (True);
      P10_W_Gain := Search_Integration.See_Gain (True, Sq ('e', '3'), Sq ('b', '6'));
      Check ("P10 G-mirror Max_Opponent_See & Bxb3 See_Gain match",
             P10_B_See = P10_W_See and then P10_B_Gain = P10_W_Gain);

      Search_Integration.Reset_Game;
      Check ("Parse P12 Black FEN",
             Search_Integration.Try_Parse_FEN
               ("rnbq1rk1/p3bppp/2pp1n2/1p2p3/4P3/1BPP1N1P/PP3PP1/RNBQ1RK1 b - - 1 8", White_Move));
      P12_B_See := Search_Integration.Max_Opponent_See (False);

      Search_Integration.Reset_Game;
      Check ("Parse P12 Mirrored White FEN",
             Search_Integration.Try_Parse_FEN
               ("rnbq1rk1/pp3pp1/1bpp1n1p/4p3/1P2P3/2PP1N2/P3BPPP/RNBQ1RK1 w - - 1 8", White_Move));
      P12_W_See := Search_Integration.Max_Opponent_See (True);
      Check ("P12 G-mirror Max_Opponent_See matches",
             P12_B_See = P12_W_See);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V0991734_STEP0B: PASS");
   else
      Put_Line ("TEST_V0991734_STEP0B: FAIL (" & Integer'Image (Failures) & " failures)");
   end if;
end Test_V0991734_Step0b;
