with TT_Types; use TT_Types;

package BCH_Hash is
   
   procedure Init_Zobrist;
   
   function Hash_Piece(Piece : Integer; Square : Integer) return Hash_Key
     with Pre => Square in 1 .. 64;
   function Hash_Side return Hash_Key;
   function Hash_Ep(Square : Integer) return Hash_Key
     with Pre => Square in 0 .. 64;
   function Hash_Castling(Rights : Integer) return Hash_Key;
   
   -- Computes the hash from scratch based on the legacy Tabuleiro
   function Compute_Hash(White_To_Move : Boolean; Ep_Square : Integer; Castling_Rights : Integer) return Hash_Key;

   --  The Zobrist leaf readers are tiny and side-effect-free; inline them
   --  so -gnatn2 can fold Compute_Hash's per-square calls.
   pragma Inline (Hash_Piece);
   pragma Inline (Hash_Side);
   pragma Inline (Hash_Ep);
   pragma Inline (Hash_Castling);

end BCH_Hash;
