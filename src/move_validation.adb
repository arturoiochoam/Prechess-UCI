-------------------------------------------------------------------------------
--  PRECHESS UCI - FIDE RULES & DERIVED LEGALITY IMPLEMENTATION
--
--  Module:        Move_Validation (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (FIDE Rules & Legality Layer)
--  Date:          2026
-------------------------------------------------------------------------------

with Pvalidade;

package body Move_Validation is

   ----------------------------------------------------------------------------
   --  STATE MANAGEMENT
   ----------------------------------------------------------------------------
   procedure Reset_State is
   begin
      White_Castling_K := True;
      White_Castling_Q := True;
      Black_Castling_K := True;
      Black_Castling_Q := True;
      En_Passant_Sq := 0;
   end Reset_State;

   procedure Set_Castling_Rights
     (White_K, White_Q, Black_K, Black_Q : Boolean)
   is
   begin
      White_Castling_K := White_K;
      White_Castling_Q := White_Q;
      Black_Castling_K := Black_K;
      Black_Castling_Q := Black_Q;
   end Set_Castling_Rights;

   function Castling_Rights_Bits return Integer is
      Bits : Integer := 0;
   begin
      if White_Castling_K then
         Bits := Bits + 1;
      end if;
      if White_Castling_Q then
         Bits := Bits + 2;
      end if;
      if Black_Castling_K then
         Bits := Bits + 4;
      end if;
      if Black_Castling_Q then
         Bits := Bits + 8;
      end if;
      return Bits;
   end Castling_Rights_Bits;

   ----------------------------------------------------------------------------
   --  COORDINATE MAPPING IMPLEMENTATIONS
   ----------------------------------------------------------------------------
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

   ----------------------------------------------------------------------------
   --  PRECALCULATED RAY OBSTRUCTION MATRIX IMPLEMENTATION
   ----------------------------------------------------------------------------
   function Square_Bitmask (Sq : Integer) return Interfaces.Unsigned_64 is
   begin
      return Shift_Left (1, Sq - 1);
   end Square_Bitmask;

   function Occupied_Bitmask return Interfaces.Unsigned_64 is
      Occupied : Unsigned_64 := 0;
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) /= 0 then
            Occupied := Occupied or Shift_Left (1, Sq - 1);
         end if;
      end loop;
      return Occupied;
   end Occupied_Bitmask;

   function Is_Ray_Clear (From_Sq, To_Sq : Integer) return Boolean is
      Intervening : constant Unsigned_64 := Ray_Between (From_Sq, To_Sq);
   begin
      if Intervening = 0 then
         return True;
      end if;
      return (Intervening and Occupied_Bitmask) = 0;
   end Is_Ray_Clear;

   procedure Init_Ray_Tables is
   begin
      for Sq1 in 1 .. 64 loop
         for Sq2 in 1 .. 64 loop
            if Sq1 = Sq2 then
               Ray_Between (Sq1, Sq2) := 0;
            else
               declare
                  R1 : constant Integer := Rank_Of (Sq1);
                  F1 : constant Integer := File_Of (Sq1);
                  R2 : constant Integer := Rank_Of (Sq2);
                  F2 : constant Integer := File_Of (Sq2);
                  Dr : constant Integer := R2 - R1;
                  Df : constant Integer := F2 - F1;
               begin
                  if Dr = 0 or else Df = 0 or else abs Dr = abs Df then
                     declare
                        Step_R : constant Integer :=
                          (if Dr > 0 then 1 elsif Dr < 0 then -1 else 0);
                        Step_F : constant Integer :=
                          (if Df > 0 then 1 elsif Df < 0 then -1 else 0);
                        Mask   : Unsigned_64 := 0;
                        Curr_R : Integer := R1 + Step_R;
                        Curr_F : Integer := F1 + Step_F;
                     begin
                        while Curr_R /= R2 or else Curr_F /= F2 loop
                           Mask := Mask or Shift_Left (1, Square_Of (Curr_R, Curr_F) - 1);
                           Curr_R := Curr_R + Step_R;
                           Curr_F := Curr_F + Step_F;
                        end loop;
                        Ray_Between (Sq1, Sq2) := Mask;
                     end;
                  else
                     Ray_Between (Sq1, Sq2) := 0;
                  end if;
               end;
            end if;
         end loop;
      end loop;
   end Init_Ray_Tables;

   ----------------------------------------------------------------------------
   --  SQUARE ATTACK ENGINE
   ----------------------------------------------------------------------------
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

      --  Ray-cast along direction vector (Dr, Df) until first obstacle
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
               return False; -- Blocked by another piece
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
      --  1. Pawn Attacks: diagonal capture steps from attacker's perspective
      if By_White then
         -- White pawns attack upwards (Rank R-1 -> R)
         if R > 1 then
            if F > 1 and then Pvalidade.Tabuleiro (Square_Of (R - 1, F - 1)) = 1 then
               return True;
            end if;
            if F < 8 and then Pvalidade.Tabuleiro (Square_Of (R - 1, F + 1)) = 1 then
               return True;
            end if;
         end if;
      else
         -- Black pawns attack downwards (Rank R+1 -> R)
         if R < 8 then
            if F > 1 and then Pvalidade.Tabuleiro (Square_Of (R + 1, F - 1)) = -1 then
               return True;
            end if;
            if F < 8 and then Pvalidade.Tabuleiro (Square_Of (R + 1, F + 1)) = -1 then
               return True;
            end if;
         end if;
      end if;

      --  2. Knight Attacks: 8 leap destinations (Piece code 4)
      if Square_Has (-2, -1, 4) or else Square_Has (-2, 1, 4)
        or else Square_Has (-1, -2, 4) or else Square_Has (-1, 2, 4)
        or else Square_Has (1, -2, 4) or else Square_Has (1, 2, 4)
        or else Square_Has (2, -1, 4) or else Square_Has (2, 1, 4)
      then
         return True;
      end if;

      --  3. King Attacks: 8 adjacent single-step squares (Piece code 999)
      for Dr in -1 .. 1 loop
         for Df in -1 .. 1 loop
            if (Dr /= 0 or else Df /= 0) and then Square_Has (Dr, Df, 999) then
               return True;
            end if;
         end loop;
      end loop;

      --  4. Orthogonal Sliders: Rooks (7) and Queens (20)
      if Ray_Hits (1, 0, 7, 20)
        or else Ray_Hits (-1, 0, 7, 20)
        or else Ray_Hits (0, 1, 7, 20)
        or else Ray_Hits (0, -1, 7, 20)
      then
         return True;
      end if;

      --  5. Diagonal Sliders: Bishops (3) and Queens (20)
      if Ray_Hits (1, 1, 3, 20)
        or else Ray_Hits (1, -1, 3, 20)
        or else Ray_Hits (-1, 1, 3, 20)
        or else Ray_Hits (-1, -1, 3, 20)
      then
         return True;
      end if;

      return False;
   end Is_Square_Attacked;

   ----------------------------------------------------------------------------
   --  KING IDENTIFICATION & CHECK VERIFICATION
   ----------------------------------------------------------------------------
   function Find_King (White_King : Boolean) return Integer is
      Target : constant Integer := (if White_King then 999 else -999);
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = Target then
            return Sq;
         end if;
      end loop;
      return 0;
   end Find_King;

   function Is_In_Check (White_King : Boolean) return Boolean is
      Ksq : constant Integer := Find_King (White_King);
   begin
      if Ksq = 0 then
         return False;
      end if;
      return Is_Square_Attacked (Ksq, By_White => not White_King);
   end Is_In_Check;

   ----------------------------------------------------------------------------
   --  CASTLING SQUARES & VALIDATION
   ----------------------------------------------------------------------------
   function Home_Rook_Square (White : Boolean; Kingside : Boolean) return Integer is
      Rank : constant Integer := (if White then 1 else 8);
      File : constant Integer := (if Kingside then 8 else 1);
   begin
      return Square_Of (Rank, File);
   end Home_Rook_Square;

   function Is_Castle_Legal (White_To_Move : Boolean; Kingside : Boolean) return Boolean is
      Rank     : constant Integer := (if White_To_Move then 1 else 8);
      King_Sq  : constant Integer := Square_Of (Rank, 5); -- e1 / e8
      Rook_Sq  : constant Integer := Home_Rook_Square (White_To_Move, Kingside);
      King_Val : constant Integer := (if White_To_Move then 999 else -999);
      Rook_Val : constant Integer := (if White_To_Move then 7 else -7);
      Opp      : constant Boolean := not White_To_Move;
   begin
      --  1) Verify castling rights bitmask
      if White_To_Move then
         if Kingside and then not White_Castling_K then
            return False;
         end if;
         if (not Kingside) and then not White_Castling_Q then
            return False;
         end if;
      else
         if Kingside and then not Black_Castling_K then
            return False;
         end if;
         if (not Kingside) and then not Black_Castling_Q then
            return False;
         end if;
      end if;

      --  2) Verify King and Rook presence on initial home squares
      if Pvalidade.Tabuleiro (King_Sq) /= King_Val then
         return False;
      end if;
      if Pvalidade.Tabuleiro (Rook_Sq) /= Rook_Val then
         return False;
      end if;

      --  3) Transit squares must be vacant, and King must not be in check,
      --     nor pass through or land on an attacked square.
      if Kingside then
         declare
            F1 : constant Integer := Square_Of (Rank, 6); -- f1/f8
            G1 : constant Integer := Square_Of (Rank, 7); -- g1/g8
         begin
            if Pvalidade.Tabuleiro (F1) /= 0 or else Pvalidade.Tabuleiro (G1) /= 0 then
               return False;
            end if;
            if Is_Square_Attacked (King_Sq, By_White => Opp)
              or else Is_Square_Attacked (F1, By_White => Opp)
              or else Is_Square_Attacked (G1, By_White => Opp)
            then
               return False;
            end if;
         end;
      else
         declare
            D1 : constant Integer := Square_Of (Rank, 4); -- d1/d8
            C1 : constant Integer := Square_Of (Rank, 3); -- c1/c8
            B1 : constant Integer := Square_Of (Rank, 2); -- b1/b8 (must be empty, need not be safe)
         begin
            if Pvalidade.Tabuleiro (D1) /= 0
              or else Pvalidade.Tabuleiro (C1) /= 0
              or else Pvalidade.Tabuleiro (B1) /= 0
            then
               return False;
            end if;
            if Is_Square_Attacked (King_Sq, By_White => Opp)
              or else Is_Square_Attacked (D1, By_White => Opp)
              or else Is_Square_Attacked (C1, By_White => Opp)
            then
               return False;
            end if;
         end;
      end if;

      return True;
   end Is_Castle_Legal;

   procedure Apply_Castle_Rook_Move (White_To_Move : Boolean; Kingside : Boolean) is
      Rank      : constant Integer := (if White_To_Move then 1 else 8);
      Rook_From : constant Integer := Home_Rook_Square (White_To_Move, Kingside);
      Rook_To   : constant Integer := (if Kingside then Square_Of (Rank, 6) else Square_Of (Rank, 4));
      Rook_Val  : constant Integer := (if White_To_Move then 7 else -7);
   begin
      Pvalidade.Tabuleiro (Rook_From) := 0;
      Pvalidade.Tabuleiro (Rook_To)   := Rook_Val;
   end Apply_Castle_Rook_Move;

   procedure Update_Rights_After_Move
     (From_Sq, To_Sq : Integer; Moved_Piece : Integer)
   is
      WR_K : constant Integer := Home_Rook_Square (True,  True);
      WR_Q : constant Integer := Home_Rook_Square (True,  False);
      BR_K : constant Integer := Home_Rook_Square (False, True);
      BR_Q : constant Integer := Home_Rook_Square (False, False);
   begin
      --  King moves forfeit both castling rights for that color
      if Moved_Piece = 999 or else From_Sq = Square_Of (1, 5) then
         White_Castling_K := False;
         White_Castling_Q := False;
      elsif Moved_Piece = -999 or else From_Sq = Square_Of (8, 5) then
         Black_Castling_K := False;
         Black_Castling_Q := False;
      end if;

      --  Rook moves or captures on home squares forfeit that specific right
      if From_Sq = WR_K or else To_Sq = WR_K then
         White_Castling_K := False;
      end if;
      if From_Sq = WR_Q or else To_Sq = WR_Q then
         White_Castling_Q := False;
      end if;
      if From_Sq = BR_K or else To_Sq = BR_K then
         Black_Castling_K := False;
      end if;
      if From_Sq = BR_Q or else To_Sq = BR_Q then
         Black_Castling_Q := False;
      end if;
   end Update_Rights_After_Move;

begin
   Init_Ray_Tables;
end Move_Validation;
