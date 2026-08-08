with Pvalidade;        use Pvalidade;
with Move_Validation;
with Ada.Text_IO;
with Ada.Strings;      use Ada.Strings;
with Ada.Strings.Fixed;

package body Move_Gen is

   Max_Moves : constant := 256;

   type Move_Rec is record
      From  : Integer;
      To    : Integer;
      Promo : Integer;   -- 0 = none, else 20(Q)/7(R)/4(N)/3(B) absolute code
   end record;

   type Move_Array is array (1 .. Max_Moves) of Move_Rec;

   type Move_List is record
      V : Move_Array;
      N : Natural := 0;
   end record;

   procedure Append (L : in out Move_List; F, T, P : Integer) is
   begin
      if L.N < Max_Moves then
         L.N := L.N + 1;
         L.V (L.N) := (From => F, To => T, Promo => P);
      end if;
   end Append;

   function Own (Piece : Integer; White : Boolean) return Boolean is
     (Piece /= 0
       and then ((White and then Piece > 0)
                  or else (not White and then Piece < 0)));

   --  Pseudo-legal generation for the side to move. Validade supplies correct
   --  geometry for normal/capture moves (pawn push/double/diagonal, knight,
   --  sliders with blockers, king); it CANNOT see castling, EP, or promotion,
   --  so those are added here.
   procedure Gen_Pseudo (White : Boolean; L : in out Move_List) is
      use Move_Validation;
      Piece : Integer;
      K_From : constant Integer := (if White then 5 else 61);
   begin
      for A in 1 .. 64 loop
         Piece := Tabuleiro (A);
         if Own (Piece, White) then
            for B in 1 .. 64 loop
               if Validade (A, B) then
                  if abs Piece = 1
                    and then (Rank_Of (B) = 1 or else Rank_Of (B) = 8)
                  then
                     Append (L, A, B, 20);
                     Append (L, A, B, 7);
                     Append (L, A, B, 4);
                     Append (L, A, B, 3);
                  else
                     Append (L, A, B, 0);
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      if Is_Castle_Legal (White, Kingside => True) then
         Append (L, K_From, (if White then 7 else 63), 0);
      end if;
      if Is_Castle_Legal (White, Kingside => False) then
         Append (L, K_From, (if White then 3 else 59), 0);
      end if;

      --  En passant: a diagonal pawn capture to an empty square.
      declare
         EP  : constant Integer := En_Passant_Sq;
         EPr : Integer := 0;
         EPf : Integer := 0;
         procedure Try_EP (Cand : Integer) is
            Rq : constant Integer := (if White then EPr - 1 else EPr + 1);
         begin
            if Cand in 1 .. 64
              and then Rank_Of (Cand) = Rq
              and then abs (File_Of (Cand) - EPf) = 1
              and then Tabuleiro (Cand) = (if White then 1 else -1)
            then
               Append (L, Cand, EP, 0);
            end if;
         end Try_EP;
      begin
         if EP /= 0 then
            EPr := Rank_Of (EP);
            EPf := File_Of (EP);
            if EPr = (if White then 6 else 3)
              and then Tabuleiro (EP) = 0
              and then Tabuleiro ((if White then EP - 8 else EP + 8)) =
                         (if White then -1 else 1)
            then
               if White then
                  Try_EP (EP - 9);
                  Try_EP (EP - 7);
               else
                  Try_EP (EP + 9);
                  Try_EP (EP + 7);
               end if;
            end if;
         end if;
      end;
   end Gen_Pseudo;

   --  Copy-make state: full board + four castling rights + EP square.
   type Board_Copy is array (1 .. 64) of Integer;
   type Saved is record
      Bd             : Board_Copy;
      WK, WQ, BK, BQ : Boolean;
      EP             : Integer;
   end record;

   procedure Save (S : out Saved) is
      use Move_Validation;
   begin
      for I in 1 .. 64 loop S.Bd (I) := Tabuleiro (I); end loop;
      S.WK := White_Castling_K;
      S.WQ := White_Castling_Q;
      S.BK := Black_Castling_K;
      S.BQ := Black_Castling_Q;
      S.EP := En_Passant_Sq;
   end Save;

   procedure Restore (S : Saved) is
      use Move_Validation;
   begin
      for I in 1 .. 64 loop Tabuleiro (I) := S.Bd (I); end loop;
      White_Castling_K := S.WK;
      White_Castling_Q := S.WQ;
      Black_Castling_K := S.BK;
      Black_Castling_Q := S.BQ;
      En_Passant_Sq    := S.EP;
   end Restore;

   procedure Make (F, T, Promo : Integer; White : Boolean) is
      use Move_Validation;
      Piece     : constant Integer := Tabuleiro (F);
      Abs_Piece : constant Integer := abs Piece;
      Sign      : constant Integer := (if White then 1 else -1);
      OldEP     : constant Integer := En_Passant_Sq;
   begin
      --  En passant capture: own pawn diagonally to the empty EP square.
      --  The file-diff guard distinguishes it from a straight push to the
      --  same rank-3/6 square.
      if Abs_Piece = 1 and then OldEP /= 0 and then T = OldEP
        and then Tabuleiro (T) = 0
        and then abs (File_Of (T) - File_Of (F)) = 1
      then
         Tabuleiro ((if White then T - 8 else T + 8)) := 0;
      end if;

      if Abs_Piece = 1 and then Promo /= 0
        and then (Rank_Of (T) = 1 or else Rank_Of (T) = 8)
      then
         Tabuleiro (T) := Sign * Promo;
      else
         Tabuleiro (T) := Piece;
      end if;
      Tabuleiro (F) := 0;

      if Abs_Piece = 999
        and then abs (File_Of (T) - File_Of (F)) = 2
      then
         Apply_Castle_Rook_Move
           (White_To_Move => White,
            Kingside      => File_Of (T) > File_Of (F));
      end if;

      Update_Rights_After_Move (F, T, Piece);

      if Abs_Piece = 1 and then abs (T - F) = 16 then
         En_Passant_Sq := (F + T) / 2;
      else
         En_Passant_Sq := 0;
      end if;
   end Make;

   function Perft (Depth : Natural; White_To_Move : Boolean)
      return Long_Long_Integer
   is
      L     : Move_List;
      S     : Saved;
      Total : Long_Long_Integer := 0;
   begin
      if Depth = 0 then
         return 1;
      end if;
      Gen_Pseudo (White_To_Move, L);
      for I in 1 .. L.N loop
         Save (S);
         Make (L.V (I).From, L.V (I).To, L.V (I).Promo, White_To_Move);
         if not Move_Validation.Is_In_Check (White_To_Move) then
            Total := Total + Perft (Depth - 1, not White_To_Move);
         end if;
         Restore (S);
      end loop;
      return Total;
   end Perft;

   function Img (N : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (N'Img, Both));

   function Sq_Name (Sq : Integer) return String is
     (Character'Val (Character'Pos ('a') + Move_Validation.File_Of (Sq) - 1)
      & Character'Val (Character'Pos ('0') + Move_Validation.Rank_Of (Sq)));

   function Promo_Letter (P : Integer) return String is
     (if P = 20 then "q"
      elsif P = 7 then "r"
      elsif P = 4 then "n"
      elsif P = 3 then "b"
      else "");

   procedure Perft_Divide (Depth : Positive; White_To_Move : Boolean) is
      L     : Move_List;
      S     : Saved;
      Total : Long_Long_Integer := 0;
      Sub   : Long_Long_Integer;
   begin
      Gen_Pseudo (White_To_Move, L);
      for I in 1 .. L.N loop
         Save (S);
         Make (L.V (I).From, L.V (I).To, L.V (I).Promo, White_To_Move);
         if not Move_Validation.Is_In_Check (White_To_Move) then
            if Depth = 1 then
               Sub := 1;
            else
               Sub := Perft (Depth - 1, not White_To_Move);
            end if;
            Total := Total + Sub;
            Ada.Text_IO.Put_Line
              (Sq_Name (L.V (I).From) & Sq_Name (L.V (I).To)
               & Promo_Letter (L.V (I).Promo) & " " & Img (Sub));
         end if;
         Restore (S);
      end loop;
      Ada.Text_IO.Put_Line
        ("perft " & Ada.Strings.Fixed.Trim (Depth'Img, Both) & " " & Img (Total));
   end Perft_Divide;

end Move_Gen;
