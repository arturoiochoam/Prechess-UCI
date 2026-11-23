-------------------------------------------------------------------------------
--  PRECHESS UCI - 64-BIT ZOBRIST HASHING SUBSYSTEM
--
--  Module:        BCH_Hash
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Layer & Hashing Engine)
--  Date:          2026
--
--  MATHEMATICAL FOUNDATION & FORMAL SPECIFICATION:
--  Zobrist hashing maps arbitrary chess positions to 64-bit unsigned integers
--  via a universal bitwise XOR sum over pseudo-random basis vectors:
--
--    H(S) = ( \bigoplus_{sq=1}^{64} Z_{piece}(sq, Piece(sq)) )
--           \oplus Z_{side}(Side)
--           \oplus Z_{ep}(Legal\_EP\_Square)
--           \oplus Z_{castle}(Castling\_Rights)
--
--  PROPERTIES & INVARIANTS:
--  1. Involutive Self-Inverse: H(S) \oplus Z \oplus Z = H(S), enabling O(1)
--     incremental hash updating during alpha-beta move execution and unmaking.
--  2. Uniform Distribution: SplitMix64 pseudo-random generation guarantees
--     equidistribution across the 2^64 output domain, bounding hash collision
--     probability under the Birthday Paradox to P(collision) \approx N^2 / 2^{65}.
--  3. Repetition Detection: Provides probabilistic 64-bit identity for
--     threefold repetition checks under FIDE rules (Article 9.2); it is not
--     bijective, so exact-key comparison remains the collision guard.
--
--  COMPLEXITY & CONCURRENCY:
--  - Time Complexity:   O(1) for all leaf readers (`Hash_Piece`, `Hash_Side`, etc.);
--                       O(N) (N=64) for full-board recomputation (`Compute_Hash`).
--  - Space Complexity:  O(1) static BSS table allocation (approx. 22 KB).
--  - Thread Safety:     Read-only access after elaboration initialization.
-------------------------------------------------------------------------------

with TT_Types; use TT_Types;

package BCH_Hash is
   
   ----------------------------------------------------------------------------
   --  INITIALIZATION
   ----------------------------------------------------------------------------
   --  Generates all pseudo-random 64-bit Zobrist basis keys via SplitMix64 PRNG.
   --  Idempotent: called automatically during package elaboration.
   ----------------------------------------------------------------------------
   procedure Init_Zobrist;
   
   ----------------------------------------------------------------------------
   --  LEAF ZOBRIST KEY READERS (INLINED)
   ----------------------------------------------------------------------------
   --  Retrieves the random basis key for a piece on a given square.
   --  Returns 0 for empty squares (Piece = 0).
   --  Handles standard pieces [-20 .. 20] and special King codes (+/- 999).
   ----------------------------------------------------------------------------
   function Hash_Piece (Piece : Integer; Square : Integer) return Hash_Key
     with Pre => Square in 1 .. 64;

   --  Returns the basis key for White-to-move side-to-move toggling.
   function Hash_Side return Hash_Key;

   --  Returns the basis key for an active en-passant target square (0 = none).
   function Hash_Ep (Square : Integer) return Hash_Key
     with Pre => Square in 0 .. 64;

   --  Returns the basis key for the 4-bit castling rights bitmask [0 .. 15].
   function Hash_Castling (Rights : Integer) return Hash_Key;
   
   ----------------------------------------------------------------------------
   --  FULL STATE RECOMPUTATION
   ----------------------------------------------------------------------------
   --  Computes the complete 64-bit Zobrist key from scratch by scanning
   --  the entire 64-square `Pvalidade.Tabuleiro` mailbox board.
   --
   --  PARAMETERS:
   --  - White_To_Move:   True if White is on move, False for Black.
   --  - Ep_Square:       En-passant target square index [0 .. 64].
   --  - Castling_Rights: Bitmask encoding (bit 0: W-OO, 1: W-OOO, 2: B-OO, 3: B-OOO).
   --
   --  POST-CONDITION: Returns a deterministic 64-bit Zobrist signature.
   ----------------------------------------------------------------------------
   function Compute_Hash
     (White_To_Move   : Boolean;
      Ep_Square       : Integer;
      Castling_Rights : Integer) return Hash_Key;

   --  Inline leaf readers to allow compiler cross-unit folding (-gnatn2).
   pragma Inline (Hash_Piece);
   pragma Inline (Hash_Side);
   pragma Inline (Hash_Ep);
   pragma Inline (Hash_Castling);

end BCH_Hash;
