with Pvalidade;

package body BCH_Hash is

   Zobrist_Pieces : array (-20 .. 20, 1 .. 64) of Hash_Key;
   Zobrist_Side   : Hash_Key;
   Zobrist_Ep     : array (1 .. 64) of Hash_Key;
   Zobrist_Castling : array (0 .. 15) of Hash_Key;

   --  Kings use piece codes +/-999, far outside the -20..20 piece
   --  array. The original Hash_Piece silently returned 0 for them,
   --  which meant KING POSITIONS WERE NOT HASHED AT ALL: any two
   --  positions differing only in king placement collided, and since
   --  this hash's one consumer is the threefold-repetition history,
   --  the engine would declare "draw by repetition" after kings merely
   --  maneuvered through distinct squares (reproduced in a won K+R vs
   --  K endgame: six distinct positions, instant false draw claim).
   Zobrist_White_King : array (1 .. 64) of Hash_Key;
   Zobrist_Black_King : array (1 .. 64) of Hash_Key;
   
   Is_Initialized : Boolean := False;
   
   procedure Init_Zobrist is
      Seed : Hash_Key := 16253412351234123;
      function Next_Random return Hash_Key is
      begin
         Seed := Seed xor (Seed * 2**13);
         Seed := Seed xor (Seed / 2**7);
         Seed := Seed xor (Seed * 2**17);
         return Seed;
      end Next_Random;
   begin
      if Is_Initialized then return; end if;
      
      for P in -20 .. 20 loop
         for S in 1 .. 64 loop
            Zobrist_Pieces(P, S) := Next_Random;
         end loop;
      end loop;
      
      Zobrist_Side := Next_Random;
      
      for S in 1 .. 64 loop
         Zobrist_Ep(S) := Next_Random;
      end loop;
      
      for C in 0 .. 15 loop
         Zobrist_Castling(C) := Next_Random;
      end loop;

      for S in 1 .. 64 loop
         Zobrist_White_King(S) := Next_Random;
      end loop;
      for S in 1 .. 64 loop
         Zobrist_Black_King(S) := Next_Random;
      end loop;

      Is_Initialized := True;
   end Init_Zobrist;

   function Hash_Piece(Piece : Integer; Square : Integer) return Hash_Key is
   begin
      --  Piece = 0 (empty square) must contribute nothing to the hash.
      --  Compute_Hash skips empties, but this leaf is a public entry
      --  point and Zobrist_Pieces (0, Square) is a real random key
      --  (the init loop covers -20..20 inclusive), so an incremental or
      --  direct caller would otherwise XOR a phantom value into the key
      --  and corrupt repetition detection.
      if Piece = 0 then
         return 0;
      elsif Piece = 999 then
         return Zobrist_White_King(Square);
      elsif Piece = -999 then
         return Zobrist_Black_King(Square);
      elsif Piece < -20 or Piece > 20 then
         --  Unreachable for the engine's piece codebook
         --  ({-20,-7,-4,-3,-1,0,1,3,4,7,20,999,-999}); the +/-999 kings
         --  are handled just above. Raise rather than silently returning 0
         --  (which would corrupt repetition detection), so any future
         --  piece-code drift surfaces immediately. NB: a raise statement is
         --  NOT a runtime check, so -gnatp does not suppress it.
         raise Program_Error;
      end if;
      return Zobrist_Pieces(Piece, Square);
   end Hash_Piece;
   
   function Hash_Side return Hash_Key is
   begin
      return Zobrist_Side;
   end Hash_Side;
   
   function Hash_Ep(Square : Integer) return Hash_Key is
   begin
      if Square = 0 then return 0; end if;
      return Zobrist_Ep(Square);
   end Hash_Ep;
   
   function Hash_Castling(Rights : Integer) return Hash_Key is
   begin
      return Zobrist_Castling(Rights mod 16);
   end Hash_Castling;
   
   function Compute_Hash(White_To_Move : Boolean; Ep_Square : Integer; Castling_Rights : Integer) return Hash_Key is
      H : Hash_Key := 0;
   begin
      if not Is_Initialized then Init_Zobrist; end if;
      
      for I in Pvalidade.tabuleiro'Range loop
         --  Hoist the global array read once per iteration. The square
         --  index is simply I: tabuleiro is 1..64, so I - 'First + 1 = I.
         declare
            Piece : constant Integer := Pvalidade.tabuleiro(I);
         begin
            if Piece /= 0 then
               H := H xor Hash_Piece(Piece, I);
            end if;
         end;
      end loop;
      
      if White_To_Move then
         H := H xor Hash_Side;
      end if;

      --  Route EP/castling through the public helpers so Compute_Hash
      --  shares their input contract instead of indexing the private
      --  Zobrist arrays directly. Concretely: Hash_Castling reduces
      --  Rights mod 16, so an out-of-range Castling_Rights no longer
      --  raises Constraint_Error here; Hash_Ep guards Square = 0.
      H := H xor Hash_Ep (Ep_Square);
      H := H xor Hash_Castling (Castling_Rights);
      
      return H;
   end Compute_Hash;

begin
   --  Populate the Zobrist tables at elaboration so every public entry
   --  point -- including the leaf Hash_Piece/Hash_Side/Hash_Ep/
   --  Hash_Castling readers, not just Compute_Hash -- observes
   --  initialized data. Without this, a caller that hit a leaf before
   --  the first Compute_Hash would read the all-zero default and every
   --  position would collapse to the same key.
   Init_Zobrist;
end BCH_Hash;
