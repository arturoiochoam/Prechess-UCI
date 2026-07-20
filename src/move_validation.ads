--  Move_Validation tracks the UCI-visible game state that the legacy
--  Pvalidade/Pprechess2 engine core has no concept of at all: castling
--  rights, the en-passant target square, and the derived legality rules
--  (attacked-square detection, check detection, castling legality) that
--  both castling and en-passant require. None of this existed anywhere
--  in the 0.7.8 codebase (Pvalidade.Validade explicitly never allows
--  en-passant to occur, and never considers castling), so this is new,
--  self-contained functionality layered cleanly on top of the legacy
--  board representation (Pvalidade.Tabuleiro) rather than a patch
--  scattered through the legacy search.
package Move_Validation is

   type Move_Type is record
      From_Sq : Integer range 1 .. 64;
      To_Sq   : Integer range 1 .. 64;
      Prom    : Integer range -20 .. 20;
   end record;

   --  UCI state tracking for castling and en passant. Reset at the start
   --  of every game/position and maintained move-by-move by
   --  Search_Integration.Make_Move_UCI.
   White_Castling_K : Boolean := True;
   White_Castling_Q : Boolean := True;
   Black_Castling_K : Boolean := True;
   Black_Castling_Q : Boolean := True;

   --  0 means "no en-passant capture available this move", else the
   --  square a pawn skipped over on its last double-step (the square a
   --  capturing pawn would land on).
   En_Passant_Sq : Integer := 0;

   procedure Reset_State;

   procedure Set_Castling_Rights
     (White_K, White_Q, Black_K, Black_Q : Boolean);

   --  Bit 0 = White O-O, bit 1 = White O-O-O, bit 2 = Black O-O,
   --  bit 3 = Black O-O-O. Feeds BCH_Hash.Compute_Hash so castling
   --  rights are part of the Zobrist key used for repetition detection.
   function Castling_Rights_Bits return Integer
     with Post => Castling_Rights_Bits'Result in 0 .. 15;

   function Rank_Of (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => Rank_Of'Result in 1 .. 8;

   function File_Of (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => File_Of'Result in 1 .. 8;

   function Square_Of (Rank, File : Integer) return Integer
     with Pre  => Rank in 1 .. 8 and then File in 1 .. 8,
          Post => Square_Of'Result in 1 .. 64;

   --  Re-orients the board for the legacy engine, which only ever
   --  searches assuming its own pieces are the positive side sitting on
   --  the low ranks: rank r -> 9 - r, file unchanged. This is a
   --  reflection (self-inverse) that preserves every piece's legal
   --  move geometry (ranks, files and diagonals all map onto
   --  themselves), so it is a valid color-swap for the whole board.
   function Mirror_Square (Sq : Integer) return Integer
     with Pre  => Sq in 1 .. 64,
          Post => Mirror_Square'Result in 1 .. 64;

   --  True if the square Sq is attacked by the given side, per the
   --  current contents of Pvalidade.Tabuleiro. Pawns are handled by
   --  their diagonal attack squares directly (not via Pvalidade.Validade,
   --  which conflates a pawn's quiet-move and capture geometry based on
   --  target-square occupancy and therefore cannot answer "is this
   --  empty square attacked by an enemy pawn").
   function Is_Square_Attacked (Sq : Integer; By_White : Boolean) return Boolean
     with Pre => Sq in 1 .. 64;

   --  Locates the king (999 or -999) for the given side. Returns 0 only
   --  if the position has no such king, which should never happen in a
   --  legal game.
   function Find_King (White_King : Boolean) return Integer
     with Post => Find_King'Result in 0 .. 64;

   function Is_In_Check (White_King : Boolean) return Boolean;

   --  Home square of the a- or h-file rook for the given side, used by
   --  both castling-legality checks and castling-rights maintenance.
   function Home_Rook_Square (White : Boolean; Kingside : Boolean) return Integer
     with Post => Home_Rook_Square'Result in 1 .. 64;

   --  Full FIDE castling legality for the side to move: rights intact,
   --  the rook still on its home square, the squares between king and
   --  rook empty, and the king neither in check, nor passing through,
   --  nor landing on an attacked square.
   function Is_Castle_Legal (White_To_Move : Boolean; Kingside : Boolean) return Boolean;

   --  Hops the rook to its post-castling square. The king's own hop is
   --  applied by the caller exactly like any other move.
   procedure Apply_Castle_Rook_Move (White_To_Move : Boolean; Kingside : Boolean);

   --  Updates castling rights after a move: clears both rights for a
   --  side whose king moves, clears the relevant right when a rook
   --  moves off (or is captured on) its home square.
   procedure Update_Rights_After_Move
     (From_Sq, To_Sq : Integer; Moved_Piece : Integer);

end Move_Validation;
