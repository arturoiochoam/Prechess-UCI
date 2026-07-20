with TT_Types; use TT_Types;

package BCH_Hash is
   
   procedure Init_Zobrist;
   
   function Hash_Piece(Piece : Integer; Square : Integer) return Hash_Key;
   function Hash_Side return Hash_Key;
   function Hash_Ep(Square : Integer) return Hash_Key;
   function Hash_Castling(Rights : Integer) return Hash_Key;
   
   -- Computes the hash from scratch based on the legacy Tabuleiro
   function Compute_Hash(White_To_Move : Boolean; Ep_Square : Integer; Castling_Rights : Integer) return Hash_Key;

end BCH_Hash;
