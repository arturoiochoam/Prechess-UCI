-------------------------------------------------------------------------------
--  PRECHESS UCI - 2F ROUNDS 2, 7 & 10 REGRESSION SUITE
--
--  Unit:          Test_V0991734_2f
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Move_Validation;
with Search_Integration;
with Tactical_Search;
with Time_Management;

procedure Test_V0991734_2f is
   Failures   : Natural := 0;
   White_Move : Boolean := True;

   Startpos_FEN : constant String :=
     "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

   R2_Moves : constant String :=
     "e2e4 c7c5 b1c3 b8c6 g2g3 g7g6 f1g2 f8g7 d2d3 d7d6 c1e3 g8f6 g2h3 c8h3 " &
     "g1h3 e7e5 h3g5 e8g8 h2h3 d8b6 b2b3 b6a5 e3d2 a5d8 g5f3 d6d5 e4d5 f6d5 " &
     "c3e4 d8b6 a2a4 c6d4 a4a5 b6c6 f3d4 c5d4 a1a4 f7f5 a4c4 c6e6 e4g5 e6d6 " &
     "g3g4 h7h6 g5f3 f5g4 h3g4 d6f6 c4c5 a8d8 h1h3 f6e7 c5c4 g6g5";

   R7_Moves : constant String :=
     "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 d1c2 d7d5 e2e3 e8g8 g1f3 b4a5 c1d2 h7h5 " &
     "a2a3 c7c6 f1d3 d5c4 d3c4 b7b5 c4d3 b5b4 a3b4 a5b4 c3e4 b4d2 f3d2 f6e4 " &
     "d3e4";

   R10_Moves : constant String :=
     "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 c1g5 f8e7 e4e5 f6d7 h2h4 e7g5 h4g5 d8g5 " &
     "g1f3 g5e7 f1b5 a7a6 b5a4 b7b5 a4b3 c7c5 a2a3 b8c6 d4c5 e7c5 d1e2 c6d4 " &
     "f3d4 c5d4 e1g1 d7e5 a1d1 d4f4 b3d5 a8b8 f1e1 f7f6 d5e4 e8g8 e2h5 f6f5 " &
     "g2g3 f4g4 h5g4 e5g4 e4f3 b5b4 c3a4 b4a3 b2a3 b8b5 c2c3 b5a5 d1d4 e6e5 " &
     "d4c4 c8e6 c4b4 f8c8 f3b7 c8c7 b7f3 g4f6 f3d1 c7c8 d1c2 e5e4 e1b1 h7h6 " &
     "c2b3 e6b3 b1b3 f6d5 b4d4 g7g6 g1f1 c8c7 b3b8 g8h7";

   R2_M15_Mirror_FEN : constant String :=
     "r2qk2r/p1pb1p2/1pnp1npp/8/2PNP3/2N3P1/PP3PBP/R2Q1RK1 b kq - 0 15";
   R2_M22_Mirror_FEN : constant String :=
     "3qk2r/2pb1p2/1p1p2pp/2rP4/p2NPPn1/3Q2P1/PP4BP/R4RK1 b k - 4 22";
   R2_M28_Mirror_FEN : constant String :=
     "3qk3/2pb1p2/1p1p1n1r/2rP2p1/p2NP1P1/7P/PP2Q1B1/3R1RK1 b - - 0 28";

   R7_M7_Mirror_FEN : constant String :=
     "r3kb1r/ppqb1ppp/2n1pn2/2pp4/B2P4/4PN2/PPP2PPP/RNBQ1RK1 w kq - 4 7";
   R7_M11_Mirror_FEN : constant String :=
     "r3k2r/1pqb1ppp/p1nbpn2/3p4/BP5P/2P1PN2/P4PP1/RNBQ1RK1 w kq - 1 11";
   R7_M15_Mirror_FEN : constant String :=
     "r3k2r/1pqn1ppp/4p3/3pb3/7P/2P1P3/P4PP1/RNBQ1RK1 w kq - 0 15";

   R10_M39_Mirror_FEN : constant String :=
     "6k1/5p2/prp3p1/n2rP3/R2N1P2/P5PP/8/2R3K1 b - - 0 39";

   Dev_White_FEN : constant String :=
     "r3kb1r/ppp2ppp/2n2n2/3pp3/3PP3/2N2N2/PPP2PPP/RNBQ1RK1 w kq - 0 7";
   Dev_Black_FEN : constant String :=
     "rnbq1rk1/ppp2ppp/2n2n2/3pp3/3PP3/2N2N2/PPP2PPP/R3KB1R b KQ - 0 7";

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

   procedure Play_N_Plies
     (Moves : String; Plies : Natural; Expected_Start_White : Boolean)
   is
      STM     : Boolean := Expected_Start_White;
      Pos     : Integer := Moves'First;
      Count   : Natural := 0;
      Applied : Boolean;
   begin
      while Pos <= Moves'Last and then Count < Plies loop
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
            if not Applied then
               Check ("Replay move " & Moves (Pos .. Stop - 1), False);
               exit;
            end if;
            STM   := not STM;
            Count := Count + 1;
            Pos   := Stop;
         end;
      end loop;
      Check ("Replayed" & Natural'Image (Count) & " plies cleanly",
             Count = Plies);
      White_Move := STM;
   end Play_N_Plies;

   function Run_Verify
     (FEN           : String;
      Chosen_UCI    : String;
      Depth         : Positive;
      Budget_Ms     : Natural;
      History_Moves : String := "";
      Plies         : Natural := 0) return Tactical_Search.Verify_Result
   is
      CF : constant Integer :=
        Sq (Chosen_UCI (Chosen_UCI'First), Chosen_UCI (Chosen_UCI'First + 1));
      CT : constant Integer :=
        Sq (Chosen_UCI (Chosen_UCI'First + 2), Chosen_UCI (Chosen_UCI'First + 3));
   begin
      Search_Integration.Reset_Game;
      Check ("Parse FEN: " & FEN,
             Search_Integration.Try_Parse_FEN (FEN, White_Move));
      if Plies > 0 then
         Play_N_Plies (History_Moves, Plies, White_Move);
      end if;
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, Depth, True, False);
      return Tactical_Search.Verify
        (White_To_Move => White_Move,
         Chosen_From   => CF,
         Chosen_To     => CT,
         Chosen_Promo  => 0,
         Budget_Ms     => Budget_Ms,
         Max_Depth     => Depth);
   end Run_Verify;

   R : Tactical_Search.Verify_Result;
   E_Dev_W, E_Dev_B, E_Before, E_After : Integer;
begin
   Put_Line ("=== 2F Suite: Rounds 2, 7 & 10 Verification ===");
   Tactical_Search.Set_Hash_MB (128);

   --  Round 2: White moves 15 (c3d5), 22 (e1g1), 28 (e1f1) + colour mirrors
   R := Run_Verify (Startpos_FEN, "c3d5", Depth => 8, Budget_Ms => 30000,
                    History_Moves => R2_Moves, Plies => 28);
   Check ("Round 2 m15 depth 8 picks c3d5 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c3d5");

   R := Run_Verify (R2_M15_Mirror_FEN, "c6d4", Depth => 8, Budget_Ms => 30000);
   Check ("Round 2 m15 colour mirror picks c6d4 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c6d4");

   R := Run_Verify (Startpos_FEN, "e1g1", Depth => 8, Budget_Ms => 30000,
                    History_Moves => R2_Moves, Plies => 42);
   Check ("Round 2 m22 depth 8 picks e1g1 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "e1g1");

   R := Run_Verify (R2_M22_Mirror_FEN, "e8g8", Depth => 8, Budget_Ms => 30000);
   Check ("Round 2 m22 colour mirror picks e8g8 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "e8g8");

   R := Run_Verify (Startpos_FEN, "b3b4", Depth => 8, Budget_Ms => 30000,
                    History_Moves => R2_Moves, Plies => 54);
   Check ("Round 2 m28 depth 8 picks e1f1 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "e1f1");

   R := Run_Verify (R2_M28_Mirror_FEN, "b6b5", Depth => 8, Budget_Ms => 30000);
   Check ("Round 2 m28 colour mirror picks e8f8 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "e8f8");

   --  Round 7: Black moves 7 (c8d7), 11 (c8b7), 15 (c8a6) + colour mirrors
   R := Run_Verify (Startpos_FEN, "h7h5", Depth => 8, Budget_Ms => 45000,
                    History_Moves => R7_Moves, Plies => 13);
   Check ("Round 7 m7 depth 8 picks c8d7 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c8d7");

   R := Run_Verify (R7_M7_Mirror_FEN, "h2h4", Depth => 8, Budget_Ms => 45000);
   Check ("Round 7 m7 colour mirror picks c1d2 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c1d2");

   R := Run_Verify (Startpos_FEN, "b5b4", Depth => 8, Budget_Ms => 45000,
                    History_Moves => R7_Moves, Plies => 21);
   Check ("Round 7 m11 depth 8 picks c8b7 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c8b7");

   R := Run_Verify (R7_M11_Mirror_FEN, "b4b5", Depth => 8, Budget_Ms => 45000);
   Check ("Round 7 m11 colour mirror picks c1b2 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c1b2");

   R := Run_Verify (Startpos_FEN, "d8h4", Depth => 8, Budget_Ms => 45000,
                    History_Moves => R7_Moves, Plies => 29);
   Check ("Round 7 m15 depth 8 picks c8a6 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c8a6");

   R := Run_Verify (R7_M15_Mirror_FEN, "d1h5", Depth => 8, Budget_Ms => 45000);
   Check ("Round 7 m15 colour mirror picks c1a3 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "c1a3");

   --  Round 10: White move 39 (b3b7) + colour mirror (b6b2)
   R := Run_Verify (Startpos_FEN, "g1f1", Depth => 8, Budget_Ms => 30000,
                    History_Moves => R10_Moves, Plies => 76);
   Check ("Round 10 m39 depth 8 picks b3b7 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "b3b7");

   R := Run_Verify (R10_M39_Mirror_FEN, "g8f8", Depth => 8, Budget_Ms => 30000);
   Check ("Round 10 m39 colour mirror picks b6b2 (actual=" & Move_Gen.Move_To_UCI (R.Best) & ")",
          R.Valid and then R.Depth >= 8
          and then Move_Gen.Move_To_UCI (R.Best) = "b6b2");

   --  G-mirror parity and Verify_Development state cleanup
   Search_Integration.Reset_Game;
   Check ("Parse Dev_White_FEN",
          Search_Integration.Try_Parse_FEN (Dev_White_FEN, White_Move));
   E_Dev_W := Tactical_Search.Evaluate_White;
   Search_Integration.Reset_Game;
   Check ("Parse Dev_Black_FEN",
          Search_Integration.Try_Parse_FEN (Dev_Black_FEN, White_Move));
   E_Dev_B := Tactical_Search.Evaluate_White;
   Check ("Development evaluation is G-mirror symmetric",
          E_Dev_W = -E_Dev_B);

   Search_Integration.Reset_Game;
   Check ("Parse Dev_Black_FEN for cleanup baseline",
          Search_Integration.Try_Parse_FEN (Dev_Black_FEN, White_Move));
   E_Before := Tactical_Search.Evaluate_White;
   R := Run_Verify (Startpos_FEN, "e2e4", Depth => 4, Budget_Ms => 5000);
   Check ("Non-development Verify completed cleanly", R.Valid);
   Check ("Re-parse Dev_Black_FEN after Verify",
          Search_Integration.Try_Parse_FEN (Dev_Black_FEN, White_Move));
   E_After := Tactical_Search.Evaluate_White;
   Check ("Standalone Evaluate_White unaffected by prior Verify_Development",
          E_Before = E_After);

   Search_Integration.Reset_Game;
   Check ("Parse Startpos for reverse cleanup baseline",
          Search_Integration.Try_Parse_FEN (Startpos_FEN, White_Move));
   E_Before := Tactical_Search.Evaluate_White;
   R := Run_Verify (Dev_White_FEN, "f1e1", Depth => 2, Budget_Ms => 3000);
   Check ("Development-active Verify completed cleanly", R.Valid);
   Check ("Re-parse Startpos after development-active Verify",
          Search_Integration.Try_Parse_FEN (Startpos_FEN, White_Move));
   E_After := Tactical_Search.Evaluate_White;
   Check ("Standalone Evaluate_White unaffected after Verify_Development=True",
          E_Before = E_After);

   if Failures > 0 then
      Put_Line ("TEST_V0991734_2F: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error with "test_v0991734_2f failed";
   end if;

   Put_Line ("TEST_V0991734_2F: PASS");
end Test_V0991734_2f;
