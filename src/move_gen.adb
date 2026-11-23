-------------------------------------------------------------------------------
--  PRECHESS UCI - LEGAL MOVE GENERATOR & PERFT VERIFICATION ENGINE
--
--  Module:        Move_Gen (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Perft & Legal Move Engine)
--  Date:          2026
-------------------------------------------------------------------------------

with Pvalidade;        use Pvalidade;
with Move_Validation;
with Ada.Text_IO;
with Ada.Strings;      use Ada.Strings;
with Ada.Strings.Fixed;

package body Move_Gen is

   function Move_To_UCI (M : Move_Rec) return String is
   begin
      if M.From not in 1 .. 64 or else M.To not in 1 .. 64 then
         return "0000";
      end if;
      declare
         F_File : constant Character :=
           Character'Val (Character'Pos ('a') + Move_Validation.File_Of (M.From) - 1);
         F_Rank : constant Character :=
           Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (M.From) - 1);
         T_File : constant Character :=
           Character'Val (Character'Pos ('a') + Move_Validation.File_Of (M.To) - 1);
         T_Rank : constant Character :=
           Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (M.To) - 1);
         P : constant String :=
           (case M.Promo is
               when 20 => "q", when 7 => "r", when 3 => "b", when 4 => "n",
               when others => "");
      begin
         return F_File & F_Rank & T_File & T_Rank & P;
      end;
   end Move_To_UCI;

   ----------------------------------------------------------------------------
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

   ----------------------------------------------------------------------------
   --  PSEUDO-LEGAL MOVE GENERATION
   ----------------------------------------------------------------------------
   --  Scans the mailbox board to generate all pseudo-legal moves for `White`.
   --  Augments standard moves with Castling, En-Passant, and Promotions.
   ----------------------------------------------------------------------------
   procedure Gen_Pseudo (White : Boolean; L : in out Move_List) is
      use Move_Validation;
      Piece  : Integer;
      K_From : constant Integer := (if White then 5 else 61);
   begin
      --  1. Standard sliding, stepping, and leaping moves
      for A in 1 .. 64 loop
         Piece := Tabuleiro (A);
         if Own (Piece, White) then
            for B in 1 .. 64 loop
               if Validade (A, B) then
                  if abs Piece = 1
                    and then (Rank_Of (B) = 1 or else Rank_Of (B) = 8)
                  then
                     -- Generate 4 promotion piece types
                     Append (L, A, B, 20); -- Queen
                     Append (L, A, B, 7);  -- Rook
                     Append (L, A, B, 4);  -- Knight
                     Append (L, A, B, 3);  -- Bishop
                  else
                     Append (L, A, B, 0);
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      --  2. FIDE Castling (Kingside and Queenside)
      if Is_Castle_Legal (White, Kingside => True) then
         Append (L, K_From, (if White then 7 else 63), 0);
      end if;
      if Is_Castle_Legal (White, Kingside => False) then
         Append (L, K_From, (if White then 3 else 59), 0);
      end if;

      --  3. En-Passant Pawn Captures
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

   ----------------------------------------------------------------------------
   --  COPY-MAKE RESTORATION STACK RECORD
   ----------------------------------------------------------------------------
   subtype Board_Copy is Pvalidade.Board_Array;
   type Saved is record
      Bd             : Board_Copy;
      WK, WQ, BK, BQ : Boolean;
      EP             : Integer;
   end record;

   procedure Save (S : out Saved) is
      use Move_Validation;
   begin
      S.Bd := Tabuleiro;   --  whole-array (block) copy
      S.WK := White_Castling_K;
      S.WQ := White_Castling_Q;
      S.BK := Black_Castling_K;
      S.BQ := Black_Castling_Q;
      S.EP := En_Passant_Sq;
   end Save;

   procedure Restore (S : Saved) is
      use Move_Validation;
   begin
      Tabuleiro := S.Bd;   --  whole-array (block) copy
      White_Castling_K := S.WK;
      White_Castling_Q := S.WQ;
      Black_Castling_K := S.BK;
      Black_Castling_Q := S.BQ;
      En_Passant_Sq    := S.EP;
   end Restore;

   ----------------------------------------------------------------------------
   --  MOVE EXECUTION (MAKE)
   ----------------------------------------------------------------------------
   procedure Make (F, T, Promo : Integer; White : Boolean) is
      use Move_Validation;
      Piece     : constant Integer := Tabuleiro (F);
      Abs_Piece : constant Integer := abs Piece;
      Sign      : constant Integer := (if White then 1 else -1);
      OldEP     : constant Integer := En_Passant_Sq;
   begin
      -- Handle En-Passant capture removal
      if Abs_Piece = 1 and then OldEP /= 0 and then T = OldEP
        and then Tabuleiro (T) = 0
        and then abs (File_Of (T) - File_Of (F)) = 1
      then
         Tabuleiro ((if White then T - 8 else T + 8)) := 0;
      end if;

      -- Handle Promotion replacement
      if Abs_Piece = 1 and then Promo /= 0
        and then (Rank_Of (T) = 1 or else Rank_Of (T) = 8)
      then
         Tabuleiro (T) := Sign * Promo;
      else
         Tabuleiro (T) := Piece;
      end if;
      Tabuleiro (F) := 0;

      -- Handle King Castling Rook jump
      if Abs_Piece = 999
        and then abs (File_Of (T) - File_Of (F)) = 2
      then
         Apply_Castle_Rook_Move
           (White_To_Move => White,
            Kingside      => File_Of (T) > File_Of (F));
      end if;

      -- Update Castling Rights
      Update_Rights_After_Move (F, T, Piece);

      -- Update En-Passant Target Square
      if Abs_Piece = 1 and then abs (T - F) = 16 then
         En_Passant_Sq := (F + T) / 2;
      else
         En_Passant_Sq := 0;
      end if;
   end Make;

   procedure Make_Move (F, T, Promo : Integer; White : Boolean) is
   begin
      Make (F, T, Promo, White);
   end Make_Move;

   ----------------------------------------------------------------------------
   --  LEGAL MOVE GENERATION
   ----------------------------------------------------------------------------
   procedure Generate_Legal_Moves
     (White_To_Move : Boolean;
      List          : out Move_List)
   is
      Pseudo : Move_List;
      S      : Saved;
   begin
      List.N := 0;
      Gen_Pseudo (White_To_Move, Pseudo);
      for I in 1 .. Pseudo.N loop
         Save (S);
         Make (Pseudo.V (I).From, Pseudo.V (I).To, Pseudo.V (I).Promo, White_To_Move);
         if not Move_Validation.Is_In_Check (White_To_Move) then
            Append (List, Pseudo.V (I).From, Pseudo.V (I).To, Pseudo.V (I).Promo);
         end if;
         Restore (S);
      end loop;
   end Generate_Legal_Moves;

   ----------------------------------------------------------------------------
   --  RECURSIVE PERFT ENGINE
   ----------------------------------------------------------------------------
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

   ----------------------------------------------------------------------------
   --  UCI STRING CONVERSION & DIVIDE FORMATTER
   ----------------------------------------------------------------------------
   function Img (N : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (N'Img, Both));

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
              (Move_To_UCI (L.V (I)) & " " & Img (Sub));
         end if;
         Restore (S);
      end loop;
      Ada.Text_IO.Put_Line
        ("perft " & Ada.Strings.Fixed.Trim (Depth'Img, Both) & " " & Img (Total));
   end Perft_Divide;

end Move_Gen;
