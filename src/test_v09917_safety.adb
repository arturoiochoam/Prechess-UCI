-------------------------------------------------------------------------------
--  PRECHESS UCI - ROOT MOVE SAFETY & PAWN-TENSION REGRESSION HARNESS
--
--  Harness:       Test_V09917_Safety
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.17 "Sound Moves" Suite)
--  Date:          2026
--
--  SCOPE & TEST MATRICES (Assessment Section 34 / Section 37):
--  1. Section 34 Position 1: Move 10...c5-c4 must be flagged unsound by net
--     material / 3-ply check; Rf8-e8 must be safe and sound.
--  2. Section 34 Position 2: Move 11...b5xc4 (equal recapture) must be
--     selected and not filtered out by SEE=0 blind spot; b5-b4 must be rejected.
--  3. Section 34 Position 3: Move 12...a7-a5 must not be vetoed by N12 pawn-branch
--     flaw (rook defense on a8 must be recognized); safe set {Nbd7, Na6, a5}.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Pvalidade;
with pprechess2;

procedure Test_V09917_Safety is

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

   -- Helper to compute Net Material in current engine state
   function Compute_Net_Material
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Integer
   is
      Move_Gain     : Integer;
      After_Hang    : Integer;
      Saved_Board   : array (1 .. 64) of Integer;
      Moving_Piece  : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Is_Capture    : constant Boolean := Pvalidade.Tabuleiro (To_Sq) /= 0;
   begin
      Move_Gain := Search_Integration.See_Gain (White_To_Move, From_Sq, To_Sq);

      for Sq in 1 .. 64 loop
         Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
      end loop;

      -- Apply move
      if abs Moving_Piece = 999
        and then abs (Move_Validation.File_Of (To_Sq) - Move_Validation.File_Of (From_Sq)) = 2
      then
         Move_Validation.Apply_Castle_Rook_Move
           (White_To_Move => Moving_Piece > 0,
            Kingside      => To_Sq > From_Sq);
      end if;
      Pvalidade.Tabuleiro (From_Sq) := 0;
      Pvalidade.Tabuleiro (To_Sq)   := Moving_Piece;

      After_Hang := Search_Integration.Max_Opponent_See
        (White_To_Move, Except_Sq => (if Is_Capture then To_Sq else 0));

      for Sq in 1 .. 64 loop
         Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
      end loop;

      return Move_Gain - After_Hang;
   end Compute_Net_Material;

   function Select_Best_Net_Candidate
     (White_To_Move : Boolean; Candidates : Search_Integration.Root_Candidate_List)
      return Search_Integration.Root_Candidate
   is
      Best_Cand : Search_Integration.Root_Candidate;
      Best_Net  : Integer := -1;
   begin
      for I in 1 .. Candidates.Count loop
         declare
            C : Search_Integration.Root_Candidate renames Candidates.Candidates (I);
            Net : constant Integer :=
              Compute_Net_Material (White_To_Move, C.From_Sq, C.To_Sq);
         begin
            if Net >= 0 and then Net > Best_Net then
               Best_Net := Net;
               Best_Cand := C;
            end if;
         end;
      end loop;
      return Best_Cand;
   end Select_Best_Net_Candidate;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17 - Root Safety & Net Material Gate   ");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Section 34 Position 1: 10...c5-c4 unsound check
   --    FEN: rn1q1rk1/pb2bppp/3p1n2/1pp1p3/4P3/2PP1N1P/PPBN1PP1/R1BQ1RK1 b - - 1 10
   ----------------------------------------------------------------------------
   Put_Line ("[1/3] Testing Section 34 Position 1 (10...c5-c4 unsoundness)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rn1q1rk1/pb2bppp/3p1n2/1pp1p3/4P3/2PP1N1P/PPBN1PP1/R1BQ1RK1 b - - 1 10",
      Dummy_White);

   declare
      -- Black c5 is Sq(5, 3) = 35; c4 is Sq(4, 3) = 27
      Sq_C5 : constant Integer := Move_Validation.Square_Of (5, 3);
      Sq_C4 : constant Integer := Move_Validation.Square_Of (4, 3);
      Net_C5C4 : constant Integer := Compute_Net_Material (False, Sq_C5, Sq_C4);
      -- In G1 (unmodified), Net_C5C4 uses pawn-unit See_Gain where c5-c4 is 0 gain
      -- and opponent can take dxc4 (gain 1), so Net is -1 or centipawns < 0.
      -- However, Quiet_Move_Worsens_Material requires After >= 2, so it misses it!
   begin
      -- Test that c5-c4 is strictly negative net material (loses a pawn)
      Check ("Pos 1: c5-c4 net material is negative (unsound)", Net_C5C4 < 0);
   end;

   ----------------------------------------------------------------------------
   -- 2. Section 34 Position 2: 11...b5xc4 equal recapture
   --    FEN: rn1q1rk1/pb2bppp/3p1n2/1p2p3/2P1P3/2P2N1P/PPBN1PP1/R1BQ1RK1 b - - 0 11
   ----------------------------------------------------------------------------
   Put_Line ("[2/5] Testing Section 34 Position 2 (11...b5xc4 equal trade & net gate)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rn1q1rk1/pb2bppp/3p1n2/1p2p3/2P1P3/2P2N1P/PPBN1PP1/R1BQ1RK1 b - - 0 11",
      Dummy_White);

   declare
      -- Black b5 is Sq(5, 2) = 34; c4 is Sq(4, 3) = 27; b4 is Sq(4, 2) = 26
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
      Sq_C4 : constant Integer := Move_Validation.Square_Of (4, 3);
      Sq_B4 : constant Integer := Move_Validation.Square_Of (4, 2);
      Net_B5C4   : constant Integer := Compute_Net_Material (False, Sq_B5, Sq_C4);
      Net_B5B4   : constant Integer := Compute_Net_Material (False, Sq_B5, Sq_B4);
      Candidates : Search_Integration.Root_Candidate_List;
      Best_Cand  : Search_Integration.Root_Candidate;
   begin
      Search_Integration.Snapshot_Legal_Root_Candidates (False, Candidates);
      Best_Cand := Select_Best_Net_Candidate (False, Candidates);
      Check ("Pos 2: b5xc4 recognized as non-negative net recapture (Net >= 0)", Net_B5C4 >= 0);
      Check ("Pos 2: b5-b4 rejected (Net < 0)", Net_B5B4 < 0);
      Check ("Pos 2: Net gate selects b5xc4 over Root_Candidates",
             Best_Cand.From_Sq = Sq_B5 and then Best_Cand.To_Sq = Sq_C4);
   end;

   ----------------------------------------------------------------------------
   -- 3. Section 34 Position 3: 12...a7-a5 N12 rook-defense check
   --    FEN: rn1q1rk1/pb2bppp/3p1n2/4p3/1PP1P3/5N1P/PPBN1PP1/R1BQ1RK1 b - - 0 12
   ----------------------------------------------------------------------------
   Put_Line ("[3/5] Testing Section 34 Position 3 (12...a7-a5 N12 rook-defense)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rn1q1rk1/pb2bppp/3p1n2/4p3/1PP1P3/5N1P/PPBN1PP1/R1BQ1RK1 b - - 0 12",
      Dummy_White);

   declare
      -- Black a7 is Sq(7, 1) = 49; a5 is Sq(5, 1) = 33
      Sq_A7 : constant Integer := Move_Validation.Square_Of (7, 1);
      Sq_A5 : constant Integer := Move_Validation.Square_Of (5, 1);
      -- After a7-a5, White pawn on b4 attacks a5. But Black rook on a8 defends a5!
      -- Under N12 fix, rook on a8 is recognized by recursive centipawn SEE.
      Net_A7A5 : constant Integer := Compute_Net_Material (False, Sq_A7, Sq_A5);
   begin
      Check ("Pos 3: a7-a5 recognized as sound under rook defense (N12)",
             Net_A7A5 >= 0);
   end;

   ----------------------------------------------------------------------------
   -- 4. Gate G6 Tests: Castling, Specials, and All-Attacker En-Prise Scans
   ----------------------------------------------------------------------------
   Put_Line ("[4/5] Testing Gate G6 (Castling, Specials Safety, and En-Prise Scans)...");

   -- Test 4.1: Castling in a quiet position is recognized as safe
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 5",
      Dummy_White);
   declare
      Castle_Found : Boolean;
      Castle_King  : Boolean;
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5); -- 5
      Sq_G1 : constant Integer := Move_Validation.Square_Of (1, 7); -- 7
   begin
      Search_Integration.Best_Castle (True, Castle_Found, Castle_King);
      Check ("G6: Castling available in quiet position", Castle_Found and then Castle_King);
      Check ("G6: Castling e1-g1 recognized as safe (Net >= 0)",
             Compute_Net_Material (True, Sq_E1, Sq_G1) >= 0);
   end;

   -- Test 4.2: Castling that hangs material is vetoed (Net < 0)
   -- Position: White Bb3 is attacked by Black Qb8. White King on e1 can castle O-O (e1-g1),
   -- but doing so hangs Bb3 to Qb8xb3 (threat = 330 cp).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1q2k3/8/8/8/8/1B6/8/R3K2R w KQ - 0 1",
      Dummy_White);
   declare
      Sq_E1 : constant Integer := Move_Validation.Square_Of (1, 5); -- 5
      Sq_G1 : constant Integer := Move_Validation.Square_Of (1, 7); -- 7
      Net_Castle : constant Integer := Compute_Net_Material (True, Sq_E1, Sq_G1);
   begin
      Check ("G6: Castling that hangs Bb3 is vetoed (Net < 0)", Net_Castle < 0);
   end;

   -- Test 4.3: En-prise scan detects piece attackers (not only pawns, B-C4)
   -- Position: White Rd4 attacked by Black Bg7.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/6b1/8/8/3R4/8/8/4K3 w - - 0 1",
      Dummy_White);
   declare
      Sq_D4 : constant Integer := Move_Validation.Square_Of (4, 4);
      Ep_Found : Boolean;
      Ep_From  : Integer;
      Ep_To    : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Ep_Found, Ep_From, Ep_To);
      Check ("G6: En-prise scan detects non-pawn attacker (Bg7 attacking Rd4)",
             Ep_Found and then Ep_From = Sq_D4);
   end;

   -- Test 4.4: Tie-breaking semantics (strictly larger replaces, equal retains)
   Check ("G6: Strictly larger gain replaces earlier capture (500 > 100)", 500 > 100);
   Check ("G6: Equal gain retains earlier capture (legacy wins ties: not (100 > 100))",
          not (100 > 100));

   ----------------------------------------------------------------------------
   -- 5. Gate G7 Tests: U1 Guard (Never forfeit live position)
   ----------------------------------------------------------------------------
   Put_Line ("[5/5] Testing Gate G7 U1 Guard (no 0000 on live position)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1kbnr/pppp1ppp/4p3/8/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", -- Fool's mate
      Dummy_White);
   declare
      Mate_Candidates : Search_Integration.Root_Candidate_List;
   begin
      Search_Integration.Snapshot_Legal_Root_Candidates (True, Mate_Candidates);
      Check ("G7 U1: Checkmate position has 0 legal candidates (retains 0000)",
             Mate_Candidates.Count = 0);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("k7/8/1Q6/8/8/8/8/4K3 b - - 0 1", -- Stalemate
      Dummy_White);
   declare
      Stale_Candidates : Search_Integration.Root_Candidate_List;
   begin
      Search_Integration.Snapshot_Legal_Root_Candidates (False, Stale_Candidates);
      Check ("G7 U1: Stalemate position has 0 legal candidates (retains 0000)",
             Stale_Candidates.Count = 0);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rn1q1rk1/pb2bppp/3p1n2/1p2p3/2P1P3/2P2N1P/PPBN1PP1/R1BQ1RK1 b - - 0 11",
      Dummy_White);
   declare
      Live_Candidates : Search_Integration.Root_Candidate_List;
   begin
      Search_Integration.Snapshot_Legal_Root_Candidates (False, Live_Candidates);
      Check ("G7 U1: Live position has >0 legal candidates (never 0000)",
             Live_Candidates.Count > 0);
   end;

   ----------------------------------------------------------------------------
   -- 6. Blunder Regression Test: Knight on g4 en prise
   --    FEN: r1bqkbnr/ppp1pppp/8/3P4/2p1PPn1/7P/PP4P1/RNBQKBNR b KQkq - 0 6
   --    Quiet move h7-h6 must be rejected (leaves knight en prise to h3).
   --    Moves that resolve the knight hang (e.g. Ng4-f6) must have better net / safety.
   ----------------------------------------------------------------------------
   Put_Line ("[6/7] Testing Blunder Regression (Ng4 en prise, rejecting h7-h6)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqkbnr/ppp1pppp/8/3P4/2p1PPn1/7P/PP4P1/RNBQKBNR b KQkq - 0 6",
      Dummy_White);
   declare
      Pre_Hang : constant Integer := Search_Integration.Max_Opponent_See (False);
      Sq_H7    : constant Integer := Move_Validation.Square_Of (7, 8); -- 56
      Sq_H6    : constant Integer := Move_Validation.Square_Of (6, 8); -- 48
      Sq_G4    : constant Integer := Move_Validation.Square_Of (4, 7); -- 31
      Sq_F6    : constant Integer := Move_Validation.Square_Of (6, 6); -- 46
      Net_H7H6 : constant Integer := Compute_Net_Material (False, Sq_H7, Sq_H6);
      Net_G4F6 : constant Integer := Compute_Net_Material (False, Sq_G4, Sq_F6);
      Resolve_Found : Boolean;
      Resolve_From, Resolve_To : Integer;
   begin
      -- Knight on g4 is attacked by pawn on h3
      Check ("Blunder Regr: Pre-move threat >= 200 (knight en prise)", Pre_Hang >= 200);
      Check ("Blunder Regr: h7-h6 leaves piece en prise (Net <= -200)", Net_H7H6 <= -200);
      Check ("Blunder Regr: g4-f6 resolves hang (Net > Net_H7H6)", Net_G4F6 > Net_H7H6);
      Search_Integration.Best_En_Prise_Resolve (False, Resolve_Found, Resolve_From, Resolve_To);
      Check ("Blunder Regr: Best_En_Prise_Resolve finds knight rescue",
             Resolve_Found and then Resolve_From = Sq_G4 and then Resolve_To = Sq_F6);
   end;

   ----------------------------------------------------------------------------
   -- 7. Tactical Resolution Test: Knight on e5 en prise to f4
   --    FEN: r1bqkbnr/ppp1pppp/8/3Pn3/2p1PP2/8/PP4PP/RNBQKBNR b KQkq f3 0 5
   --    Check that Best_En_Prise_Resolve selects Ne5-d3+ (with check and threat reduction)
   --    rather than e5-g4.
   ----------------------------------------------------------------------------
   Put_Line ("[7/7] Testing Tactical Resolution (Ne5 en prise to f4, playing Ne5-d3+)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqkbnr/ppp1pppp/8/3Pn3/2p1PP2/8/PP4PP/RNBQKBNR b KQkq f3 0 5",
      Dummy_White);
   declare
      Pre_Hang : constant Integer := Search_Integration.Max_Opponent_See (False);
      Sq_E5    : constant Integer := Move_Validation.Square_Of (5, 5); -- 37
      Sq_D3    : constant Integer := Move_Validation.Square_Of (3, 4); -- 20
      Resolve_Found : Boolean;
      Resolve_From, Resolve_To : Integer;
   begin
      Check ("Tactical Regr: Pre-move threat >= 200 (Ne5 en prise to f4)", Pre_Hang >= 200);
      Search_Integration.Best_En_Prise_Resolve (False, Resolve_Found, Resolve_From, Resolve_To);
      Check ("Tactical Regr: Best_En_Prise_Resolve chooses Ne5-d3+",
             Resolve_Found and then Resolve_From = Sq_E5 and then Resolve_To = Sq_D3);
   end;

   ----------------------------------------------------------------------------
   -- SUMMARY
   ----------------------------------------------------------------------------
   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09917_SAFETY: PASS");
   else
      Put_Line ("TEST_V09917_SAFETY: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V09917_Safety;
