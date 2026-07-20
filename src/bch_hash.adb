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
      if Piece = 999 then
         return Zobrist_White_King(Square);
      elsif Piece = -999 then
         return Zobrist_Black_King(Square);
      elsif Piece < -20 or Piece > 20 then
         return 0;
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
         if Pvalidade.tabuleiro(I) /= 0 then
            H := H xor Hash_Piece(Pvalidade.tabuleiro(I), I - Pvalidade.tabuleiro'First + 1);
         end if;
      end loop;
      
      if White_To_Move then
         H := H xor Zobrist_Side;
      end if;
      
      if Ep_Square /= 0 then
         H := H xor Zobrist_Ep(Ep_Square);
      end if;
      
      H := H xor Zobrist_Castling(Castling_Rights);
      
      return H;
   end Compute_Hash;

end BCH_Hash;
