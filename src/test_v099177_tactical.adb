-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.7 TACTICAL VERIFICATION SEARCH TEST SUITE
--
--  Unit:     Test_V099177_Tactical
--  Language: Ada 2022
--
--  1. Fast generator perft == Move_Gen.Perft (start, Kiwipete, pos3, pos4).
--  2. Verify replaces cascade blunders taken from the analysed games.
--  3. Verify keeps sound cascade moves.
--  4. Proven mates are reported as mates; speculative lines are not.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Pvalidade;
with Tactical_Search;

procedure Test_V099177_Tactical is

   Failures : Natural := 0;
   White    : Boolean;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function Sq (Name : String) return Integer is
     (Move_Validation.Square_Of
        (Character'Pos (Name (Name'First + 1)) - Character'Pos ('0'),
         Character'Pos (Name (Name'First)) - Character'Pos ('a') + 1));

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White);
   end Load;

   procedure Perft_Case (Label, FEN : String; Depth : Natural; Expected : Long_Long_Integer) is
      Fast, Ref : Long_Long_Integer;
   begin
      Load (FEN);
      Fast := Tactical_Search.Perft_Fast (Depth, White);
      Ref  := Move_Gen.Perft (Depth, White);
      Check (Label & " fast perft" & Long_Long_Integer'Image (Fast)
             & " = expected" & Long_Long_Integer'Image (Expected),
             Fast = Expected and then Ref = Expected);
   end Perft_Case;

   function Run
     (FEN, From, To : String;
      Budget        : Natural := 30_000;
      Margin        : Natural := Tactical_Search.Veto_Margin_Cp)
      return Tactical_Search.Verify_Result
   is
   begin
      Load (FEN);
      --  Fixed depth 7 (budget is only a safety cap) so the result does not
      --  depend on build flags or machine speed.
      return Tactical_Search.Verify
        (White, Sq (From), Sq (To), 0, Budget,
         Max_Depth => 7, Margin_Cp => Margin);
   end Run;

   R : Tactical_Search.Verify_Result;
begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.7 - Tactical Verification Suite     ");
   Put_Line ("========================================================");

   --  1. Generator correctness
   Perft_Case ("startpos d4",
     "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 4, 197_281);
   Perft_Case ("kiwipete d3",
     "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97_862);
   Perft_Case ("pos3 d4", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43_238);
   Perft_Case ("pos4 d3",
     "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9_467);

   --  2. Blunders from the analysed games must be replaced
   R := Run ("1R6/2pk2p1/p6p/2B1p3/8/3P1K2/r5PP/8 w - - 2 33", "b8", "b7");
   Check ("G2 m33: Rb7?? (king fork Kc6) replaced", R.Valid and then R.Replaced);

   R := Run ("r3k2r/pp1bbppp/2nppn2/qN6/2B1PP2/2N1BQ2/PPP3PP/R3K2R w KQkq - 5 11", "b2", "b4");
   Check ("G7 m11: b4?? (Qxb4 pins Nc3) replaced", R.Valid and then R.Replaced);

   R := Run ("4qk2/5p2/8/r4p2/3P3p/1p6/p3N2P/Q3K3 w - - 0 37", "a1", "a2");
   Check ("G8 m37: Qxa2?? (bxa2) replaced", R.Valid and then R.Replaced);

   R := Run ("rnb1k2r/pppn1ppp/4p3/3pP3/3P4/3B1N2/PPP1NPq1/R2QK2R w KQkq - 0 11", "h1", "h2");
   Check ("G5 m11: Rh2?? (Qxf3) replaced", R.Valid and then R.Replaced);

   R := Run ("rnb1k3/pppn1ppr/4p3/3pP3/3P4/3B1q2/PPP1NP2/R2QK3 w Qq - 0 13", "d3", "b5");
   Check ("G5 m13: Bb5?? replaced", R.Valid and then R.Replaced);
   Check ("G5 m13: replacement is Bxh7 (SF best)",
          R.Best.From = Sq ("d3") and then R.Best.To = Sq ("h7"));

   --  3. Sound cascade moves are kept
   R := Run ("2kr2r1/1p3p1p/p1n3p1/P4n2/7P/5bP1/3B1PB1/R4RK1 w - - 0 22", "g2", "f3");
   Check ("G4 m22: Bxf3 (recapture) kept", R.Valid and then not R.Replaced);

   R := Run ("6k1/pp1rQppp/5n2/q3P3/1nr1P1b1/2N1B3/PPP3PP/1R3RK1 w - - 3 20", "e5", "f6");
   Check ("G3 m20: exf6 kept", R.Valid and then not R.Replaced);

   R := Run ("rnb1k2r/pppn1ppp/4p3/3pP3/3P2q1/2NB1N2/PPP2PP1/R2QK2R w KQkq - 4 10", "c3", "e2");
   Check ("G5 m10: no shallow h7 sacrifice override at default Margin (25)",
          R.Valid and then R.Best.To /= Sq ("h7"));
   R := Run ("rnb1k2r/pppn1ppp/4p3/3pP3/3P2q1/2NB1N2/PPP2PP1/R2QK2R w KQkq - 4 10",
             "c3", "e2", Margin => 100);
   Check ("G5 m10: Ne2 (queen-trap idea) kept under historical Margin => 100",
          R.Valid and then not R.Replaced);

   R := Run ("6k1/pp1rQppp/5n2/q3P3/1nr1P1b1/2N1B3/PPP3PP/1R3RK1 w - - 3 20", "e5", "f6");

   --  4. Mate scoring
   Check ("G3 m20: exf6 score is not a mate score (old +25.00 bug)",
          abs R.Best_Score < Tactical_Search.Mate_Threshold);

   R := Run ("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "g1", "f1");
   Check ("Back-rank: quiet Kf1 replaced by Ra8#",
          R.Valid and then R.Replaced and then R.Best.To = Sq ("a8"));
   Check ("Back-rank: Ra8# scored as mate in 1 (Mate_Value - 1)",
          R.Best_Score = Tactical_Search.Mate_Value - 1);

   R := Run ("r3qr2/5p1p/7k/5p2/2pP4/Q7/pP1KN2P/7R w - - 0 28", "a3", "e3");
   Check ("G8 m28: Qe3+?? replaced (perpetual Qh3+ available)",
          R.Valid and then R.Replaced);

   --  5. Black-side blunders and mate-in-N verification
   R := Run ("rnb1k2r/pppn1ppp/4p3/3NPq2/3P4/3Q4/PPP2PP1/R3KBNR b KQkq - 0 9", "c7", "c6");
   Check ("Black G1/G6 m9: c6?? (fork Nc7+) replaced by Qxd3 (SF best)",
          R.Valid and then R.Replaced
          and then R.Best.From = Sq ("f5") and then R.Best.To = Sq ("d3"));

   R := Run ("rnb1k2r/pp1n1ppR/2p1p3/3NPq2/3P4/3Q4/PPP2PP1/R3KBN1 b Qkq - 0 10", "c6", "c5");
   Check ("Black G6 m10: c5?? (Rxh8+ & Nc7+) replaced by capture on h7",
          R.Valid and then R.Replaced and then R.Best.To = Sq ("h7"));

   R := Run ("rnb1k2r/pp1n1ppR/2p1p3/3NPq2/3P4/3Q4/PPP2PP1/R3KBN1 b Qkq - 0 10", "f5", "h7");
   Check ("Black G6 m10: Qxh7 (SF best) kept",
          R.Valid and then not R.Replaced);

   R := Run ("r1bqr1k1/p4ppp/2p5/2Q5/2B4b/4P2P/PPP2RPK/R7 b - - 2 18", "d8", "b6");
   Check ("Black G9 m18: Qb6?? (Bxf7+ & Qh5+) replaced by Bxf2+ (SF best)",
          R.Valid and then R.Replaced
          and then R.Best.From = Sq ("h4") and then R.Best.To = Sq ("f2"));

   R := Run ("r1b1rk2/p5pp/1qp5/8/5P1Q/2N4P/PPP2RP1/R5K1 b - - 0 21", "h7", "h6");
   Check ("Black G9 m21: h6?? replaced by Qxb2 (SF best)",
          R.Valid and then R.Replaced
          and then R.Best.From = Sq ("b6") and then R.Best.To = Sq ("b2"));

   R := Run ("6k1/p2b4/6p1/8/1pP3pb/4r3/1r3P1P/6K1 b - - 1 38", "h4", "f2");
   Check ("Black G2 m38: Bxf2+ replaced by Re1+ (mate in 2 with 3-ply PV)",
          R.Valid and then R.Replaced
          and then R.Best.From = Sq ("e3") and then R.Best.To = Sq ("e1")
          and then R.Best_Score = Tactical_Search.Mate_Value - 3
          and then R.PV_Len = 3);

   R := Run ("3q1rk1/p3rpbp/5np1/4P3/8/2N3P1/P1P1NP1P/R3K2b b Q - 0 19", "e7", "e5");
   Check ("Black m19: Rxe5 kept with full non-truncated PV (PV_Len >= 7)",
          R.Valid and then not R.Replaced and then R.PV_Len >= 7);

   R := Run ("r1bqk2r/pp2ppbp/2n2np1/2pP4/8/2NPB1PB/PPP2P1P/R2QK1NR b KQkq - 0 8", "f6", "d5");
   Check ("Black Closed Sicilian m8: Nxd5 (SF best) kept",
          R.Valid and then not R.Replaced);

   --  10. Game 1 33... a6?? (-1.07) refuted in favor of winning central break 33... d4+
   R := Run ("4r1k1/p4r1p/2p2pn1/2pp4/5N2/4K3/1RP2PPP/4R3 b - - 3 33", "a7", "a6");
   Check ("G1 33... a6?? refuted", R.Valid and then R.Replaced);

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line ("FAILURES:" & Natural'Image (Failures));
      raise Program_Error with "test_v099177_tactical failed";
   end if;
end Test_V099177_Tactical;
