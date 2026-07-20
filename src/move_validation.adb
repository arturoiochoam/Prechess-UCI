with Pvalidade;

package body Move_Validation is

   procedure Reset_State is
   begin
      White_Castling_K := True;
      White_Castling_Q := True;
      Black_Castling_K := True;
      Black_Castling_Q := True;
      En_Passant_Sq := 0;
   end Reset_State;

   procedure Set_Castling_Rights
     (White_K, White_Q, Black_K, Black_Q : Boolean) is
   begin
      White_Castling_K := White_K;
      White_Castling_Q := White_Q;
      Black_Castling_K := Black_K;
      Black_Castling_Q := Black_Q;
   end Set_Castling_Rights;

   function Castling_Rights_Bits return Integer is
      Bits : Integer := 0;
   begin
      if White_Castling_K then Bits := Bits + 1; end if;
      if White_Castling_Q then Bits := Bits + 2; end if;
      if Black_Castling_K then Bits := Bits + 4; end if;
      if Black_Castling_Q then Bits := Bits + 8; end if;
      return Bits;
   end Castling_Rights_Bits;

   function Rank_Of (Sq : Integer) return Integer is
   begin
      return (Sq - 1) / 8 + 1;
   end Rank_Of;

   function File_Of (Sq : Integer) return Integer is
   begin
      return (Sq - 1) mod 8 + 1;
   end File_Of;

   function Square_Of (Rank, File : Integer) return Integer is
   begin
      return (Rank - 1) * 8 + File;
   end Square_Of;

   function Mirror_Square (Sq : Integer) return Integer is
   begin
      return Square_Of (9 - Rank_Of (Sq), File_Of (Sq));
   end Mirror_Square;

   function Is_Square_Attacked (Sq : Integer; By_White : Boolean) return Boolean is
      R : constant Integer := Rank_Of (Sq);
      F : constant Integer := File_Of (Sq);

      function Piece_Is_Attacker (P : Integer) return Boolean is
      begin
         if By_White then
            return P > 0;
         else
            return P < 0;
         end if;
      end Piece_Is_Attacker;

      --  Ray-cast in one direction (Dr, Df) from (R, F); True if the
      --  first occupied square hit belongs to the attacker and matches
      --  one of the Wanted piece codes (unsigned, e.g. 7 for rook).
      function Ray_Hits (Dr, Df, Wanted1, Wanted2 : Integer) return Boolean is
         Cr, Cf, Csq, P : Integer;
      begin
         Cr := R + Dr;
         Cf := F + Df;
         while Cr in 1 .. 8 and then Cf in 1 .. 8 loop
            Csq := Square_Of (Cr, Cf);
            P := Pvalidade.Tabuleiro (Csq);
            if P /= 0 then
               if Piece_Is_Attacker (P)
                 and then (abs P = Wanted1 or else abs P = Wanted2)
               then
                  return True;
               end if;
               return False; -- blocked by some other piece
            end if;
            Cr := Cr + Dr;
            Cf := Cf + Df;
         end loop;
         return False;
      end Ray_Hits;

      function Square_Has (Dr, Df, Wanted : Integer) return Boolean is
         Cr : constant Integer := R + Dr;
         Cf : constant Integer := F + Df;
      begin
         if Cr in 1 .. 8 and then Cf in 1 .. 8 then
            declare
               P : constant Integer := Pvalidade.Tabuleiro (Square_Of (Cr, Cf));
            begin
               return Piece_Is_Attacker (P) and then abs P = Wanted;
            end;
         end if;
         return False;
      end Square_Has;

   begin
      --  Pawns: a white pawn attacks the two squares diagonally ahead of
      --  it (higher rank); a black pawn attacks diagonally ahead in the
      --  direction of decreasing rank. We are looking from the target
      --  square back toward where such an attacking pawn would sit.
      if By_White then
         if Square_Has (-1, -1, 1) or else Square_Has (-1, 1, 1) then
            return True;
         end if;
      else
         if Square_Has (1, -1, 1) or else Square_Has (1, 1, 1) then
            return True;
         end if;
      end if;

      --  Knights (code 4).
      if Square_Has (1, 2, 4) or else Square_Has (1, -2, 4)
        or else Square_Has (-1, 2, 4) or else Square_Has (-1, -2, 4)
        or else Square_Has (2, 1, 4) or else Square_Has (2, -1, 4)
        or else Square_Has (-2, 1, 4) or else Square_Has (-2, -1, 4)
      then
         return True;
      end if;

      --  King (code 999) - adjacent squares only.
      for Dr in -1 .. 1 loop
         for Df in -1 .. 1 loop
            if (Dr /= 0 or else Df /= 0) and then Square_Has (Dr, Df, 999) then
               return True;
            end if;
         end loop;
      end loop;

      --  Sliding pieces: bishops/queens on diagonals, rooks/queens on
      --  files and ranks. Wanted2 = 20 (queen) is folded into each ray.
      if Ray_Hits (1, 1, 3, 20) or else Ray_Hits (1, -1, 3, 20)
        or else Ray_Hits (-1, 1, 3, 20) or else Ray_Hits (-1, -1, 3, 20)
      then
         return True;
      end if;

      if Ray_Hits (1, 0, 7, 20) or else Ray_Hits (-1, 0, 7, 20)
        or else Ray_Hits (0, 1, 7, 20) or else Ray_Hits (0, -1, 7, 20)
      then
         return True;
      end if;

      return False;
   end Is_Square_Attacked;

   function Find_King (White_King : Boolean) return Integer is
      Wanted : constant Integer := (if White_King then 999 else -999);
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = Wanted then
            return Sq;
         end if;
      end loop;
      return 0;
   end Find_King;

   function Is_In_Check (White_King : Boolean) return Boolean is
      King_Sq : constant Integer := Find_King (White_King);
   begin
      if King_Sq = 0 then
         return False;
      end if;
      return Is_Square_Attacked (King_Sq, By_White => not White_King);
   end Is_In_Check;

   function Home_Rook_Square (White : Boolean; Kingside : Boolean) return Integer is
   begin
      if White then
         return (if Kingside then 8 else 1);
      else
         return (if Kingside then 64 else 57);
      end if;
   end Home_Rook_Square;

   function Is_Castle_Legal (White_To_Move : Boolean; Kingside : Boolean) return Boolean is
      Rook_Value : constant Integer := (if White_To_Move then 7 else -7);
      King_Home  : constant Integer := (if White_To_Move then 5 else 61);
      Rook_Sq    : constant Integer := Home_Rook_Square (White_To_Move, Kingside);
      Enemy      : constant Boolean := not White_To_Move;
   begin
      --  Rights.
      if White_To_Move then
         if Kingside and then not White_Castling_K then return False; end if;
         if not Kingside and then not White_Castling_Q then return False; end if;
      else
         if Kingside and then not Black_Castling_K then return False; end if;
         if not Kingside and then not Black_Castling_Q then return False; end if;
      end if;

      --  King and rook must genuinely still be on their home squares.
      --  Castling rights normally imply the king never moved, but a
      --  hand-written FEN can lie (rights "KQkq" with a displaced
      --  king); without this guard the castle would be offered from a
      --  square the king does not occupy, corrupting the board.
      if Pvalidade.Tabuleiro (King_Home) /= (if White_To_Move then 999 else -999) then
         return False;
      end if;
      if Pvalidade.Tabuleiro (Rook_Sq) /= Rook_Value then
         return False;
      end if;

      --  King must not currently be in check.
      if Is_In_Check (White_To_Move) then
         return False;
      end if;

      if Kingside then
         declare
            F1 : constant Integer := King_Home + 1; -- f-file
            G1 : constant Integer := King_Home + 2; -- g-file
         begin
            if Pvalidade.Tabuleiro (F1) /= 0 or else Pvalidade.Tabuleiro (G1) /= 0 then
               return False;
            end if;
            if Is_Square_Attacked (F1, By_White => Enemy)
              or else Is_Square_Attacked (G1, By_White => Enemy)
            then
               return False;
            end if;
         end;
      else
         declare
            D1 : constant Integer := King_Home - 1; -- d-file
            C1 : constant Integer := King_Home - 2; -- c-file
            B1 : constant Integer := King_Home - 3; -- b-file (must be empty, need not be safe)
         begin
            if Pvalidade.Tabuleiro (D1) /= 0 or else Pvalidade.Tabuleiro (C1) /= 0
              or else Pvalidade.Tabuleiro (B1) /= 0
            then
               return False;
            end if;
            if Is_Square_Attacked (D1, By_White => Enemy)
              or else Is_Square_Attacked (C1, By_White => Enemy)
            then
               return False;
            end if;
         end;
      end if;

      return True;
   end Is_Castle_Legal;

   procedure Apply_Castle_Rook_Move (White_To_Move : Boolean; Kingside : Boolean) is
      Rook_Value : constant Integer := (if White_To_Move then 7 else -7);
      Rook_From  : constant Integer := Home_Rook_Square (White_To_Move, Kingside);
      King_Home  : constant Integer := (if White_To_Move then 5 else 61);
      Rook_To    : constant Integer :=
        (if Kingside then King_Home + 1 else King_Home - 1);
   begin
      Pvalidade.Tabuleiro (Rook_From) := 0;
      Pvalidade.Tabuleiro (Rook_To) := Rook_Value;
   end Apply_Castle_Rook_Move;

   procedure Update_Rights_After_Move
     (From_Sq, To_Sq : Integer; Moved_Piece : Integer) is
   begin
      --  A king move forfeits both castling rights for that side.
      if Moved_Piece = 999 then
         White_Castling_K := False;
         White_Castling_Q := False;
      elsif Moved_Piece = -999 then
         Black_Castling_K := False;
         Black_Castling_Q := False;
      end if;

      --  A rook leaving (or being captured on) its home square forfeits
      --  that specific right, for either side.
      if From_Sq = Home_Rook_Square (True, True) or else To_Sq = Home_Rook_Square (True, True) then
         White_Castling_K := False;
      end if;
      if From_Sq = Home_Rook_Square (True, False) or else To_Sq = Home_Rook_Square (True, False) then
         White_Castling_Q := False;
      end if;
      if From_Sq = Home_Rook_Square (False, True) or else To_Sq = Home_Rook_Square (False, True) then
         Black_Castling_K := False;
      end if;
      if From_Sq = Home_Rook_Square (False, False) or else To_Sq = Home_Rook_Square (False, False) then
         Black_Castling_Q := False;
      end if;
   end Update_Rights_After_Move;

end Move_Validation;
