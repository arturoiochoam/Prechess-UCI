-------------------------------------------------------------------------------
--  PRECHESS UCI - MAILBOX BOARD REPRESENTATION & MOVEMENT ORACLE
--
--  Module:        Pvalidade
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        José Lauro Strapasson (Original 2001 Core)
--                 Arthur Matheus (Ada 2022 Contracts, Optimizations & Telemetry)
--  Date:          2001-2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Pvalidade` defines the foundational 1D Mailbox board data structure (`Tabuleiro`)
--  and the pseudo-legal geometric movement validation oracle (`Validade`).
--
--  COORDINATE & PIECE MAPPING:
--  - Board Topology: 1D flat array [1 .. 64], 1-indexed, row-major:
--      Square 1  = a1, Square 8  = h1,
--      Square 57 = a8, Square 64 = h8.
--  - Piece Value Codebook:
--      White Pieces: Pawn (+1), Knight (+4), Bishop (+3), Rook (+7), Queen (+20), King (+999)
--      Black Pieces: Pawn (-1), Knight (-4), Bishop (-3), Rook (-7), Queen (-20), King (-999)
--      Vacant Square: 0
--
--  PERFORMANCE & MEMORY INVARIANTS:
--  - O(1) Access: Direct mailbox array lookup with zero dereferencing indirection.
--  - Zero Heap Allocations: 100% static BSS storage (`Storage_Error` immune).
--  - Unified Telemetry Funnel: Every call through `Validade` increments
--    `TT_Types.Nodes_Searched`, ensuring 100% accurate NPS telemetry.
-------------------------------------------------------------------------------

package Pvalidade is

   subtype Square is Integer range 1 .. 64;
   type Board_Array is array (Square) of Integer;

   ----------------------------------------------------------------------------
   --  PRIMARY GLOBAL BOARD STATE
   ----------------------------------------------------------------------------
   --  Global mailbox array referenced directly by all legacy search cascades,
   --  trial move simulators, and UCI position synchronizers.
   ----------------------------------------------------------------------------
   Tabuleiro : Board_Array;

   ----------------------------------------------------------------------------
   --  GEOMETRIC MOVEMENT ORACLE
   ----------------------------------------------------------------------------
   --  Evaluates whether a pseudo-legal move from square `A` to square `B` is
   --  geometrically valid for the piece on `A`:
   --  - Pawns: Single/double pushes, diagonal captures.
   --  - Knights: L-shaped leaps (dx^2 + dy^2 = 5).
   --  - Bishops / Rooks / Queens: Sliding ray collision checks.
   --  - Kings: 1-square step in 8 directions.
   --
   --  PRE-CONDITIONS:
   --  - `A` in 1 .. 64 and `B` in 1 .. 64.
   --
   --  POST-CONDITIONS:
   --  - Returns True iff the move conforms to geometric rules and intermediate
   --    sliding squares are vacant.
   --  - Does NOT check for king check exposure (handled by `Move_Validation`).
   ----------------------------------------------------------------------------
   function Validade (A, B : in Integer) return Boolean
     with Pre => A in Square and then B in Square;

end Pvalidade;
