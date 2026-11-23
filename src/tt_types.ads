-------------------------------------------------------------------------------
--  PRECHESS UCI - TRANSPOSITION TABLE CORE TYPE DEFINITIONS
--
--  Module:        TT_Types
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Layer & Core Types)
--  Date:          2026
--
--  ARCHITECTURAL ROLE:
--  `TT_Types` serves as the foundational, dependency-free leaf package for
--  the entire transposition table subsystem, telemetry counters, and move
--  primitives. By design, it carries no `with` dependencies on any other
--  engine package, breaking circular dependencies between the legacy board
--  representation (`Pvalidade`), the search bridge (`Search_Integration`),
--  and the transposition table engine (`TT_Table`).
--
--  MEMORY MODEL & HARDWARE TOPOLOGY:
--  - Zero Heap Allocation: All types defined herein are statically sized
--    and suitable for contiguous stack or BSS allocation.
--  - Cache-Line Locality: `TT_Entry` records are designed for compact
--    packing in multi-bucket array clusters, minimizing L1/L2 cache misses
--    during high-throughput branch evaluations.
--  - Word-Size Alignment: 64-bit unsigned modular integers (`Hash_Key`) map
--    directly to native 64-bit general-purpose registers (RAX/RDX on x86-64).
-------------------------------------------------------------------------------

package TT_Types is
   pragma Preelaborate;

   ----------------------------------------------------------------------------
   --  GLOBAL TELEMETRY INSTRUMENTATION
   ----------------------------------------------------------------------------
   --  Monotonically increasing 64-bit counter tracking the exact number of
   --  node evaluations and pseudo-legal/legal move validations across all
   --  search tiers (legacy cascade + 40-ply safety verifier).
   --
   --  Updated by the single search worker in `Pvalidade.Validade` and
   --  batched by `Tactical_Search.Tick`; not an atomic cross-task variable.
   --
   --  TIME COMPLEXITY:   O(1) per validation step
   --  SPACE COMPLEXITY:  8 bytes static BSS storage
   ----------------------------------------------------------------------------
   Nodes_Searched : Long_Long_Integer := 0;

   ----------------------------------------------------------------------------
   --  ZOBRIST HASH KEY
   ----------------------------------------------------------------------------
   --  64-bit unsigned modular type representing a Zobrist hash key.
   --  Operates under modulo 2^64 arithmetic with bitwise XOR commutativity:
   --    Key = Key_Side XOR Key_Piece(Sq, Piece) XOR Key_Castling(Rights) XOR Key_EP(File)
   --  Provides a collision resistance domain of 2^64 (~1.84 x 10^19 states).
   ----------------------------------------------------------------------------
   type Hash_Key is mod 2**64;

   ----------------------------------------------------------------------------
   --  SEARCH EVALUATION SCORE
   ----------------------------------------------------------------------------
   --  Discrete integer evaluation metric scaled in centipawns (cp) where:
   --    100 cp = 1 Pawn equivalent material
   --    +/- 900000+ cp = Checkmate distance bounds
   ----------------------------------------------------------------------------
   type Score_Type is range -1000000 .. 1000000;

   ----------------------------------------------------------------------------
   --  TRANSPOSITION TABLE NODE BOUND FLAG
   ----------------------------------------------------------------------------
   --  Defines the mathematical nature of the stored evaluation score:
   --  - Exact:       True minimax score (PV node, Alpha < Score < Beta)
   --  - Lower_Bound: Fail-high cut-off node (Beta cut-off, Score >= Beta)
   --  - Upper_Bound: Fail-low all-node (All moves searched, Score <= Alpha)
   ----------------------------------------------------------------------------
   type TT_Flag is (Exact, Lower_Bound, Upper_Bound);

   ----------------------------------------------------------------------------
   --  COMPACT MOVE PRIMITIVE
   ----------------------------------------------------------------------------
   --  Lightweight, 3-field discrete move representation:
   --  - From_Sq: Origin 1D mailbox square index [1 .. 64]
   --  - To_Sq:   Target 1D mailbox square index [1 .. 64]
   --  - Prom:    Promotion piece code (20 Queen, 7 Rook, 4 Knight,
   --             3 Bishop), or 0 for non-promotions.
   ----------------------------------------------------------------------------
   type Move_Type is record
      From_Sq : Integer range 1 .. 64;
      To_Sq   : Integer range 1 .. 64;
      Prom    : Integer range -20 .. 20; -- 0 means no promotion, else piece value
   end record;

   ----------------------------------------------------------------------------
   --  TRANSPOSITION TABLE ENTRY SLOT
   ----------------------------------------------------------------------------
   --  Primary atomic record stored within multi-bucket transposition tables.
   --
   --  FIELDS:
   --  - Occupied:   Distinguishes valid cached entries from vacant slots.
   --                Crucial because Zobrist XOR can mathematically evaluate
   --                to 0 (a valid non-empty key).
   --  - Key:        Full 64-bit Zobrist key used for exact match verification
   --                to eliminate aliasing collisions.
   --  - Depth:      Nominal search depth (in plies) at which the node was evaluated.
   --  - Score:      Centipawn score or mate-distance evaluation.
   --  - Flag:       Node bound classification (Exact, Lower_Bound, Upper_Bound).
   --  - Best:       Principal Variation (PV) / Best move harvested at this node.
   --  - Generation: Search epoch counter used for multi-bucket aging and
   --                replacement eviction.
   ----------------------------------------------------------------------------
   type TT_Entry is record
      Occupied   : Boolean;
      Key        : Hash_Key;
      Depth      : Integer;
      Score      : Score_Type;
      Flag       : TT_Flag;
      Best       : Move_Type;
      Generation : Natural;
   end record;

end TT_Types;
