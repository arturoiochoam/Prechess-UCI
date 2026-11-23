-------------------------------------------------------------------------------
--  PRECHESS UCI - GPT SEARCH & EVALUATION REGRESSION SUITE (G2/28, G1/16, G1/18)
--
--  Unit:          Test_V0991734_Gpt
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Move_Validation;
with Search_Integration;
with Tactical_Search;
with Time_Management;

procedure Test_V0991734_Gpt is
   Failures   : Natural := 0;
   White_Move : Boolean := True;

   Startpos_FEN : constant String :=
     "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
   G2_28_FEN : constant String :=
     "1r3k2/1p3p1P/p1np1b2/2p1p3/4P1P1/1PPP4/P4PK1/R6R w - - 0 28";
   G2_28_Mirror_FEN : constant String :=
     "r6r/p4pk1/1ppp4/4p1p1/2P1P3/P1NP1B2/1P3P1p/1R3K2 b - - 0 28";
   Free_Passer_FEN : constant String :=
     "7k/P7/8/8/8/8/8/4K3 w - - 0 1";
   G1_16_FEN : constant String :=
     "r3k2r/pp2p3/2qpbppp/8/3QP1n1/6P1/P1PB1PBP/R4RK1 b kq - 1 16";
   G1_16_Mirror_FEN : constant String :=
     "r4rk1/p1pb1pbp/6p1/3qp1N1/8/2QPBPPP/PP2P3/R3K2R w KQ - 1 16";
   G1_18_Mirror_FEN : constant String :=
     "r2r2k1/p1pb2bp/6p1/3qpp2/4N3/2QPBPPP/PP1KP3/R6R w - - 0 18";

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

   procedure Play_Moves (Moves : String; Expected_Start_White : Boolean) is
      STM     : Boolean := Expected_Start_White;
      Pos     : Integer := Moves'First;
      Applied : Boolean;
   begin
      while Pos <= Moves'Last loop
         while Pos <= Moves'Last and then Moves (Pos) = ' ' loop
            Pos := Pos + 1;
         end loop;
         exit when Pos > Moves'Last;
         declare
            Stop : Integer := Pos;
         begin
            while Stop <= Moves'Last and then Moves (Stop) /= ' ' loop
               Stop := Stop + 1;
            end loop;
            Search_Integration.Make_Move_UCI
              (Moves (Pos .. Stop - 1), STM, Applied);
            Check ("Replay move " & Moves (Pos .. Stop - 1), Applied);
            STM := not STM;
            Pos := Stop;
         end;
      end loop;
      White_Move := STM;
   end Play_Moves;

   function Run_Verify
     (FEN          : String;
      Chosen_UCI   : String;
      Depth        : Positive;
      Budget_Ms    : Natural;
      History_Moves : String := "") return Tactical_Search.Verify_Result
   is
      CF    : constant Integer := Sq (Chosen_UCI (Chosen_UCI'First), Chosen_UCI (Chosen_UCI'First + 1));
      CT    : constant Integer := Sq (Chosen_UCI (Chosen_UCI'First + 2), Chosen_UCI (Chosen_UCI'First + 3));
      CP    : constant Integer :=
        (if Chosen_UCI'Length >= 5 then
           (case Chosen_UCI (Chosen_UCI'First + 4) is
               when 'q' => 20, when 'r' => 7, when 'b' => 3, when 'n' => 4, when others => 0)
         else 0);
   begin
      Search_Integration.Reset_Game;
      Check ("Parse FEN: " & FEN,
             Search_Integration.Try_Parse_FEN (FEN, White_Move));
      if History_Moves'Length > 0 then
         Play_Moves (History_Moves, White_Move);
      end if;
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, Depth, True, False);
      return Tactical_Search.Verify
        (White_To_Move => White_Move,
         Chosen_From   => CF,
         Chosen_To     => CT,
         Chosen_Promo  => CP,
         Budget_Ms     => Budget_Ms,
         Max_Depth     => Depth);
   end Run_Verify;

   G1_16_Moves : constant String :=
     "e2e4 c7c5 b1c3 b8c6 g2g3 g7g6 f1g2 f8g7 d2d3 d7d6 c1e3 d8a5 g1e2 g8f6 " &
     "d3d4 c5d4 e2d4 f6g4 d4c6 g7c3 b2c3 a5c3 e3d2 c3c6 e1g1 c8e6 d2g5 h7h6 " &
     "d1d4 f7f6 g5d2";
   G1_18_Moves : constant String := G1_16_Moves & " e8d7 f1d1 g4e5 f2f4";

   R : Tactical_Search.Verify_Result;
   E_Atk_Free, E_Atk_Att, E_Before, E_After, E_G16_W, E_G16_B : Integer;
begin
   Put_Line ("=== GPT Suite: G2/28 Promotion, G1/16 King Exposure, G1/18 Attack Eval ===");
   Tactical_Search.Set_Hash_MB (128);

   --  Fix 1a: Evaluate_White penalizes attacked 7th/2nd rank empty stop squares symmetrically
   Search_Integration.Reset_Game;
   Check ("Parse attacked vs unattacked 7th-rank stop-square White (Ra8 attacks c8)",
          Search_Integration.Try_Parse_FEN ("r3k3/2P5/8/8/8/8/8/4K3 w - - 0 1", White_Move));
   E_Atk_Att := Tactical_Search.Evaluate_White;
   Search_Integration.Reset_Game;
   Check ("Parse unattacked 7th-rank stop-square control (Ra6 does not guard c8)",
          Search_Integration.Try_Parse_FEN ("4k3/2P5/r7/8/8/8/8/4K3 w - - 0 1", White_Move));
   E_Atk_Free := Tactical_Search.Evaluate_White;
   Check ("Attacked 7th-rank empty stop square incurs Pass(7)/2 swing vs free bonus",
          E_Atk_Free > E_Atk_Att + 120);

   --  Fix 1b: G2/28 promotion conversion at depth 8 and depth 10
   R := Run_Verify (G2_28_FEN, "g4g5", Depth => 8, Budget_Ms => 30000);
   Check ("G2/28 depth 8 picks h7h8q (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "h7h8q");

   R := Run_Verify (G2_28_FEN, "h1h6", Depth => 10, Budget_Ms => 30000);
   Check ("G2/28 depth 10 converts h7h8q directly or via g4g5 f6g7 h7h8q (actual="
          & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 10
          and then (Move_Gen.Move_To_UCI (R.Best) = "h7h8q"
                    or else (Move_Gen.Move_To_UCI (R.Best) = "g4g5"
                             and then R.PV_Len >= 5
                             and then Move_Gen.Move_To_UCI (R.PV (3)) = "h7h8q"
                             and then Move_Gen.Move_To_UCI (R.PV (5)) = "h1h8")));

   --  Fix 1c: G2/28 colour mirror & controls
   R := Run_Verify (G2_28_Mirror_FEN, "g5g4", Depth => 8, Budget_Ms => 30000);
   Check ("G2/28 colour mirror depth 8 picks h2h1q (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "h2h1q");

   R := Run_Verify (Free_Passer_FEN, "e1d1", Depth => 8, Budget_Ms => 15000);
   Check ("Free passer control depth 8 picks a7a8q (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "a7a8q");

   R := Run_Verify (Startpos_FEN, "e2e4", Depth => 8, Budget_Ms => 15000);
   Check ("Startpos control depth 8 keeps e2e4 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "e2e4");

   --  Fix 2: G1/16 exposed uncastled king -> g4e5 (+ mirror eval parity & g5e4 d7)
   R := Run_Verify (Startpos_FEN, "c6c2", Depth => 8, Budget_Ms => 30000,
                    History_Moves => G1_16_Moves);
   Check ("G1/16 depth 8 picks g4e5 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "g4e5");

   Search_Integration.Reset_Game;
   Check ("Parse G1_16_FEN",
          Search_Integration.Try_Parse_FEN (G1_16_FEN, White_Move));
   E_G16_B := Tactical_Search.Evaluate_White;
   Search_Integration.Reset_Game;
   Check ("Parse G1_16_Mirror_FEN",
          Search_Integration.Try_Parse_FEN (G1_16_Mirror_FEN, White_Move));
   E_G16_W := Tactical_Search.Evaluate_White;
   Check ("G1/16 evaluator G-mirror parity", E_G16_B = -E_G16_W);

   R := Run_Verify (G1_16_Mirror_FEN, "c3c7", Depth => 7, Budget_Ms => 30000);
   Check ("G1/16 colour mirror depth 7 picks g5e4 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 7
          and then Move_Gen.Move_To_UCI (R.Best) = "g5e4");

   --  Fix 3: G1/18 attack-mode mobility, king-ring pressure, bishop pair (+ mirror)
   R := Run_Verify (Startpos_FEN, "e6g4", Depth => 8, Budget_Ms => 30000,
                    History_Moves => G1_18_Moves);
   Check ("G1/18 depth 8 picks c6c4 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c6c4");

   R := Run_Verify (Startpos_FEN, "e6g4", Depth => 9, Budget_Ms => 30000,
                    History_Moves => G1_18_Moves);
   Check ("G1/18 depth 9 picks c6c4 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 9
          and then Move_Gen.Move_To_UCI (R.Best) = "c6c4");

   R := Run_Verify (G1_18_Mirror_FEN, "e3g5", Depth => 8, Budget_Ms => 30000);
   Check ("G1/18 colour mirror depth 8 picks c3c5 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c3c5");

   --  Cleanup safety check: Verify resets its attack-eval latch on exit
   Search_Integration.Reset_Game;
   Check ("Parse G1/18 mirror for standalone Evaluate_White baseline",
          Search_Integration.Try_Parse_FEN (G1_18_Mirror_FEN, White_Move));
   E_Before := Tactical_Search.Evaluate_White;
   R := Run_Verify (Free_Passer_FEN, "e1d1", Depth => 4, Budget_Ms => 2000);
   Check ("Non-attack Verify completed cleanly", R.Valid);
   Check ("Re-parse G1/18 mirror after non-attack Verify",
          Search_Integration.Try_Parse_FEN (G1_18_Mirror_FEN, White_Move));
   E_After := Tactical_Search.Evaluate_White;
   Check ("Standalone Evaluate_White unaffected by prior Verify call",
          E_Before = E_After);

   if Failures > 0 then
      Put_Line ("TEST_V0991734_GPT: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error with "test_v0991734_gpt failed";
   end if;

   Put_Line ("TEST_V0991734_GPT: PASS");
end Test_V0991734_Gpt;
