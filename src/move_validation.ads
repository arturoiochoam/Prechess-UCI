-------------------------------------------------------------------------------
--  PRECHESS UCI - FIDE RULES & DERIVED LEGALITY ENGINE
--
--  Module:        Move_Validation
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (FIDE Rules & Legality Layer)
--  Date:          2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Move_Validation` encapsulates all FIDE game-state attributes that the legacy
--  2001 engine (`Pvalidade` / `Pprechess2`) lacked:
--  1. Castling Rights State Tracking (`White_Castling_K/Q`, `Black_Castling_K/Q`).
--  2. En-Passant Target Square Tracking (`En_Passant_Sq`).
--  3. Attacked-Square Detection & In-Check Derivation (`Is_Square_Attacked`, `Is_In_Check`).
--  4. Full FIDE Castling Legality Verification (`Is_Castle_Legal`, Article 3.8.2).
--  5. 2D <-> 1D Coordinate Mappings & Board Geometry Transformations.
--
--  BOARD GEOMETRY & COORDINATE MAPPINGS:
--  - 1D Mailbox Index: `Sq \in [1 .. 64]`
--  - Rank Mapping:     `Rank(Sq) = \lfloor (Sq - 1) / 8 \rfloor + 1 \in [1 .. 8]`
--  - File Mapping:     `File(Sq) = ((Sq - 1) \pmod 8) + 1 \in [1 .. 8]`
--  - Square Mapping:   `Sq(Rank, File) = (Rank - 1) \times 8 + File`
--  - Color Mirroring:  `Mirror(Sq) = Sq(9 - Rank(Sq), File(Sq))`
--
--  PERFORMANCE & CONTRACTS:
--  - Inlined Leaf Mappings: `Rank_Of`, `File_Of`, `Square_Of`, and `Mirror_Square`
--    are fully inlined (`pragma Inline`) with formal Pre/Post contract aspects.
--  - Attack Ray Casting: Efficient directional ray traversal terminating on the
--    first blocking piece.
-------------------------------------------------------------------------------

with Interfaces; use Interfaces;

package Move_Validation is
   pragma Elaborate_Body;

   ----------------------------------------------------------------------------
   --  FIDE GAME STATE ATTRIBUTES
   ----------------------------------------------------------------------------
   White_Castling_K : Boolean := True;
   White_Castling_Q : Boolean := True;
   Black_Castling_K : Boolean := True;
   Black_Castling_Q : Boolean := True;

   --  0 indicates no active en-passant target square; otherwise 1 .. 64.
   En_Passant_Sq : Integer := 0;

   ----------------------------------------------------------------------------
   --  STATE INITIALIZATION & SYNCHRONIZATION
   ----------------------------------------------------------------------------
   --  Resets castling rights to all-true and en-passant to 0.
   procedure Reset_State;

   --  Explicitly sets the 4 castling rights flags (used when parsing FEN).
   procedure Set_Castling_Rights
     (White_K, White_Q, Black_K, Black_Q : Boolean);

   --  Encodes the 4 castling rights into a 4-bit integer [0 .. 15]:
   --    Bit 0: White Kingside  (O-O)
   --    Bit 1: White Queenside (O-O-O)
   --    Bit 2: Black Kingside  (O-O)
   --    Bit 3: Black Queenside (O-O-O)
   function Castling_Rights_Bits return Integer
     with Post => Castling_Rights_Bits'Result in 0 .. 15;

   ----------------------------------------------------------------------------
   --  COORDINATE ARITHMETIC & GEOMETRY (INLINED)
   ----------------------------------------------------------------------------
   function Rank_Of (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => Rank_Of'Result in 1 .. 8;

   function File_Of (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => File_Of'Result in 1 .. 8;

   function Square_Of (Rank, File : Integer) return Integer
     with Pre  => Rank in 1 .. 8 and then File in 1 .. 8,
          Post => Square_Of'Result in 1 .. 64;

   --  Re-orients the square across the horizontal axis (Rank r -> 9 - r)
   --  for the legacy engine's internal perspective.
   function Mirror_Square (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => Mirror_Square'Result in 1 .. 64;

   ----------------------------------------------------------------------------
   --  PRECALCULATED RAY OBSTRUCTION MATRIX (64x64)
   ----------------------------------------------------------------------------
   --  Bitmask representation: Bit (Sq - 1) corresponds to Square Sq.
   --  Ray_Between(Sq1, Sq2) contains the bitmask of squares strictly between
   --  Sq1 and Sq2 along straight/diagonal rays (or 0 if not collinear).
   type Ray_Table_Type is array (1 .. 64, 1 .. 64) of Interfaces.Unsigned_64;
   Ray_Between : Ray_Table_Type;

   procedure Init_Ray_Tables;

   function Square_Bitmask (Sq : Integer) return Interfaces.Unsigned_64
     with Inline, Pre => Sq in 1 .. 64;

   function Occupied_Bitmask return Interfaces.Unsigned_64
     with Inline;

   function Is_Ray_Clear (From_Sq, To_Sq : Integer) return Boolean
     with Inline, Pre => From_Sq in 1 .. 64 and then To_Sq in 1 .. 64;

   ----------------------------------------------------------------------------
   --  TACTICAL ATTACK & CHECK DETECTION
   ----------------------------------------------------------------------------
   --  Evaluates whether target square `Sq` is under attack by any piece of side `By_White`.
   --  Pawns are evaluated via direct diagonal attack geometries (not via `Pvalidade.Validade`).
   function Is_Square_Attacked (Sq : Integer; By_White : Boolean) return Boolean
     with Pre => Sq in 1 .. 64;

   --  Locates the King (+999 or -999) for the specified color.
   --  Returns 0 only if no King exists on the board.
   function Find_King (White_King : Boolean) return Integer
     with Post => Find_King'Result in 0 .. 64;

   --  Returns True iff the specified King is currently in check.
   function Is_In_Check (White_King : Boolean) return Boolean;

   ----------------------------------------------------------------------------
   --  FIDE CASTLING MECHANICS (Article 3.8.2)
   ----------------------------------------------------------------------------
   --  Returns the initial home square of the rook (a1/h1 for White, a8/h8 for Black).
   function Home_Rook_Square (White : Boolean; Kingside : Boolean) return Integer
     with Post => Home_Rook_Square'Result in 1 .. 64;

   --  Verifies complete FIDE castling legality:
   --  1. Castling right bit must be active.
   --  2. King and Rook must reside on their exact home squares.
   --  3. All intermediate squares between King and Rook must be empty.
   --  4. King must not be in check, nor pass through or land on attacked squares.
   function Is_Castle_Legal (White_To_Move : Boolean; Kingside : Boolean) return Boolean;

   --  Executes the secondary rook jump during castling.
   procedure Apply_Castle_Rook_Move (White_To_Move : Boolean; Kingside : Boolean);

   --  Mutates castling rights following a move execution:
   --  - King move: Clears both rights for that color.
   --  - Rook move / Rook capture: Clears the corresponding flank right.
   procedure Update_Rights_After_Move
     (From_Sq, To_Sq : Integer; Moved_Piece : Integer);

   --  Pragma Inline directives for hot execution paths.
   pragma Inline (Rank_Of);
   pragma Inline (File_Of);
   pragma Inline (Square_Of);
   pragma Inline (Mirror_Square);
   pragma Inline (Castling_Rights_Bits);
   --  0.9.9.17.20: attack/check probes run 60-100x per search node.
   pragma Inline (Is_Square_Attacked);
   pragma Inline (Find_King);
   pragma Inline (Is_In_Check);

end Move_Validation;
