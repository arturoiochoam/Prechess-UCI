-------------------------------------------------------------------------------
--  PRECHESS UCI - LEGAL MOVE GENERATOR & PERFT VERIFICATION ENGINE
--
--  Module:        Move_Gen
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Perft & Legal Move Engine)
--  Date:          2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Move_Gen` provides a complete, strictly legal move generator and Perft
--  (Performance Test) verification harness. It operates strictly in parallel
--  to the legacy search cascade (`Pprechess2`), leaving the legacy engine's
--  heuristic move-ordering untouched while providing a 100% standard-compliant
--  FIDE move generator for `go perft <Depth>` diagnostics and engine audits.
--
--  GENERATION & VALIDATION PIPELINE:
--  1. Pseudo-Legal Generation (`Gen_Pseudo`):
--     - Queries `Pvalidade.Validade` for normal sliding and leaping moves.
--     - Generates 4 underpromotions (Q, R, B, N) for 8th-rank pawn moves.
--     - Generates FIDE castling moves (O-O and O-O-O) via `Is_Castle_Legal`.
--     - Generates diagonal En-Passant pawn captures to empty target squares.
--  2. Make / Unmake State Transitions:
--     - Simulates moves via copy-make, updating en-passant square and castling rights.
--  3. Legality Filter:
--     - Filters out pseudo-legal moves that leave the moving King in check.
--
--  FORMAL INVARIANTS & VERIFICATION TARGETS:
--  - Startpos Perft Depth 5: Exactly 4,865,609 leaf nodes.
--  - Kiwipete Perft Depth 5: Exactly 193,690,690 leaf nodes.
--  - O(1) Heap Footprint: All move buffers are stack-allocated fixed arrays (`Max_Moves = 256`).
-------------------------------------------------------------------------------

package Move_Gen is

   ----------------------------------------------------------------------------
   --  MOVE TYPES & BUFFER DEFINITIONS
   ----------------------------------------------------------------------------
   Max_Moves : constant := 256;

   type Move_Rec is record
      From  : Integer;
      To    : Integer;
      Promo : Integer;   -- 0 = none, else 20(Q), 7(R), 4(N), 3(B)
   end record;

   --  Shared UCI coordinate formatter used by every search reporter.
   function Move_To_UCI (M : Move_Rec) return String;

   type Move_Array is array (1 .. Max_Moves) of Move_Rec;

   type Move_List is record
      V : Move_Array;
      N : Natural := 0;
   end record;

   ----------------------------------------------------------------------------
   --  LEGAL MOVE GENERATION
   ----------------------------------------------------------------------------
   procedure Generate_Legal_Moves
     (White_To_Move : Boolean;
      List          : out Move_List);

   --  Copy-make primitive (board, castling rights, en-passant square).
   --  Callers save/restore Pvalidade.Tabuleiro and Move_Validation state
   --  themselves. Used by Tactical_Search.
   procedure Make_Move (F, T, Promo : Integer; White : Boolean);

   ----------------------------------------------------------------------------
   --  PERFT RECURSIVE ENUMERATION
   ----------------------------------------------------------------------------
   --  Recursively computes the exact number of legal leaf nodes to `Depth`
   --  from the current position in `Pvalidade.Tabuleiro`.
   --
   --  PARAMETERS:
   --  - Depth:         Remaining search depth (plies). Depth 0 returns 1.
   --  - White_To_Move: Color to move at the current node.
   --
   --  POST-CONDITION: Returns the exact discrete combinatorial node count.
   ----------------------------------------------------------------------------
   function Perft (Depth : Natural; White_To_Move : Boolean) return Long_Long_Integer;

   ----------------------------------------------------------------------------
   --  PERFT DIVIDE ROOT DIAGNOSTIC
   ----------------------------------------------------------------------------
   --  Prints a Stockfish-style divide report to Standard_Output:
   --    "<move_uci> <leaf_count>" for every legal root move,
   --    followed by "perft <Depth> <total_nodes>".
   ----------------------------------------------------------------------------
   procedure Perft_Divide (Depth : Positive; White_To_Move : Boolean);

end Move_Gen;
