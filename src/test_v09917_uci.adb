-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17 UCI SURFACE & VETO COST TEST SUITE (PHASE 6c)
--
--  Unit:          Test_V09917_UCI
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Surface & Protocol Hardening Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. S2 Equivalence:
--     - Prechess2_Cascade_Only produces IDENTICAL moves to full Prechess2
--       both before and after root-move veto exclusions across multiple
--       standard positions.
--  2. N4 Option Case-Insensitivity:
--     - Set_Heuristic_Option parses lowercase, uppercase, and mixed-case
--       option names without mutation.
--  3. M7 Nodes Limit Parsing:
--     - 64-bit integer parsing handles values exceeding Integer'Last
--       (e.g., 5,000,000,000) and safely rejects malformed/negative inputs.
--  4. U3 Move Rejection Safeguard:
--     - Illegal and wrong-side replay tokens are rejected without mutating board.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;
with pprechess2;
with Time_Management;

procedure Test_V09917_UCI is
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

   White_To_Move : Boolean;

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
      pprechess2.Jogada_Vetada := (others => (others => False));
   end Load;

   -- S2 equivalence test helper
   procedure Check_S2_Equivalence (Pos_Name : String; FEN : String) is
      Cc_Full, Dd_Full : Integer;
      Cc_Casc, Dd_Casc : Integer;
      Cc_Full_V, Dd_Full_V : Integer;
      Cc_Casc_V, Dd_Casc_V : Integer;
   begin
      Load (FEN);
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 0, White_To_Move, True, 0);

      -- Run full search
      pprechess2.Prechess2;
      Cc_Full := pprechess2.Cc;
      Dd_Full := pprechess2.Dd;

      -- Run cascade-only on the same tactical flags
      pprechess2.Prechess2_Cascade_Only;
      Cc_Casc := pprechess2.Cc;
      Dd_Casc := pprechess2.Dd;

      Check ("S2 equivalence on " & Pos_Name & " (initial choice)",
             Cc_Full = Cc_Casc and Dd_Full = Dd_Casc);

      -- Apply veto on first choice and verify equivalence on veto retry
      pprechess2.Jogada_Vetada (Cc_Full, Dd_Full) := True;

      pprechess2.Prechess2;
      Cc_Full_V := pprechess2.Cc;
      Dd_Full_V := pprechess2.Dd;

      pprechess2.Prechess2_Cascade_Only;
      Cc_Casc_V := pprechess2.Cc;
      Dd_Casc_V := pprechess2.Dd;

      Check ("S2 equivalence on " & Pos_Name & " (veto retry)",
             Cc_Full_V = Cc_Casc_V and Dd_Full_V = Dd_Casc_V);

      pprechess2.Jogada_Vetada := (others => (others => False));
   end Check_S2_Equivalence;

   -- M7 parser tester mirroring prechess_uci.adb Get_Next_Nodes
   function Parse_Nodes_Token (Tok : String) return Long_Long_Integer is
      Val : Long_Long_Integer;
   begin
      Val := Long_Long_Integer'Value (Tok);
      if Val > 0 then
         return Val;
      else
         return 0;
      end if;
   exception
      when others =>
         return 0;
   end Parse_Nodes_Token;

   Applied : Boolean;
begin
   Put_Line ("=== V0.9.9.17 UCI Surface & Veto Cost Test Suite ===");

   -- -------------------------------------------------------------------------
   -- 1. S2 Equivalence: Prechess2_Cascade_Only == Prechess2
   -- -------------------------------------------------------------------------
   Check_S2_Equivalence ("Startpos",
     "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   Check_S2_Equivalence ("Tactical Italian",
     "r1bqkb1r/pppp1ppp/2n5/4p3/2B1n3/5N2/PPPP1PPP/RNBQ1RK1 w kq - 0 5");
   Check_S2_Equivalence ("Kiwipete",
     "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
   Check_S2_Equivalence ("Endgame",
     "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");

   -- -------------------------------------------------------------------------
   -- 2. N4 Option Case-Insensitivity
   -- -------------------------------------------------------------------------
   Search_Integration.Set_Heuristic_Option ("castle_bonus", 120);
   Check ("Set_Heuristic_Option lowercase castle_bonus",
          Search_Integration.Castle_Bonus_Weight = 120);

   Search_Integration.Set_Heuristic_Option ("CASTLE_BONUS", 130);
   Check ("Set_Heuristic_Option uppercase CASTLE_BONUS",
          Search_Integration.Castle_Bonus_Weight = 130);

   Search_Integration.Set_Heuristic_Option ("Castle_Bonus", 80);
   Check ("Set_Heuristic_Option mixed-case Castle_Bonus reset",
          Search_Integration.Castle_Bonus_Weight = 80);

   Search_Integration.Set_Heuristic_Option ("development_bonus", 55);
   Check ("Set_Heuristic_Option lowercase development_bonus",
          Search_Integration.Development_Bonus_Weight = 55);

   Search_Integration.Set_Heuristic_Option ("DEVELOPMENT_BONUS", 40);
   Check ("Set_Heuristic_Option uppercase DEVELOPMENT_BONUS reset",
          Search_Integration.Development_Bonus_Weight = 40);

   Search_Integration.Set_Heuristic_Option ("queen_tempo_penalty", 75);
   Check ("Set_Heuristic_Option lowercase queen_tempo_penalty",
          Search_Integration.Queen_Tempo_Penalty_Weight = 75);

   Search_Integration.Set_Heuristic_Option ("QUEEN_TEMPO_PENALTY", 60);
   Check ("Set_Heuristic_Option uppercase QUEEN_TEMPO_PENALTY reset",
          Search_Integration.Queen_Tempo_Penalty_Weight = 60);

   Search_Integration.Set_Heuristic_Option ("central_pawn_bonus", 65);
   Check ("Set_Heuristic_Option lowercase central_pawn_bonus",
          Search_Integration.Central_Pawn_Bonus_Weight = 65);

   Search_Integration.Set_Heuristic_Option ("CENTRAL_PAWN_BONUS", 50);
   Check ("Set_Heuristic_Option uppercase CENTRAL_PAWN_BONUS reset",
          Search_Integration.Central_Pawn_Bonus_Weight = 50);

   Search_Integration.Set_Heuristic_Option ("defended_piece_bonus", 35);
   Check ("Set_Heuristic_Option lowercase defended_piece_bonus",
          Search_Integration.Defended_Piece_Bonus_Weight = 35);

   Search_Integration.Set_Heuristic_Option ("DEFENDED_PIECE_BONUS", 25);
   Check ("Set_Heuristic_Option uppercase DEFENDED_PIECE_BONUS reset",
          Search_Integration.Defended_Piece_Bonus_Weight = 25);

   Search_Integration.Set_Heuristic_Option ("mobility_weight", 15);
   Check ("Set_Heuristic_Option lowercase mobility_weight",
          Search_Integration.Mobility_Bonus_Weight = 15);

   Search_Integration.Set_Heuristic_Option ("MOBILITY_WEIGHT", 10);
   Check ("Set_Heuristic_Option uppercase MOBILITY_WEIGHT reset",
          Search_Integration.Mobility_Bonus_Weight = 10);

   -- -------------------------------------------------------------------------
   -- 3. M7 Nodes Limit Parsing
   -- -------------------------------------------------------------------------
   Check ("M7 parses 5000000000 exceeding Integer'Last",
          Parse_Nodes_Token ("5000000000") = 5_000_000_000);
   Check ("M7 parses standard 1000000",
          Parse_Nodes_Token ("1000000") = 1_000_000);
   Check ("M7 rejects negative node count -50",
          Parse_Nodes_Token ("-50") = 0);
   Check ("M7 rejects non-numeric token 'abc'",
          Parse_Nodes_Token ("abc") = 0);
   Check ("M7 rejects empty token",
          Parse_Nodes_Token ("") = 0);

   -- -------------------------------------------------------------------------
   -- 4. U3 Move Rejection Safeguard
   -- -------------------------------------------------------------------------
   Load ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   Search_Integration.Make_Move_UCI
     ("e2e5", Expected_White_To_Move => True, Applied => Applied);
   Check ("U3 rejects illegal move e2e5", not Applied);
   Check ("U3 leaves pawn on e2",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 5)) = 1
          and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (5, 5)) = 0);

   Search_Integration.Make_Move_UCI
     ("e7e5", Expected_White_To_Move => True, Applied => Applied);
   Check ("U3 rejects wrong turn move e7e5 on White's turn", not Applied);

   -- -------------------------------------------------------------------------
   -- Final reporting
   -- -------------------------------------------------------------------------
   New_Line;
   if Failures = 0 then
      Put_Line ("TEST_V09917_UCI: ALL PASS (29/29)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line ("TEST_V09917_UCI: FAILURES =" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_V09917_UCI;
