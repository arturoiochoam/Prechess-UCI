-------------------------------------------------------------------------------
--  PRECHESS UCI - TACTICAL VERIFICATION SEARCH
--
--  Module:   Tactical_Search
--  Language: Ada 2022
--
--  Real negamax alpha-beta (iterative deepening, check extension, killer
--  moves, triangular PV) with a capture/promotion quiescence search and
--  exact checkmate/stalemate detection, running on Pvalidade.Tabuleiro via
--  Move_Gen's legal generator and copy-make.
--
--  Purpose: the legacy heuristic cascade picks the move; this search then
--  checks that move against every legal alternative. If some alternative is
--  provably better by >= Veto_Margin_Cp at the completed depth (hanging a
--  piece, missing a fork / mate, walking into mate), the cascade move is
--  replaced. Scores are side-to-move relative; mate = Mate_Value - plies,
--  so "score mate N" is only ever reported for a mate the tree proved.
-------------------------------------------------------------------------------

with Move_Gen;

package Tactical_Search is

   Mate_Value     : constant := 32000;
   Mate_Threshold : constant := 31000;
   Veto_Margin_Cp : constant := 25;   --  Step 4 sweep winner (was 100)
   Max_Ply        : constant := 64;

   type PV_Array is array (1 .. Max_Ply) of Move_Gen.Move_Rec;

   Empty_Move_List : constant Move_Gen.Move_List :=
     (V => [others => (0, 0, 0)], N => 0);

   type Verify_Result is record
      Valid        : Boolean := False;  --  at least depth 1 completed
      Depth        : Natural := 0;      --  deepest completed iteration
      Seldepth     : Natural := 0;
      Nodes        : Long_Long_Integer := 0;
      Chosen_Score : Integer := 0;      --  exact score of the cascade move
      Best_Score   : Integer := 0;      --  score of the move returned
      Best         : Move_Gen.Move_Rec := (0, 0, 0);
      Replaced     : Boolean := False;  --  Best /= cascade move
      PV           : PV_Array;
      PV_Len       : Natural := 0;
   end record;

   --  Static evaluation, White-relative centipawns (material, pawn
   --  advancement, passed pawns, bishop pair).
   function Evaluate_White return Integer;

   --  Perft over the internal fast generator (validated against
   --  Move_Gen.Perft in test_v099177_tactical).
   function Perft_Fast (Depth : Natural; White : Boolean) return Long_Long_Integer;

   --  Size the verifier's transposition table from the UCI "Hash" option.
   --  Takes effect at the start of the next Verify (never mid-search).
   procedure Set_Hash_MB (MB : Positive);

   --  Number of entries in the verifier table currently allocated.
   function Current_Hash_Entries return Natural;

   --  Clears the verifier transposition table and applies any pending Hash resize.
   procedure Clear_TT;

   --  Verify the cascade choice (Chosen_*) for White_To_Move on the current
   --  board. Budget_Ms bounds wall time, with a small hard grace period;
   --  UCI stop and the shared node budget can also abort the search.
   --  Margin_Cp sets the minimum centipawn improvement required to replace
   --  the cascade choice (defaults to Veto_Margin_Cp = 25); at shallow depths
   --  D < 6, non-mate replacement also requires a >= 250 cp gap.
   --  The board and Move_Validation state are restored on return.
   --  Report_Progress emits one shared Report_PV line per completed iteration.
   function Verify
     (White_To_Move      : Boolean;
      Chosen_From, Chosen_To, Chosen_Promo : Integer;
      Budget_Ms          : Natural;
      Max_Depth          : Positive := 12;
      Margin_Cp          : Natural := Veto_Margin_Cp;
      Report_Progress    : Boolean := False;
      Searchmoves_Filter : Move_Gen.Move_List := Empty_Move_List;
      Mate_Target        : Natural := 0) return Verify_Result;

end Tactical_Search;
