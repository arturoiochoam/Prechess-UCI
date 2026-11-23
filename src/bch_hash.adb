-------------------------------------------------------------------------------
--  PRECHESS UCI - 64-BIT ZOBRIST HASHING IMPLEMENTATION
--
--  Module:        BCH_Hash (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Layer & Hashing Engine)
--  Date:          2026
-------------------------------------------------------------------------------

with Pvalidade;

package body BCH_Hash is

   ----------------------------------------------------------------------------
   --  ZOBRIST PSEUDO-RANDOM BASIS TABLES
   ----------------------------------------------------------------------------
   --  Static lookup arrays allocated in BSS. Populated at elaboration time.
   ----------------------------------------------------------------------------
   Zobrist_Pieces   : array (-20 .. 20, 1 .. 64) of Hash_Key;
   Zobrist_Side     : Hash_Key;
   Zobrist_Ep       : array (1 .. 64) of Hash_Key;
   Zobrist_Castling : array (0 .. 15) of Hash_Key;

   --  Dedicated tables for King pieces (+/- 999).
   --  CRITICAL ARCHITECTURAL FIX:
   --  Legacy engine uses piece codes +/-999 for Kings, which lie far outside
   --  the standard -20..20 piece array bounds. Dedicated tables prevent
   --  silent return of 0, ensuring distinct king placements hash to distinct keys
   --  and preventing false threefold repetition claims during endgame maneuvers.
   Zobrist_White_King : array (1 .. 64) of Hash_Key;
   Zobrist_Black_King : array (1 .. 64) of Hash_Key;
   
   Is_Initialized : Boolean := False;
   
   ----------------------------------------------------------------------------
   --  SPLITMIX64 PSEUDO-RANDOM NUMBER GENERATOR
   ----------------------------------------------------------------------------
   --  Algorithm: Guy L. Steele Jr., Doug Lea, Christine H. Flood (2014)
   --  "Fast splittable pseudorandom number generators" (OOPSLA '14)
   --
   --  RECURRENCE RELATION:
   --    S_{k+1} = S_k + \gamma  where \gamma = \text{0x9E3779B97F4A7C15} (\text{Golden Ratio fractional})
   --    Z = S_{k+1}
   --    Z = (Z \oplus (Z \gg 30)) \times \text{0xBF58476D1CE4E5B9}
   --    Z = (Z \oplus (Z \gg 27)) \times \text{0x94D049BB133111EB}
   --    Result = Z \oplus (Z \gg 31)
   --
   --  STATISTICAL VALIDATION: Passes TestU01 BigCrush, Dieharder, and PractRand.
   ----------------------------------------------------------------------------
   procedure Init_Zobrist is
      State : Hash_Key := 16253412351234123;

      function Next_Random return Hash_Key is
         Z : Hash_Key;
      begin
         State := State + 16#9E3779B97F4A7C15#;
         Z := State;
         Z := (Z xor (Z / 2**30)) * 16#BF58476D1CE4E5B9#;
         Z := (Z xor (Z / 2**27)) * 16#94D049BB133111EB#;
         return Z xor (Z / 2**31);
      end Next_Random;
   begin
      if Is_Initialized then
         return;
      end if;
      
      -- Initialize piece-square tables
      for P in -20 .. 20 loop
         for S in 1 .. 64 loop
            Zobrist_Pieces (P, S) := Next_Random;
         end loop;
      end loop;
      
      -- Initialize side-to-move key
      Zobrist_Side := Next_Random;
      
      -- Initialize en-passant square keys
      for S in 1 .. 64 loop
         Zobrist_Ep (S) := Next_Random;
      end loop;
      
      -- Initialize castling rights keys (4-bit domain [0 .. 15])
      for C in 0 .. 15 loop
         Zobrist_Castling (C) := Next_Random;
      end loop;

      -- Initialize dedicated King square keys
      for S in 1 .. 64 loop
         Zobrist_White_King (S) := Next_Random;
         Zobrist_Black_King (S) := Next_Random;
      end loop;

      Is_Initialized := True;
   end Init_Zobrist;

   ----------------------------------------------------------------------------
   --  LEAF KEY RETRIEVAL
   ----------------------------------------------------------------------------
   function Hash_Piece (Piece : Integer; Square : Integer) return Hash_Key is
   begin
      --  Empty squares (Piece = 0) contribute identity (0) under XOR.
      if Piece = 0 then
         return 0;
      elsif Piece = 999 then
         return Zobrist_White_King (Square);
      elsif Piece = -999 then
         return Zobrist_Black_King (Square);
      elsif Piece < -20 or Piece > 20 then
         --  Enforce piece codebook validity ({-20,-7,-4,-3,-1,0,1,3,4,7,20,999,-999}).
         --  Explicit raise surfaces illegal memory state immediately.
         raise Program_Error;
      end if;
      return Zobrist_Pieces (Piece, Square);
   end Hash_Piece;
   
   function Hash_Side return Hash_Key is
   begin
      return Zobrist_Side;
   end Hash_Side;
   
   function Hash_Ep (Square : Integer) return Hash_Key is
   begin
      if Square = 0 then
         return 0;
      end if;
      return Zobrist_Ep (Square);
   end Hash_Ep;
   
   function Hash_Castling (Rights : Integer) return Hash_Key is
   begin
      return Zobrist_Castling (Rights mod 16);
   end Hash_Castling;
   
   ----------------------------------------------------------------------------
   --  FULL POSITION RECOMPUTATION
   ----------------------------------------------------------------------------
   function Compute_Hash
     (White_To_Move   : Boolean;
      Ep_Square       : Integer;
      Castling_Rights : Integer) return Hash_Key
   is
      H : Hash_Key := 0;
   begin
      if not Is_Initialized then
         Init_Zobrist;
      end if;
      
      --  Iterate over 64-square 1D mailbox board
      for I in Pvalidade.tabuleiro'Range loop
         declare
            Piece : constant Integer := Pvalidade.tabuleiro (I);
         begin
            if Piece /= 0 then
               H := H xor Hash_Piece (Piece, I);
            end if;
         end;
      end loop;
      
      --  XOR side to move
      if White_To_Move then
         H := H xor Hash_Side;
      end if;

      --  XOR en-passant and castling rights
      H := H xor Hash_Ep (Ep_Square);
      H := H xor Hash_Castling (Castling_Rights);
      
      return H;
   end Compute_Hash;

begin
   --  Ensure tables are populated at package elaboration time.
   Init_Zobrist;
end BCH_Hash;
