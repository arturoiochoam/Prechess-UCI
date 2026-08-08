with Ada.Strings.Fixed;
with Ada.Text_IO;
with Pvalidade;
with Move_Validation;
with BCH_Hash;
with TT_Table;
with Time_Management;

package body Search_Integration is

   ------------------------------------------------------------------
   --  Game history / draw rules
   ------------------------------------------------------------------

   procedure Reset_Game is
   begin
      History_Count := 0;
      Fifty_Move_Counter := 0;
      Move_Validation.Reset_State;
   end Reset_Game;

   procedure Push_State (H : Hash_Key; Half_Move : Integer) is
   begin
      Fifty_Move_Counter := Half_Move;
      if History_Count < History_Max then
         History_Count := History_Count + 1;
         History (History_Count) := H;
      else
         --  Very long game / deep analysis: drop the oldest entry and
         --  keep the trailing History_Max positions so threefold detection
         --  still works for recent repetitions.
         for I in 1 .. History_Max - 1 loop
            History (I) := History (I + 1);
         end loop;
         History (History_Max) := H;
      end if;
   end Push_State;

   function Is_Threefold_Repetition return Boolean is
      --  FIDE Article 9.2: a draw may be claimed when the same position
      --  (same piece placement, same side to move, same castling rights,
      --  same en-passant availability) has arisen AT LEAST THREE times,
      --  counting the current occurrence. History is the true game
      --  history -- Parse_FEN seeds the root and Make_Move_UCI pushes
      --  exactly one entry per move, while the legacy search never
      --  pushes -- so we count EVERY History entry equal to the current
      --  (last-pushed) hash, INCLUDING the current entry itself, and
      --  draw when the total reaches 3. Counting the current occurrence
      --  explicitly avoids the old "two priors" phrasing that read as
      --  "draw on the 2nd" and keeps the threshold literal: total >= 3.
      Total : Integer := 0;
      Current_Hash : Hash_Key;
   begin
      if History_Count = 0 then
         return False;
      end if;

      Current_Hash := History (History_Count);
      for I in 1 .. History_Count loop
         if History (I) = Current_Hash then
            Total := Total + 1;
            if Total >= 3 then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Is_Threefold_Repetition;

   function Is_Fifty_Move_Rule return Boolean is
   begin
      return Fifty_Move_Counter >= 100; -- 50 full moves = 100 half moves
   end Is_Fifty_Move_Rule;

   function Bishops_On_Both_Colors (For_White : Boolean) return Boolean is
      Seen_Color_0 : Boolean := False;
      Seen_Color_1 : Boolean := False;
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = (if For_White then 3 else -3) then
            if (Move_Validation.Rank_Of (Sq) + Move_Validation.File_Of (Sq)) mod 2 = 0 then
               Seen_Color_0 := True;
            else
               Seen_Color_1 := True;
            end if;
         end if;
      end loop;
      return Seen_Color_0 and then Seen_Color_1;
   end Bishops_On_Both_Colors;

   function Has_Legal_En_Passant_Capture (White_To_Move : Boolean; Ep : Integer)
      return Boolean
   is
      Pawn_Code   : constant Integer := (if White_To_Move then 1 else -1);
      Cap_Rank    : Integer;
      Cap_File    : Integer;
      Candidate   : Integer;
      Captured_Sq : Integer;
      Legal       : Boolean;
   begin
      if Ep = 0 then
         return False;
      end if;
      if Move_Validation.Rank_Of (Ep) /= (if White_To_Move then 6 else 3) then
         return False;
      end if;

      Cap_Rank := (if White_To_Move then Move_Validation.Rank_Of (Ep) - 1
                                  else Move_Validation.Rank_Of (Ep) + 1);
      if Cap_Rank not in 1 .. 8 then
         return False;
      end if;

      for D in -1 .. 1 loop
         if D /= 0 then
            Cap_File := Move_Validation.File_Of (Ep) + D;
            if Cap_File in 1 .. 8 then
               Candidate := Move_Validation.Square_Of (Cap_Rank, Cap_File);
               Captured_Sq := Move_Validation.Square_Of
                 (Cap_Rank, Move_Validation.File_Of (Ep));
               if Pvalidade.Tabuleiro (Candidate) = Pawn_Code
                 and then Pvalidade.Tabuleiro (Ep) = 0
                 and then Pvalidade.Tabuleiro (Captured_Sq) = -Pawn_Code
               then
                  Pvalidade.Tabuleiro (Ep) := Pawn_Code;
                  Pvalidade.Tabuleiro (Candidate) := 0;
                  Pvalidade.Tabuleiro (Captured_Sq) := 0;
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Pvalidade.Tabuleiro (Ep) := 0;
                  Pvalidade.Tabuleiro (Candidate) := Pawn_Code;
                  Pvalidade.Tabuleiro (Captured_Sq) := -Pawn_Code;
                  if Legal then
                     return True;
                  end if;
               end if;
            end if;
         end if;
      end loop;
      return False;
   end Has_Legal_En_Passant_Capture;

   function Hash_Ep_For_Repetition (White_To_Move : Boolean; Ep : Integer) return Integer is
   begin
      if Has_Legal_En_Passant_Capture (White_To_Move, Ep) then
         return Ep;
      end if;
      return 0;
   end Hash_Ep_For_Repetition;

   function Is_Insufficient_Material return Boolean is
      White_Pawns    : Integer := 0;
      Black_Pawns    : Integer := 0;
      White_Knights  : Integer := 0;
      White_Bishops  : Integer := 0;
      Black_Knights  : Integer := 0;
      Black_Bishops  : Integer := 0;
      Other_Pieces   : Integer := 0;
      --  Square color (0 or 1) of the last bishop seen per side; only
      --  consulted when that side has exactly one bishop, so "last
      --  seen" is exact. Needed because KB-KB is a dead position ONLY
      --  when both bishops travel the same square color: with
      --  opposite-colored bishops a legal helpmate exists (e.g. Black
      --  Ka8 blocked by its own dark-squared Bb8, White Kb6 and a
      --  light-squared bishop checking along b7-a8), so FIDE Article
      --  5.2.2 does not end the game there.
      White_Bishop_Color : Integer := 0;
      Black_Bishop_Color : Integer := 0;
   begin
      for I in 1 .. 64 loop
         case Pvalidade.Tabuleiro (I) is
            when 0 => null;
            when 1 => White_Pawns := White_Pawns + 1;
            when -1 => Black_Pawns := Black_Pawns + 1;
            when 4 => White_Knights := White_Knights + 1;
            when -4 => Black_Knights := Black_Knights + 1;
            when 3 =>
               White_Bishops := White_Bishops + 1;
               White_Bishop_Color :=
                 (Move_Validation.Rank_Of (I) + Move_Validation.File_Of (I)) mod 2;
            when -3 =>
               Black_Bishops := Black_Bishops + 1;
               Black_Bishop_Color :=
                 (Move_Validation.Rank_Of (I) + Move_Validation.File_Of (I)) mod 2;
            when 999 | -999 => null; -- kings
            when others => Other_Pieces := Other_Pieces + 1;
         end case;
      end loop;

      --  Any pawn, rook or queen keeps the position alive (a pawn can
      --  promote, rooks/queens can mate). Pawns are tallied explicitly
      --  rather than rolled into Other_Pieces so the KNN-vs-K guard
      --  below can name them directly: KNN-vs-KP is a WINNABLE
      --  endgame (the pawn promotes), so it must NOT be reported as a
      --  dead position just because the major pieces happen to be two
      --  knights vs none.
      if Other_Pieces > 0 then return False; end if;
      if White_Pawns > 0 or else Black_Pawns > 0 then return False; end if;

      --  FIDE Article 5.2.2 dead positions covered here: K-K, KB-K,
      --  KN-K, and KB-KB with same-coloured bishops. KNN-K and KN-KN
      --  are NOT dead positions because mate is legally possible, even
      --  if not forceable, so they must not be reported as FIDE draws.
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 0 then
         return True;
      end if;
      if White_Knights = 0 and White_Bishops = 1 and Black_Knights = 0 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 1 then return True; end if;
      if White_Knights = 1 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 1 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 1 and Black_Knights = 0 and Black_Bishops = 1
        and White_Bishop_Color = Black_Bishop_Color then return True; end if;
      if White_Knights = 0 and White_Bishops = 2 and Black_Knights = 0 and Black_Bishops = 0
        and not Bishops_On_Both_Colors (True) then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 2
        and not Bishops_On_Both_Colors (False) then return True; end if;

      return False;
   end Is_Insufficient_Material;

   function Is_Draw return Boolean is
   begin
      return Is_Threefold_Repetition or else Is_Fifty_Move_Rule or else Is_Insufficient_Material;
   end Is_Draw;

   ------------------------------------------------------------------
   --  FEN parsing
   ------------------------------------------------------------------

   function Try_Parse_FEN (FEN : String; White_To_Move : in out Boolean) return Boolean is
      Rank       : Integer := 8;
      File       : Integer := 1;
      Idx        : Integer := FEN'First;
      Ch         : Character;
      Piece_Code : Integer;
      Half_Move  : Integer := 0;
      WK, WQ, BK, BQ : Boolean := False;
      EP_Sq      : Integer := 0;
      Local_White : Boolean := True;
      Board      : Pvalidade.Board_Array := (others => 0);

      function Piece_Of (C : Character) return Integer is
      begin
         case C is
            when 'P' => return 1;
            when 'N' => return 4;
            when 'B' => return 3;
            when 'R' => return 7;
            when 'Q' => return 20;
            when 'K' => return 999;
            when 'p' => return -1;
            when 'n' => return -4;
            when 'b' => return -3;
            when 'r' => return -7;
            when 'q' => return -20;
            when 'k' => return -999;
            when others => return 0;
         end case;
      end Piece_Of;

      procedure Skip_Field is
      begin
         while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
            Idx := Idx + 1;
         end loop;
      end Skip_Field;
   begin
      --  Field 1: piece placement. Reject malformed input instead of
      --  accepting surprising board states after the UCI front end has reset
      --  the current game.
      while Idx <= FEN'Last loop
         Ch := FEN (Idx);
         exit when Ch = ' ';
         if Ch = '/' then
            if File /= 9 or else Rank = 1 then
               return False;
            end if;
            Rank := Rank - 1;
            File := 1;
         elsif Ch >= '1' and then Ch <= '8' then
            File := File + Character'Pos (Ch) - Character'Pos ('0');
            if File > 9 then
               return False;
            end if;
         else
            Piece_Code := Piece_Of (Ch);
            if Piece_Code = 0 or else File > 8 then
               return False;
            end if;
            Board (Move_Validation.Square_Of (Rank, File)) := Piece_Code;
            File := File + 1;
         end if;
         Idx := Idx + 1;
      end loop;
      if Idx > FEN'Last or else Rank /= 1 or else File /= 9 then
         return False;
      end if;
      Idx := Idx + 1;

      --  Field 2: active color.
      if Idx > FEN'Last then
         return False;
      elsif FEN (Idx) = 'b' then
         Local_White := False;
      elsif FEN (Idx) = 'w' then
         Local_White := True;
      else
         return False;
      end if;
      Idx := Idx + 1;
      if Idx <= FEN'Last and then FEN (Idx) /= ' ' then
         return False;
      end if;
      Idx := Idx + 1;

      --  Field 3: castling availability.
      if Idx > FEN'Last then
         return False;
      elsif FEN (Idx) = '-' then
         Idx := Idx + 1;
      else
         while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
            case FEN (Idx) is
               when 'K' => if WK then return False; end if; WK := True;
               when 'Q' => if WQ then return False; end if; WQ := True;
               when 'k' => if BK then return False; end if; BK := True;
               when 'q' => if BQ then return False; end if; BQ := True;
               when others => return False;
            end case;
            Idx := Idx + 1;
         end loop;
      end if;
      if Idx > FEN'Last or else FEN (Idx) /= ' ' then
         return False;
      end if;
      Idx := Idx + 1;

      --  Field 4: en-passant target square.
      if Idx > FEN'Last then
         return False;
      elsif FEN (Idx) = '-' then
         Idx := Idx + 1;
      elsif Idx + 1 <= FEN'Last
        and then FEN (Idx) in 'a' .. 'h'
        and then FEN (Idx + 1) in '1' .. '8'
      then
         EP_Sq :=
           Move_Validation.Square_Of
             (Character'Pos (FEN (Idx + 1)) - Character'Pos ('0'),
              Character'Pos (FEN (Idx)) - Character'Pos ('a') + 1);
         Idx := Idx + 2;
      else
         return False;
      end if;
      if Idx > FEN'Last or else FEN (Idx) /= ' ' then
         return False;
      end if;
      Idx := Idx + 1;

      --  Field 5: halfmove clock.
      if Idx > FEN'Last or else FEN (Idx) not in '0' .. '9' then
         return False;
      end if;
      declare
         Start : constant Integer := Idx;
      begin
         Skip_Field;
         begin
            Half_Move := Integer'Value (FEN (Start .. Idx - 1));
         exception
            when others => return False;
         end;
      end;
      if Half_Move < 0 then
         return False;
      end if;
      if Idx > FEN'Last or else FEN (Idx) /= ' ' then
         return False;
      end if;
      Idx := Idx + 1;

      --  Field 6: full-move number must be syntactically valid, even though
      --  it does not affect engine behaviour.
      if Idx > FEN'Last or else FEN (Idx) not in '0' .. '9' then
         return False;
      end if;
      declare
         Start : constant Integer := Idx;
         Full_Move : Integer;
      begin
         Skip_Field;
         if Idx <= FEN'Last then
            return False;
         end if;
         begin
            Full_Move := Integer'Value (FEN (Start .. Idx - 1));
         exception
            when others => return False;
         end;
         if Full_Move <= 0 then
            return False;
         end if;
      end;

      Pvalidade.Tabuleiro := Board;
      History_Count := 0;
      Move_Validation.Reset_State;
      Move_Validation.Set_Castling_Rights (WK, WQ, BK, BQ);
      Move_Validation.En_Passant_Sq := EP_Sq;
      Push_State
        (H => BCH_Hash.Compute_Hash
               (White_To_Move   => Local_White,
                Ep_Square       => Hash_Ep_For_Repetition
                                     (Local_White, EP_Sq),
                Castling_Rights => Move_Validation.Castling_Rights_Bits),
         Half_Move => Half_Move);
      White_To_Move := Local_White;
      return True;
   end Try_Parse_FEN;

   procedure Parse_FEN (FEN : String; White_To_Move : out Boolean) is
      Parsed : Boolean;
   begin
      White_To_Move := True;
      Parsed := Try_Parse_FEN (FEN, White_To_Move);
      if not Parsed then
         White_To_Move := True;
      end if;
   end Parse_FEN;

   ------------------------------------------------------------------
   --  Move application
   ------------------------------------------------------------------

   procedure Make_Move_UCI
     (Move_Str               : String;
      Expected_White_To_Move : Boolean;
      Applied                : out Boolean)
   is
      --  Each component guards its own indexing: a token shorter than 4
      --  (malformed UCI input, or an empty slice produced by a double
      --  space in "position ... moves") yields 0, which the range guard
      --  below rejects, instead of raising Constraint_Error during
      --  elaboration of these constants -- before that guard could run.
      F_File : constant Integer := (if Move_Str'Length >= 1
                                     then Character'Pos (Move_Str (Move_Str'First)) - Character'Pos ('a') + 1
                                     else 0);
      F_Rank : constant Integer := (if Move_Str'Length >= 2
                                     then Character'Pos (Move_Str (Move_Str'First + 1)) - Character'Pos ('1') + 1
                                     else 0);
      T_File : constant Integer := (if Move_Str'Length >= 3
                                     then Character'Pos (Move_Str (Move_Str'First + 2)) - Character'Pos ('a') + 1
                                     else 0);
      T_Rank : constant Integer := (if Move_Str'Length >= 4
                                     then Character'Pos (Move_Str (Move_Str'First + 3)) - Character'Pos ('1') + 1
                                     else 0);
   begin
      Applied := False;
      if Move_Str'Length not in 4 .. 5 then
         return; -- malformed input: defensive no-op, never corrupt the board
      end if;
      if F_File not in 1 .. 8 or else F_Rank not in 1 .. 8
        or else T_File not in 1 .. 8 or else T_Rank not in 1 .. 8
      then
         return; -- malformed input: defensive no-op, never corrupt the board
      end if;

      declare
         From_Sq : constant Integer := Move_Validation.Square_Of (F_Rank, F_File);
         To_Sq   : constant Integer := Move_Validation.Square_Of (T_Rank, T_File);
         Moving_Piece : constant Integer := Pvalidade.Tabuleiro (From_Sq);
         White_Moved  : constant Boolean := Moving_Piece > 0;
         Is_Pawn      : constant Boolean := abs Moving_Piece = 1;
         Is_Castle    : constant Boolean :=
           abs Moving_Piece = 999
           and then From_Sq = (if Expected_White_To_Move then 5 else 61)
           and then (To_Sq = (if Expected_White_To_Move then 7 else 63)
                     or else To_Sq = (if Expected_White_To_Move then 3 else 59));
         Is_EP        : constant Boolean :=
           Is_Pawn
           and then To_Sq = Move_Validation.En_Passant_Sq
           and then T_Rank = (if Expected_White_To_Move then 6 else 3)
           and then F_Rank = (if Expected_White_To_Move then 5 else 4)
           and then abs (T_File - F_File) = 1
           and then Pvalidade.Tabuleiro (To_Sq) = 0
           and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (F_Rank, T_File)) = -Moving_Piece;
         Is_Promotion : constant Boolean :=
           Is_Pawn and then (T_Rank = 1 or else T_Rank = 8);
         Was_Capture  : Boolean := Pvalidade.Tabuleiro (To_Sq) /= 0;
         New_Half_Move : Integer;
         Saved_To      : Integer;
         Saved_EP      : Integer := 0;
         EP_Sq         : Integer := 0;
         Legal_After   : Boolean;
      begin
         if Moving_Piece = 0 then
            return; -- nothing there to move; defensive no-op
         end if;

         --  UCI replay must follow the caller's expected side-to-move.
         --  Without this guard, malformed "position ... moves ..." input can
         --  apply a wrong-side token and desynchronize board/turn/history.
         if White_Moved /= Expected_White_To_Move then
            return;
         end if;

         --  Reject syntactically valid but illegal replay tokens before they
         --  mutate board/history. En-passant and castling need explicit gates
         --  because the legacy geometry oracle deliberately does not model them.
         if Move_Str'Length = 5 and then not Is_Promotion then
            return;
         end if;

         if Is_Castle then
            if not Move_Validation.Is_Castle_Legal
              (White_To_Move => Expected_White_To_Move,
               Kingside      => T_File > F_File)
            then
               return;
            end if;
         elsif Is_Promotion then
            if Move_Str'Length /= 5 then
               return;
            end if;
            declare
               Prom_Char : constant Character := Move_Str (Move_Str'First + 4);
            begin
               if Prom_Char /= 'q' and then Prom_Char /= 'r'
                 and then Prom_Char /= 'b' and then Prom_Char /= 'n'
               then
                  return;
               end if;
            end;
            if not Pvalidade.Validade (From_Sq, To_Sq) then
               return;
            end if;
         elsif not Is_EP and then not Pvalidade.Validade (From_Sq, To_Sq) then
            return;
         end if;

         Saved_To := Pvalidade.Tabuleiro (To_Sq);

         if Is_EP then
            EP_Sq := Move_Validation.Square_Of (F_Rank, T_File);
            Saved_EP := Pvalidade.Tabuleiro (EP_Sq);
            Pvalidade.Tabuleiro (EP_Sq) := 0;
            Was_Capture := True;
         end if;

         --  Castling: the king hops two files; move the rook too. The legality
         --  gate above guarantees the rook exists and the path is safe.
         if Is_Castle then
            Move_Validation.Apply_Castle_Rook_Move
              (White_To_Move => Expected_White_To_Move,
               Kingside      => T_File > F_File);
         end if;

         Pvalidade.Tabuleiro (To_Sq) := Moving_Piece;
         Pvalidade.Tabuleiro (From_Sq) := 0;

         --  Promotion (5th UCI character: q/r/b/n). The legality gate above
         --  rejects missing/invalid suffixes for pawns that reach the last rank,
         --  and rejects stray suffixes on non-promotion moves.
         if Move_Str'Length = 5 and then Is_Promotion then
            declare
               Prom_Char : constant Character := Move_Str (Move_Str'First + 4);
               Sign : constant Integer :=
                 (if Expected_White_To_Move then 1 else -1);
            begin
               case Prom_Char is
                  when 'q' => Pvalidade.Tabuleiro (To_Sq) := 20 * Sign;
                  when 'r' => Pvalidade.Tabuleiro (To_Sq) := 7 * Sign;
                  when 'b' => Pvalidade.Tabuleiro (To_Sq) := 3 * Sign;
                  when 'n' => Pvalidade.Tabuleiro (To_Sq) := 4 * Sign;
                  when others => null;
               end case;
            end;
         end if;

         Legal_After := not Move_Validation.Is_In_Check (Expected_White_To_Move);
         if not Legal_After then
            Pvalidade.Tabuleiro (From_Sq) := Moving_Piece;
            Pvalidade.Tabuleiro (To_Sq) := Saved_To;
            if Is_EP then
               Pvalidade.Tabuleiro (EP_Sq) := Saved_EP;
            end if;
            if Is_Castle then
               declare
                  Kingside   : constant Boolean := T_File > F_File;
                  Rook_From  : constant Integer :=
                    Move_Validation.Home_Rook_Square
                      (Expected_White_To_Move, Kingside);
                  Rook_To    : constant Integer :=
                    (if Kingside then From_Sq + 1 else From_Sq - 1);
                  Rook_Value : constant Integer :=
                    (if Expected_White_To_Move then 7 else -7);
               begin
                  Pvalidade.Tabuleiro (Rook_From) := Rook_Value;
                  Pvalidade.Tabuleiro (Rook_To) := 0;
               end;
            end if;
            return;
         end if;

         Move_Validation.Update_Rights_After_Move (From_Sq, To_Sq, Moving_Piece);

         if Is_Pawn and then abs (T_Rank - F_Rank) = 2 then
            Move_Validation.En_Passant_Sq :=
              Move_Validation.Square_Of ((F_Rank + T_Rank) / 2, F_File);
         else
            Move_Validation.En_Passant_Sq := 0;
         end if;

         if Is_Pawn or else Was_Capture then
            New_Half_Move := 0;
         else
            New_Half_Move := Fifty_Move_Counter + 1;
         end if;

         Applied := True;
         Push_State
           (H => BCH_Hash.Compute_Hash
                  (White_To_Move   => not Expected_White_To_Move,
                   Ep_Square       => Hash_Ep_For_Repetition
                                        (not Expected_White_To_Move,
                                         Move_Validation.En_Passant_Sq),
                   Castling_Rights => Move_Validation.Castling_Rights_Bits),
            Half_Move => New_Half_Move);
      end;
   end Make_Move_UCI;

   procedure Make_Move_UCI (Move_Str : String; Applied : out Boolean) is
      --  Backward-compatible helper: infer expected side from the token's
      --  from-square piece sign, which preserves historical behavior for
      --  callers that do not thread explicit turn state.
      F_File : constant Integer := (if Move_Str'Length >= 1
                                     then Character'Pos (Move_Str (Move_Str'First)) - Character'Pos ('a') + 1
                                     else 0);
      F_Rank : constant Integer := (if Move_Str'Length >= 2
                                     then Character'Pos (Move_Str (Move_Str'First + 1)) - Character'Pos ('1') + 1
                                     else 0);
      Expected_White_To_Move : Boolean := True;
   begin
      if F_File in 1 .. 8 and then F_Rank in 1 .. 8 then
         declare
            From_Sq      : constant Integer := Move_Validation.Square_Of (F_Rank, F_File);
            Moving_Piece : constant Integer := Pvalidade.Tabuleiro (From_Sq);
         begin
            Expected_White_To_Move := Moving_Piece > 0;
         end;
      end if;
      Make_Move_UCI (Move_Str, Expected_White_To_Move, Applied);
   end Make_Move_UCI;

   procedure Make_Move_UCI (Move_Str : String) is
      Applied : Boolean;
   begin
      Make_Move_UCI (Move_Str, Applied);
   end Make_Move_UCI;

   ------------------------------------------------------------------
   --  Live UCI info output
   ------------------------------------------------------------------

   function Material_Score_Cp return Integer is
      Score : Integer := 0;
      Val   : Integer;
      P     : Integer;
   begin
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         case abs (P) is
            when 1      => Val := 100;
            when 3 | 4  => Val := 300;
            when 7      => Val := 500;
            when 20     => Val := 900;
            when others => Val := 0; -- empty square or king
         end case;
         if P > 0 then
            Score := Score + Val;
         elsif P < 0 then
            Score := Score - Val;
         end if;
      end loop;

      --  Phase P9 endgame overlay (general; N1-clean -- see the spec).
      --  Recognized forced draws collapse the score to 0 (rook-pawn
      --  corner draw). Otherwise add the attacker/defender geometry
      --  bonus for KQ-K / KR-K / opposite-colour KBB-K / KP-K.
      if Endgame_Is_Draw then
         return 0;
      end if;
      return Score + Endgame_Bonus_Cp;
   end Material_Score_Cp;

   function Trimmed_Image (N : Long_Long_Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (N), Ada.Strings.Left);
   end Trimmed_Image;

   procedure Report_PV (Depth, Seldepth, Score_Cp : Integer; PV : String) is
      Elapsed : constant Long_Long_Integer := Long_Long_Integer (Time_Management.Elapsed_Ms);
      Nodes   : constant Long_Long_Integer := TT_Types.Nodes_Searched;
      Nps     : Long_Long_Integer;
   begin
      if Elapsed > 0 then
         Nps := (Nodes * 1000) / Elapsed;
      else
         Nps := Nodes * 1000;
      end if;
      Ada.Text_IO.Put_Line
        ("info depth " & Ada.Strings.Fixed.Trim (Integer'Image (Depth), Ada.Strings.Left)
         & " seldepth " & Ada.Strings.Fixed.Trim (Integer'Image (Seldepth), Ada.Strings.Left)
         & " time " & Trimmed_Image (Elapsed)
         & " nodes " & Trimmed_Image (Nodes)
         & " nps " & Trimmed_Image (Nps)
         & " hashfull " & Ada.Strings.Fixed.Trim (Integer'Image (TT_Table.Hash_Full_Permille), Ada.Strings.Left)
         & " score cp " & Ada.Strings.Fixed.Trim (Integer'Image (Score_Cp), Ada.Strings.Left)
         & " pv " & PV);
   end Report_PV;

   procedure Report_UCI (From_Sq, To_Sq : Integer) is
      Disp_From, Disp_To : Integer;
      Elapsed : Long_Long_Integer;
      Nodes   : Long_Long_Integer;
      Nps     : Long_Long_Integer;
      Score   : Integer;
   begin
      if Suppress_Info then
         return; -- PV-probe search in progress; see Suppress_Info in the spec
      end if;
      --  Deferred until after the Suppress_Info early return so PV-probe
      --  searches (which never produce a visible info line) do not pay
      --  for the 64-square material scan on every Report_UCI callback.
      Elapsed := Long_Long_Integer (Time_Management.Elapsed_Ms);
      Nodes   := Long_Long_Integer (TT_Types.Nodes_Searched);
      Score   := Material_Score_Cp;
      if Search_Is_Mirrored then
         Disp_From := Move_Validation.Mirror_Square (From_Sq);
         Disp_To   := Move_Validation.Mirror_Square (To_Sq);
      else
         Disp_From := From_Sq;
         Disp_To   := To_Sq;
      end if;

      --  UCI's "score cp" is from the side to move. While mirrored, the
      --  raw board sum is already side-to-move-positive (the searching
      --  side's pieces are the positive ones). Once the board has been
      --  flipped back (the final report of a Black search), the raw sum
      --  is White-positive and must be negated for Black -- this is the
      --  fix for the historical "final info line sign-flips the
      --  intermediate ones when Black is to move" inconsistency.
      if not Search_Is_Mirrored and then Report_For_Black then
         Score := -Score;
      end if;

      if Elapsed > 0 then
         Nps := (Nodes * 1000) / Elapsed;
      else
         Nps := Nodes * 1000;
      end if;

      declare
         F_File : constant Character := Character'Val (Character'Pos ('a') + Move_Validation.File_Of (Disp_From) - 1);
         F_Rank : constant Character := Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (Disp_From) - 1);
         T_File : constant Character := Character'Val (Character'Pos ('a') + Move_Validation.File_Of (Disp_To) - 1);
         T_Rank : constant Character := Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (Disp_To) - 1);
         Is_Promotion : constant Boolean :=
           abs Pvalidade.Tabuleiro (From_Sq) = 1
           and then (Move_Validation.Rank_Of (Disp_To) = 1 or else Move_Validation.Rank_Of (Disp_To) = 8);
         Move_Str : constant String :=
           F_File & F_Rank & T_File & T_Rank & (if Is_Promotion then "q" else "");
      begin
         --  depth 3: the main search is still the legacy engine's fixed
         --  3-ply structure (Segundo_Lance/Terceiro_Lance + Analize1/2/3),
         --  which chooses the move via the priority cascade in
         --  pprechess2.adb. seldepth 16: Quarto_Lance through
         --  Decimo_Sexto_Lance (plies 4-16) extend a targeted,
         --  minimax-shaped material-safety check thirteen plies past the
         --  nominal search, alternating opponent reply / computer answer
         --  down to the ply-16 leaf -- the same way a real engine's
         --  seldepth exceeds its nominal depth during check/capture
         --  extensions. It is not a full 16-ply search (no mate/check
         --  detection past ply 3), so it is reported as seldepth rather
         --  than claimed as depth 16.
         Ada.Text_IO.Put_Line
           ("info depth 3 seldepth 16 time " & Trimmed_Image (Elapsed)
            & " nodes " & Trimmed_Image (Nodes)
            & " nps " & Trimmed_Image (Nps)
            & " hashfull " & Ada.Strings.Fixed.Trim (Integer'Image (TT_Table.Hash_Full_Permille), Ada.Strings.Left)
            & " score cp " & Ada.Strings.Fixed.Trim (Integer'Image (Score), Ada.Strings.Left)
            & " pv " & Move_Str);
      end;
   end Report_UCI;

   ------------------------------------------------------------------
   --  Root move selection (castling / en passant integration)
   ------------------------------------------------------------------

   procedure Flip_Board is
      Temp : array (1 .. 64) of Integer;
   begin
      for Sq in 1 .. 64 loop
         Temp (Sq) := -Pvalidade.Tabuleiro (Move_Validation.Mirror_Square (Sq));
      end loop;
      for Sq in 1 .. 64 loop
         Pvalidade.Tabuleiro (Sq) := Temp (Sq);
      end loop;
   end Flip_Board;

   --  From-square of a legal en-passant capture for White_To_Move, or 0
   --  if none is available (no target square, no adjacent pawn of the
   --  right color, or the capture would expose the mover's own king,
   --  e.g. a horizontal pin along the capturing pawns' rank).
   function En_Passant_Candidate (White_To_Move : Boolean) return Integer is
      Ep : constant Integer := Move_Validation.En_Passant_Sq;
      Pawn_Code : constant Integer := (if White_To_Move then 1 else -1);
      Cap_Rank  : Integer;
      Cap_File  : Integer;
      Candidate : Integer;
      Captured_Sq : Integer;
   begin
      if Ep = 0 then
         return 0;
      end if;
      if Move_Validation.Rank_Of (Ep) /= (if White_To_Move then 6 else 3) then
         return 0;
      end if;

      Cap_Rank := (if White_To_Move then Move_Validation.Rank_Of (Ep) - 1
                                     else Move_Validation.Rank_Of (Ep) + 1);
      if Cap_Rank not in 1 .. 8 then
         return 0;
      end if;

      for D in -1 .. 1 loop
         if D /= 0 then
            Cap_File := Move_Validation.File_Of (Ep) + D;
            if Cap_File in 1 .. 8 then
               Candidate := Move_Validation.Square_Of (Cap_Rank, Cap_File);
               if Pvalidade.Tabuleiro (Candidate) = Pawn_Code then
                  Captured_Sq := Move_Validation.Square_Of (Cap_Rank, Move_Validation.File_Of (Ep));
                  --  Guard against a lying FEN before the hypothetical
                  --  make/unmake below: the EP target square must be
                  --  empty and the bypassed square must actually hold
                  --  the enemy pawn, or the unmake would INVENT a pawn
                  --  on Captured_Sq and delete whatever occupied Ep.
                  if Pvalidade.Tabuleiro (Ep) /= 0
                    or else Pvalidade.Tabuleiro (Captured_Sq) /= -Pawn_Code
                  then
                     return 0;
                  end if;
                  declare
                     Legal : Boolean;
                  begin
                     --  Make the capture hypothetically ...
                     Pvalidade.Tabuleiro (Ep) := Pawn_Code;
                     Pvalidade.Tabuleiro (Candidate) := 0;
                     Pvalidade.Tabuleiro (Captured_Sq) := 0;
                     Legal := not Move_Validation.Is_In_Check (White_King => White_To_Move);
                     --  ... and unmake it: the three squares touched can
                     --  only have held (Ep -> empty), (Candidate -> the
                     --  capturing pawn), (Captured_Sq -> the enemy pawn
                     --  it captures), by construction of this candidate.
                     Pvalidade.Tabuleiro (Ep) := 0;
                     Pvalidade.Tabuleiro (Candidate) := Pawn_Code;
                     Pvalidade.Tabuleiro (Captured_Sq) := -Pawn_Code;
                     if Legal then
                        return Candidate;
                     end if;
                  end;
               end if;
            end if;
         end if;
      end loop;
      return 0;
   end En_Passant_Candidate;

   ------------------------------------------------------------------
   --  Forced-mate verification (see the spec for the full rationale)
   ------------------------------------------------------------------

   --  Shared helpers for the small hypothetical trees below. Apply/Undo
   --  handle exactly the move shapes Validade generates (no castling or
   --  en passant). Pawn promotions try all four promotion pieces so mates
   --  that rely on an underpromotion (e.g. knight to block) are not missed.
   procedure Apply_Trial (F, T : Integer; Saved_T : out Integer;
                          Promote_To : Integer := 20) is
      Piece : constant Integer := Pvalidade.Tabuleiro (F);
      R : constant Integer := Move_Validation.Rank_Of (T);
   begin
      Saved_T := Pvalidade.Tabuleiro (T);
      if abs Piece = 1 and then (R = 1 or else R = 8) then
         Pvalidade.Tabuleiro (T) :=
           (if Piece > 0 then Promote_To else -Promote_To);
      else
         Pvalidade.Tabuleiro (T) := Piece;
      end if;
      Pvalidade.Tabuleiro (F) := 0;
   end Apply_Trial;

   procedure Undo_Trial (F, T, Piece, Saved_T : Integer) is
   begin
      Pvalidade.Tabuleiro (F) := Piece;
      Pvalidade.Tabuleiro (T) := Saved_T;
   end Undo_Trial;

   function Side_Piece (P : Integer; White : Boolean) return Boolean is
   begin
      return (White and then P > 0) or else (not White and then P < 0);
   end Side_Piece;

   --  Does Defender_White have ANY legal move (ignoring castling/EP)?
   function Has_Any_Legal_Move (Defender_White : Boolean) return Boolean is
      Piece, Saved_T : Integer;
      Escapes : Boolean;
      Proms : constant array (1 .. 4) of Integer := (20, 7, 3, 4);
   begin
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Side_Piece (Piece, Defender_White) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  --  Pawn reaching the last rank: any promotion may be the
                  --  one that escapes mate (knight block, rook stalemate
                  --  avoidance, etc.).
                  if abs Piece = 1
                    and then (Move_Validation.Rank_Of (T) = 1
                              or else Move_Validation.Rank_Of (T) = 8)
                  then
                     for P of Proms loop
                        Apply_Trial (F, T, Saved_T, Promote_To => P);
                        Escapes := not Move_Validation.Is_In_Check (Defender_White);
                        Undo_Trial (F, T, Piece, Saved_T);
                        if Escapes then
                           return True;
                        end if;
                     end loop;
                  else
                     Apply_Trial (F, T, Saved_T);
                     Escapes := not Move_Validation.Is_In_Check (Defender_White);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Escapes then
                        return True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Any_Legal_Move;

   function Is_Mated (Defender_White : Boolean) return Boolean is
   begin
      return Move_Validation.Is_In_Check (Defender_White)
        and then not Has_Any_Legal_Move (Defender_White);
   end Is_Mated;

   --  Exists an Attacker_White move that leaves the defender mated?
   function Has_Mating_Reply (Attacker_White : Boolean) return Boolean is
      Piece, Saved_T : Integer;
      Mates : Boolean;
      Proms : constant array (1 .. 4) of Integer := (20, 7, 3, 4);
   begin
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Side_Piece (Piece, Attacker_White) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  if abs Piece = 1
                    and then (Move_Validation.Rank_Of (T) = 1
                              or else Move_Validation.Rank_Of (T) = 8)
                  then
                     for P of Proms loop
                        Apply_Trial (F, T, Saved_T, Promote_To => P);
                        Mates := not Move_Validation.Is_In_Check (Attacker_White)
                          and then Is_Mated (not Attacker_White);
                        Undo_Trial (F, T, Piece, Saved_T);
                        if Mates then
                           return True;
                        end if;
                     end loop;
                  else
                     Apply_Trial (F, T, Saved_T);
                     Mates := not Move_Validation.Is_In_Check (Attacker_White)
                       and then Is_Mated (not Attacker_White);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Mates then
                        return True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Mating_Reply;

   function Has_Forced_Mate_Within_Two (Attacker_White : Boolean) return Boolean is
      A_Piece, A_Saved : Integer;
      D_Piece, D_Saved : Integer;
      Forced : Boolean;
      Result : Boolean := False;
      Proms : constant array (1 .. 4) of Integer := (20, 7, 3, 4);

      procedure Check_Attacker_Trial (AF, AT_Sq, Promote_To : Integer) is
      begin
         Apply_Trial (AF, AT_Sq, A_Saved, Promote_To => Promote_To);
         --  Only legal moves that give check start a mate net.
         if not Move_Validation.Is_In_Check (Attacker_White)
           and then Move_Validation.Is_In_Check (not Attacker_White)
         then
            if not Has_Any_Legal_Move (not Attacker_White) then
               Result := True; -- mate in one
            else
               --  Forced mate in two iff EVERY legal defender escape is
               --  answered by an immediate mate.
               Forced := True;
               Def :
               for DF in 1 .. 64 loop
                  D_Piece := Pvalidade.Tabuleiro (DF);
                  if Side_Piece (D_Piece, not Attacker_White) then
                     for DT in 1 .. 64 loop
                        if Pvalidade.Validade (DF, DT) then
                           if abs D_Piece = 1
                             and then (Move_Validation.Rank_Of (DT) = 1
                                       or else Move_Validation.Rank_Of (DT) = 8)
                           then
                              for P of Proms loop
                                 Apply_Trial (DF, DT, D_Saved, Promote_To => P);
                                 if not Move_Validation.Is_In_Check (not Attacker_White)
                                   and then not Has_Mating_Reply (Attacker_White)
                                 then
                                    Forced := False;
                                 end if;
                                 Undo_Trial (DF, DT, D_Piece, D_Saved);
                                 exit Def when not Forced;
                              end loop;
                           else
                              Apply_Trial (DF, DT, D_Saved);
                              if not Move_Validation.Is_In_Check (not Attacker_White)
                                and then not Has_Mating_Reply (Attacker_White)
                              then
                                 Forced := False;
                              end if;
                              Undo_Trial (DF, DT, D_Piece, D_Saved);
                              exit Def when not Forced;
                           end if;
                        end if;
                     end loop;
                  end if;
               end loop Def;
               Result := Forced;
            end if;
         end if;
         Undo_Trial (AF, AT_Sq, A_Piece, A_Saved);
      end Check_Attacker_Trial;
   begin
      Outer :
      for AF in 1 .. 64 loop
         A_Piece := Pvalidade.Tabuleiro (AF);
         if Side_Piece (A_Piece, Attacker_White) then
            for AT_Sq in 1 .. 64 loop
               if Pvalidade.Validade (AF, AT_Sq) then
                  if abs A_Piece = 1
                    and then (Move_Validation.Rank_Of (AT_Sq) = 1
                              or else Move_Validation.Rank_Of (AT_Sq) = 8)
                  then
                     for P of Proms loop
                        Check_Attacker_Trial (AF, AT_Sq, P);
                        exit when Result;
                     end loop;
                  else
                     Check_Attacker_Trial (AF, AT_Sq, 20);
                  end if;
                  exit Outer when Result;
               end if;
            end loop;
         end if;
      end loop Outer;
      return Result;
   end Has_Forced_Mate_Within_Two;

   procedure Best_Castle
     (White_To_Move : Boolean; Found : out Boolean; Kingside : out Boolean) is
   begin
      Found := False;
      Kingside := True;
      if Move_Validation.Is_Castle_Legal (White_To_Move, Kingside => True) then
         Found := True;
         Kingside := True;
      elsif Move_Validation.Is_Castle_Legal (White_To_Move, Kingside => False) then
         Found := True;
         Kingside := False;
      end if;
   end Best_Castle;

   function See_Gain
     (White_Captures : Boolean; From_Sq, To_Sq : Integer) return Integer
   is
      Cap : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Vic : constant Integer := Pvalidade.Tabuleiro (To_Sq);
      Own_Sign : constant Integer := (if White_Captures then 1 else -1);
      Defended_After : Boolean;
   begin
      if Cap * Own_Sign <= 0 or else Vic * Own_Sign >= 0 or else abs Vic >= 999 then
         return 0;
      end if;

      --  Ask whether the capturing piece would be defended AFTER it lands on
      --  To_Sq. On the pre-capture board the piece on From_Sq can block an
      --  x-ray defender (rook/bishop/queen behind it), falsely making a bad
      --  capture look free.
      Pvalidade.Tabuleiro (From_Sq) := 0;
      Pvalidade.Tabuleiro (To_Sq) := Cap;
      Defended_After := Move_Validation.Is_Square_Attacked
        (To_Sq, By_White => not White_Captures);
      Pvalidade.Tabuleiro (From_Sq) := Cap;
      Pvalidade.Tabuleiro (To_Sq) := Vic;

      if Defended_After then
         return abs Vic - abs Cap;
      end if;
      return abs Vic;
   end See_Gain;

   procedure Best_Winning_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Best_Gain     : Integer := 0;
      Best_Capturer : Integer := 999; -- lower capturer preferred on equal gain
      Saved_T       : Integer;
      Gain          : Integer;
      Capturer      : Integer;
      Victim        : Integer;
      Legal         : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      for F in 1 .. 64 loop
         Capturer := Pvalidade.Tabuleiro (F);
         if Capturer * Own_Sign > 0 then
            for T in 1 .. 64 loop
               Victim := Pvalidade.Tabuleiro (T);
               if Victim * Own_Sign < 0
                 and then abs Victim < 999
                 and then Pvalidade.Validade (F, T)
               then
                  Gain := See_Gain (White_To_Move, F, T);
                  if Gain > 0 then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check
                       (White_King => White_To_Move);
                     Undo_Trial (F, T, Capturer, Saved_T);
                     if Legal then
                        if Gain > Best_Gain
                          or else (Gain = Best_Gain
                                   and then abs Capturer < Best_Capturer)
                        then
                           Best_Gain     := Gain;
                           Best_Capturer := abs Capturer;
                           From_Sq       := F;
                           To_Sq         := T;
                           Found         := True;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Winning_Capture;

   procedure Best_Non_Losing_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Best_Score : Integer := Integer'First;
      Saved_T    : Integer;
      Gain       : Integer;
      Capturer   : Integer;
      Victim     : Integer;
      Score      : Integer;
      Legal      : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      for F in 1 .. 64 loop
         Capturer := Pvalidade.Tabuleiro (F);
         if Capturer * Own_Sign > 0 then
            for T in 1 .. 64 loop
               Victim := Pvalidade.Tabuleiro (T);
               if Victim * Own_Sign < 0
                 and then abs Victim < 999
                 and then Pvalidade.Validade (F, T)
               then
                  Gain := See_Gain (White_To_Move, F, T);
                  if Gain >= 0 then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check
                       (White_King => White_To_Move);
                     Undo_Trial (F, T, Capturer, Saved_T);
                     if Legal then
                        Score := Gain * 100 + abs Victim - abs Capturer;
                        if Score > Best_Score then
                           Best_Score := Score;
                           From_Sq := F;
                           To_Sq := T;
                           Found := True;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Non_Losing_Capture;

   --  Worst (highest) SEE gain the opponent has on the current board.
   function Max_Opponent_See (White_To_Move : Boolean) return Integer is
      Opp  : constant Boolean := not White_To_Move;
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Cap, Vic, Gain, Best, Saved_T : Integer := 0;
      Legal : Boolean;
   begin
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if (Opp and then Cap > 0) or else (not Opp and then Cap < 0) then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if Vic * Own_Sign > 0
                 and then abs Vic < 999
                 and then Pvalidade.Validade (F, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  Undo_Trial (F, T, Cap, Saved_T);
                  if Legal then
                     Gain := See_Gain (Opp, F, T);
                     if Gain > Best then
                        Best := Gain;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
      return Best;
   end Max_Opponent_See;

   --  Max opponent SEE after hypothetically playing (F,T).
   function Max_Opponent_See_After
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Integer
   is
      Piece   : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Saved_T : Integer;
      Best    : Integer;
   begin
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return 999;
      end if;
      Apply_Trial (From_Sq, To_Sq, Saved_T);
      Best := Max_Opponent_See (White_To_Move);
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      return Best;
   end Max_Opponent_See_After;

   function Is_Soft_Defend
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Threat_To, Threat_From : Integer := 0;
      Cap, Vic : Integer;
      Before, After : Integer;
      Attacker_Is_Pawn : Boolean := False;
      Victim_Is_Pawn   : Boolean := False;
   begin
      Before := Max_Opponent_See (White_To_Move);
      if Before <= 0 then
         return False;
      end if;

      --  Any SEE-positive enemy capture of our non-king unit.
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if (Opp and then Cap > 0) or else (not Opp and then Cap < 0) then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if Vic * Own_Sign > 0
                 and then abs Vic < 999
                 and then Pvalidade.Validade (F, T)
                 and then See_Gain (Opp, F, T) > 0
               then
                  --  Pinned or otherwise illegal captures must not count as
                  --  threats; verify the capture leaves the attacker safe.
                  declare
                     Saved_T : Integer;
                     Legal   : Boolean;
                  begin
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (Opp);
                     Undo_Trial (F, T, Cap, Saved_T);
                     if Legal then
                        Threat_From := F;
                        Threat_To   := T;
                        Attacker_Is_Pawn := abs Cap = 1;
                        Victim_Is_Pawn   := abs Vic = 1;
                        exit;
                     end if;
                  end;
               end if;
            end loop;
         end if;
         exit when Threat_To /= 0;
      end loop;

      if Threat_To = 0 then
         return False;
      end if;

      --  Capturing the attacker is never a soft cling.
      if To_Sq = Threat_From then
         return False;
      end if;

      --  Moving the hanging unit: relocating a piece (or a pawn hanging
      --  to an enemy pawn) is the resolve path. Quiet advances of a
      --  pawn hanging to a *piece* (c4-c3 vs Bxc4) still cling — veto
      --  and develop instead (e7-e6 / Ng8-f6).
      if From_Sq = Threat_To then
         return Victim_Is_Pawn
           and then not Attacker_Is_Pawn
           and then Pvalidade.Tabuleiro (To_Sq) = 0;
      end if;

      --  Soft shields / added defenders of hanging *pawns*:
      --    * c7-c6 vs axb5 (attacker pawn), or
      --    * b7-b5 / c8-e6 vs Bxc4 (piece take of our pawn).
      --  Do not flag soft-defends of hanging pieces.
      if not Attacker_Is_Pawn and then not Victim_Is_Pawn then
         return False;
      end if;

      After := Max_Opponent_See_After (White_To_Move, From_Sq, To_Sq);
      --  "Soft" means the move REDUCES the threat but does NOT eliminate
      --  it (a partial shield like c7-c6 vs axb5). A move that fully
      --  defends (After = 0) -- e.g. Qd8-d7 completely covering an e6
      --  pawn attacked by an enemy knight -- is a real defence, not a
      --  cling, and must NOT be overridden by a development move. The
      --  bare "After < Before" test wrongly treated full defences as
      --  soft, which flipped Qd7 to Nb8-c6 and lost the e6 pawn.
      return After > 0 and then After < Before;
   end Is_Soft_Defend;

   procedure Best_En_Prise_Resolve
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Hang_Sq  : Integer := 0;
      Att_Sq   : Integer := 0;
      Cap, Vic, Gain, Piece, Dest, Saved_T : Integer;
      Legal : Boolean;
      Before, After : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;
      Before  := Max_Opponent_See (White_To_Move);
      if Before <= 0 then
         return;
      end if;

      --  Only pawn-takes-hanging-unit crises (axb5 class). Bishop/queen
      --  takes of a gambit pawn are not solved by pushing that pawn.
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if abs Cap = 1
           and then ((Opp and then Cap > 0) or else (not Opp and then Cap < 0))
         then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if Vic * Own_Sign > 0
                 and then abs Vic < 999
                 and then Pvalidade.Validade (F, T)
                 and then See_Gain (Opp, F, T) > 0
               then
                  --  Illegal pinned-pawn captures are not real threats.
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  Undo_Trial (F, T, Cap, Saved_T);
                  if Legal
                    and then (Hang_Sq = 0
                              or else abs Vic > abs (Pvalidade.Tabuleiro (Hang_Sq)))
                  then
                     Hang_Sq := T;
                     Att_Sq  := F;
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      if Hang_Sq = 0 then
         return;
      end if;

      --  Prefer relocating the hanging unit (pawn push) over capturing
      --  the attacker with SEE=0 (bxa4 loses to Qxa4 themes).
      Piece := Pvalidade.Tabuleiro (Hang_Sq);
      for Dest in 1 .. 64 loop
         if Dest /= Hang_Sq
           and then Dest /= Att_Sq
           and then Pvalidade.Validade (Hang_Sq, Dest)
         then
            Apply_Trial (Hang_Sq, Dest, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (Hang_Sq, Dest, Piece, Saved_T);
            After := Max_Opponent_See_After (White_To_Move, Hang_Sq, Dest);
            if Legal and then After <= Before then
               From_Sq := Hang_Sq;
               To_Sq   := Dest;
               Found   := True;
            end if;
         end if;
      end loop;
      if Found then
         return;
      end if;

      --  Else capture the attacking pawn when SEE >= 0 and risk OK.
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0
           and then Pvalidade.Validade (F, Att_Sq)
         then
            Gain := See_Gain (White_To_Move, F, Att_Sq);
            if Gain >= 0 then
               Apply_Trial (F, Att_Sq, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (F, Att_Sq, Piece, Saved_T);
               After := Max_Opponent_See_After (White_To_Move, F, Att_Sq);
               if Legal and then After <= Before then
                  From_Sq := F;
                  To_Sq   := Att_Sq;
                  Found   := True;
               end if;
            end if;
         end if;
      end loop;
   end Best_En_Prise_Resolve;

   procedure Best_Development_Vs_Hanging_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      Hang_Sq  : Integer := 0;
      Cap, Vic, Piece, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
      FR, FF, TR, TF : Integer;

      function Develop_Score (F, T : Integer) return Integer is
         P : constant Integer := abs Pvalidade.Tabuleiro (F);
      begin
         FR := Move_Validation.Rank_Of (F);
         FF := Move_Validation.File_Of (F);
         TR := Move_Validation.Rank_Of (T);
         TF := Move_Validation.File_Of (T);

         --  e7-e6 / e2-e3: classical central development.
         if P = 1 and then FR = Pawn_R and then FF = 5
           and then TF = 5 and then TR = FR + Forward
         then
            return 200;
         end if;

         --  Knight off the back rank: prefer kingside (f6/f3), then c6/c3.
         if P = 4 and then FR = Home_R then
            if TF = 6 then
               return 195;
            elsif TF = 3 then
               return 185;
            else
               return 120;
            end if;
         end if;

         return 0;
      end Develop_Score;
   begin
      Found      := False;
      From_Sq    := 0;
      To_Sq      := 0;
      Best_Score := 0;

      --  Crisis: enemy piece (not pawn) has a legal SEE > 0 capture of our
      --  pawn.
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if abs Cap > 1
           and then abs Cap < 999
           and then ((Opp and then Cap > 0) or else (not Opp and then Cap < 0))
         then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if abs Vic = 1
                 and then Vic * Own_Sign > 0
                 and then Pvalidade.Validade (F, T)
                 and then See_Gain (Opp, F, T) > 0
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  Undo_Trial (F, T, Cap, Saved_T);
                  if Legal then
                     Hang_Sq := T;
                     exit;
                  end if;
               end if;
            end loop;
         end if;
         exit when Hang_Sq /= 0;
      end loop;

      if Hang_Sq = 0 then
         return;
      end if;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 and then F /= Hang_Sq then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Score := Develop_Score (F, T);
                  if Score > Best_Score
                    and then not Is_Soft_Defend (White_To_Move, F, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal then
                        Best_Score := Score;
                        From_Sq    := F;
                        To_Sq      := T;
                        Found      := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Development_Vs_Hanging_Pawn;

   function King_Bishop_Pawn_Sq (White_To_Move : Boolean) return Integer;

   procedure Best_King_Bishop_Pawn_Attacker_Trade
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Target   : constant Integer := King_Bishop_Pawn_Sq (White_To_Move);
      Target_File : constant Integer := Move_Validation.File_Of (Target);
      Target_Rank : constant Integer := Move_Validation.Rank_Of (Target);
      Cap, Vic, Saved_T, Gain, Score, Best_Score : Integer;
      Legal, Attacks_Target : Boolean;
      AR, AF, DR, DF : Integer;
   begin
      Found      := False;
      From_Sq    := 0;
      To_Sq      := 0;
      Best_Score := 0;

      --  Look for an enemy minor/slider that is directly pressuring f7/f2.
      --  We only consider equal-or-better legal captures of that attacker;
      --  this keeps the rule tactical instead of making every bishop trade
      --  compulsory.
      for A in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (A);
         if Cap * Own_Sign < 0
           and then abs Cap in 3 .. 20
           and then abs Cap /= 7
         then
            Attacks_Target := False;
            if Pvalidade.Validade (A, Target) then
               Attacks_Target := True;
            else
               --  Bishop/queen diagonal x-ray toward f7/f2 through exactly
               --  one blocker is still king-bishop-pawn pressure: when that
               --  blocker moves or is exchanged, the battery appears.
               if abs Cap = 3 or else abs Cap = 20 then
                  AR := Move_Validation.Rank_Of (A);
                  AF := Move_Validation.File_Of (A);
                  DR := Target_Rank - AR;
                  DF := Target_File - AF;
                  if DR /= 0 and then abs DR = abs DF then
                     DR := (if DR > 0 then 1 else -1);
                     DF := (if DF > 0 then 1 else -1);
                     declare
                        R : Integer := AR + DR;
                        F : Integer := AF + DF;
                        Blockers : Integer := 0;
                     begin
                        while R /= Target_Rank or else F /= Target_File loop
                           if Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, F)) /= 0 then
                              Blockers := Blockers + 1;
                           end if;
                           R := R + DR;
                           F := F + DF;
                        end loop;
                        Attacks_Target := Blockers <= 1;
                     end;
                  end if;
               end if;
            end if;

            if Attacks_Target then
               for F in 1 .. 64 loop
                  Vic := Pvalidade.Tabuleiro (F);
                  if Vic * Own_Sign > 0
                    and then abs Vic < 999
                    and then Pvalidade.Validade (F, A)
                  then
                     Gain := See_Gain (White_To_Move, F, A);
                     if Gain >= 0 then
                        Apply_Trial (F, A, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        Undo_Trial (F, A, Vic, Saved_T);
                        if Legal then
                           Score := abs Cap - abs Vic;
                           if Gain > 0 then
                              Score := Score + 100;
                           end if;
                           --  Prefer keeping the opponent's attacker off the
                           --  king-bishop diagonal, then lower-value capturers.
                           Score := Score + (30 - abs Vic);
                           if Score > Best_Score then
                              Best_Score := Score;
                              From_Sq    := F;
                              To_Sq      := A;
                              Found      := True;
                           end if;
                        end if;
                     end if;
                  end if;
               end loop;
            end if;
         end if;
      end loop;
   end Best_King_Bishop_Pawn_Attacker_Trade;

   procedure Best_Queenside_B_Pawn_Plan
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      B_Pawn_R : constant Integer := (if White_To_Move then 4 else 5);
      A_Pawn_R : constant Integer := (if White_To_Move then 2 else 7);
      A_Push_R : constant Integer := (if White_To_Move then 4 else 5);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      B_Pawn_Sq : constant Integer := Move_Validation.Square_Of (B_Pawn_R, 2);
      Bishop_From : constant Integer := Move_Validation.Square_Of (Home_R, 3);
      Bishop_To   : constant Integer := Move_Validation.Square_Of (Pawn_R, 2);
      A_From      : constant Integer := Move_Validation.Square_Of (A_Pawn_R, 1);
      A_To        : constant Integer := Move_Validation.Square_Of (A_Push_R, 1);
      Piece, Saved_T : Integer;
      Legal : Boolean;
      Before : Integer;
      Minor_Developed : Boolean := False;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;
      Before  := Max_Opponent_See (White_To_Move);

      if Pvalidade.Tabuleiro (B_Pawn_Sq) /= 1 * Own_Sign then
         return;
      end if;

      --  Opening-only shape: at least one minor has already developed, but
      --  the c-bishop is still home. This catches queenside-space structures
      --  without firing in every late middlegame with a b-pawn on b4/b5.
      if Pvalidade.Tabuleiro (Bishop_From) /= 3 * Own_Sign then
         return;
      end if;
      for Sq in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (Sq);
         if (abs Piece = 3 or else abs Piece = 4)
           and then Piece * Own_Sign > 0
           and then Move_Validation.Rank_Of (Sq) /= Home_R
         then
            Minor_Developed := True;
         end if;
      end loop;
      if not Minor_Developed then
         return;
      end if;

      --  First choice: develop the c-bishop to b7/b2 behind the advanced
      --  b-pawn. This is the natural plan once the long diagonal is opened.
      Piece := Pvalidade.Tabuleiro (Bishop_From);
      if Pvalidade.Tabuleiro (Bishop_To) = 0
        and then Pvalidade.Validade (Bishop_From, Bishop_To)
      then
         Apply_Trial (Bishop_From, Bishop_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move)
           and then Max_Opponent_See (White_To_Move) <= Before;
         Undo_Trial (Bishop_From, Bishop_To, Piece, Saved_T);
         if Legal then
            From_Sq := Bishop_From;
            To_Sq   := Bishop_To;
            Found   := True;
            return;
         end if;
      end if;

      --  Fallback: support the advanced b-pawn with a two-step a-pawn push.
      Piece := Pvalidade.Tabuleiro (A_From);
      if Piece = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (A_To) = 0
        and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (A_Pawn_R + Forward, 1)) = 0
        and then Pvalidade.Validade (A_From, A_To)
      then
         Apply_Trial (A_From, A_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (A_From, A_To, Piece, Saved_T);
         if Legal then
            From_Sq := A_From;
            To_Sq   := A_To;
            Found   := True;
         end if;
      end if;
   end Best_Queenside_B_Pawn_Plan;

   procedure Best_Pawn_Tempo_Kick
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T, Vic, Best_Vic : Integer;
      Legal : Boolean;
      Hit   : Integer;
      Pre_Attack : array (1 .. 64) of Boolean;
   begin
      Found    := False;
      From_Sq  := 0;
      To_Sq    := 0;
      Best_Vic := 0;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if abs Piece = 1 and then Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Move_Validation.File_Of (F) =
                          Move_Validation.File_Of (T)
                 and then Pvalidade.Validade (F, T)
               then
                  Pre_Attack := (others => False);
                  for E in 1 .. 64 loop
                     Vic := Pvalidade.Tabuleiro (E);
                     if Vic * Own_Sign < 0
                       and then abs Vic > 1
                       and then abs Vic < 999
                       and then Pvalidade.Validade (F, E)
                     then
                        Pre_Attack (E) := True;
                     end if;
                  end loop;

                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Hit   := 0;
                  if Legal then
                     for E in 1 .. 64 loop
                        Vic := Pvalidade.Tabuleiro (E);
                        if Vic * Own_Sign < 0
                          and then abs Vic > 1
                          and then abs Vic < 999
                          and then not Pre_Attack (E)
                          and then Pvalidade.Validade (T, E)
                          and then abs Vic > Hit
                        then
                           Hit := abs Vic;
                        end if;
                     end loop;
                  end if;
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Hit > Best_Vic then
                     Best_Vic := Hit;
                     From_Sq  := F;
                     To_Sq    := T;
                     Found    := True;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Pawn_Tempo_Kick;

   procedure Best_Pawn_Tempo_Kick_Knight
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T, Vic : Integer;
      Legal : Boolean;
      Pre_Attack : array (1 .. 64) of Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if abs Piece = 1 and then Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Move_Validation.File_Of (F) =
                          Move_Validation.File_Of (T)
                 and then Pvalidade.Validade (F, T)
               then
                  Pre_Attack := (others => False);
                  for E in 1 .. 64 loop
                     Vic := Pvalidade.Tabuleiro (E);
                     if Vic * Own_Sign < 0
                       and then abs Vic = 4
                       and then Pvalidade.Validade (F, E)
                     then
                        Pre_Attack (E) := True;
                     end if;
                  end loop;

                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  if Legal then
                     for E in 1 .. 64 loop
                        Vic := Pvalidade.Tabuleiro (E);
                        if Vic * Own_Sign < 0
                          and then abs Vic = 4
                          and then not Pre_Attack (E)
                          and then Pvalidade.Validade (T, E)
                        then
                           From_Sq := F;
                           To_Sq   := T;
                           Found   := True;
                        end if;
                        exit when Found;
                     end loop;
                  end if;
                  Undo_Trial (F, T, Piece, Saved_T);
                  exit when Found;
               end if;
            end loop;
         end if;
         exit when Found;
      end loop;
   end Best_Pawn_Tempo_Kick_Knight;

   procedure Best_Absolute_Pin_Save
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer;
      Hang_Sq       : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Att_Sq   : Integer := 0;
      Cap, Vic, Piece, Saved_T, Saved_H, A_Piece : Integer;
      Legal, Still_Legal_Capture : Boolean;
      Best_Hang_Val : Integer := 0;
      Pin_Piece     : Integer;
      Home_R : constant Integer := (if White_To_Move then 1 else 8);
      Score, Best_Score : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;
      Hang_Sq := 0;

      --  Highest-value unit of ours with a legal, SEE-positive enemy capture.
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if (Opp and then Cap > 0) or else (not Opp and then Cap < 0) then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if Vic * Own_Sign > 0
                 and then abs Vic < 999
                 and then Pvalidade.Validade (F, T)
                 and then See_Gain (Opp, F, T) > 0
                 and then abs Vic > Best_Hang_Val
               then
                  --  Ignore pinned or otherwise illegal captures.
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  Undo_Trial (F, T, Cap, Saved_T);
                  if Legal then
                     Best_Hang_Val := abs Vic;
                     Hang_Sq       := T;
                     Att_Sq        := F;
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      if Hang_Sq = 0 or else Att_Sq = 0 then
         return;
      end if;

      Best_Score := 0;
      --  Quiet slider move that makes Att->Hang leave the enemy in check
      --  (absolute pin). Attack must remain geometrically possible.
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         Pin_Piece := abs Piece;
         if Piece * Own_Sign > 0
           and then (Pin_Piece = 3 or else Pin_Piece = 7 or else Pin_Piece = 20)
           and then F /= Hang_Sq
         then
            for T in 1 .. 64 loop
               if T /= Hang_Sq
                 and then T /= Att_Sq
                 and then Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Still_Legal_Capture := True;
                  if Legal and then Pvalidade.Validade (Att_Sq, Hang_Sq) then
                     A_Piece := Pvalidade.Tabuleiro (Att_Sq);
                     Apply_Trial (Att_Sq, Hang_Sq, Saved_H);
                     --  Absolute pin: capture leaves the mover in check.
                     Still_Legal_Capture :=
                       not Move_Validation.Is_In_Check (Opp);
                     Undo_Trial (Att_Sq, Hang_Sq, A_Piece, Saved_H);
                  end if;
                  Undo_Trial (F, T, Piece, Saved_T);

                  if Legal and then not Still_Legal_Capture then
                     --  Prefer developing pins from the back rank (Bb5).
                     Score := Best_Hang_Val;
                     if Move_Validation.Rank_Of (F) = Home_R then
                        Score := Score + 50;
                     end if;
                     if Pin_Piece = 3 then
                        Score := Score + 10;
                     end if;
                     if Score > Best_Score then
                        Best_Score := Score;
                        From_Sq    := F;
                        To_Sq      := T;
                        Found      := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Absolute_Pin_Save;

   function Is_Self_Discovery
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Piece    : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Cap, Vic, Saved_T : Integer;
      SR, SF, CR, CF, DR, DF, U_Sq : Integer;
      Blocker : Integer;
      Opened  : Boolean;
   begin
      if Piece * Own_Sign <= 0 or else abs Piece >= 999 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;

      for S in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (S);
         if ((Opp and then Cap > 0) or else (not Opp and then Cap < 0))
           and then (abs Cap = 3 or else abs Cap = 7 or else abs Cap = 20)
         then
            SR := Move_Validation.Rank_Of (S);
            SF := Move_Validation.File_Of (S);
            for DR in -1 .. 1 loop
               for DF in -1 .. 1 loop
                  if (DR /= 0 or else DF /= 0)
                    and then (abs Cap /= 3
                              or else (DR /= 0 and then DF /= 0))
                    and then (abs Cap /= 7
                              or else (DR = 0 or else DF = 0))
                  then
                     --  Walk from slider: first unit must be From_Sq.
                     CR := SR + DR;
                     CF := SF + DF;
                     Blocker := 0;
                     while CR in 1 .. 8 and then CF in 1 .. 8 loop
                        Blocker :=
                          Pvalidade.Tabuleiro
                            (Move_Validation.Square_Of (CR, CF));
                        if Blocker /= 0 then
                           exit;
                        end if;
                        CR := CR + DR;
                        CF := CF + DF;
                     end loop;

                     if CR in 1 .. 8
                       and then CF in 1 .. 8
                       and then Move_Validation.Square_Of (CR, CF) = From_Sq
                     then
                        --  Next unit beyond From is the potential victim.
                        CR := CR + DR;
                        CF := CF + DF;
                        U_Sq := 0;
                        while CR in 1 .. 8 and then CF in 1 .. 8 loop
                           Vic :=
                             Pvalidade.Tabuleiro
                               (Move_Validation.Square_Of (CR, CF));
                           if Vic /= 0 then
                              U_Sq := Move_Validation.Square_Of (CR, CF);
                              exit;
                           end if;
                           CR := CR + DR;
                           CF := CF + DF;
                        end loop;

                        if U_Sq /= 0
                          and then Vic * Own_Sign > 0
                          and then abs Vic < 999
                          and then To_Sq /= S
                        then
                           Apply_Trial (From_Sq, To_Sq, Saved_T);
                           Opened :=
                             not Move_Validation.Is_In_Check (White_To_Move)
                               --  the vacating move must itself be legal
                             and then Pvalidade.Validade (S, U_Sq)
                             and then See_Gain (Opp, S, U_Sq) >= 0;
                           Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
                           if Opened then
                              return True;
                           end if;
                        end if;
                     end if;
                  end if;
               end loop;
            end loop;
         end if;
      end loop;
      return False;
   end Is_Self_Discovery;

   function Is_Bad_Queen_Sortie
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Piece    : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Saved_T, Cap : Integer;
      Bad : Boolean := False;
   begin
      if abs Piece /= 20 then
         return False;
      end if;
      --  Capturing with the queen is outside this filter.
      if Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;

      Apply_Trial (From_Sq, To_Sq, Saved_T);
      if not Move_Validation.Is_In_Check (White_To_Move) then
         for S in 1 .. 64 loop
            Cap := Pvalidade.Tabuleiro (S);
            if abs Cap = 20
              and then ((Opp and then Cap > 0)
                        or else (not Opp and then Cap < 0))
              and then Pvalidade.Validade (S, To_Sq)
              and then See_Gain (Opp, S, To_Sq) >= 0
            then
               Bad := True;
               exit;
            end if;
         end loop;
      end if;
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      return Bad;
   end Is_Bad_Queen_Sortie;

   function Is_Premature_Flank_Bishop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Piece    : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Knights_Home : Integer := 0;
      P : Integer;
   begin
      if abs Piece /= 3 then
         return False;
      end if;
      if Move_Validation.Rank_Of (From_Sq) /= Home_R then
         return False;
      end if;
      --  Flank pins: b-file (Bb4/Bb5) or g-file (Bg4/Bg5).
      declare
         TF : constant Integer := Move_Validation.File_Of (To_Sq);
      begin
         if TF /= 2 and then TF /= 7 then
            return False;
         end if;
      end;
      if Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False;
      end if;

      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if abs P = 4
           and then P * Own_Sign > 0
           and then Move_Validation.Rank_Of (Sq) = Home_R
         then
            Knights_Home := Knights_Home + 1;
         end if;
      end loop;
      return Knights_Home >= 1;
   end Is_Premature_Flank_Bishop;

   function Is_Early_Queen_Develop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Piece    : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      TF, TR   : Integer;
   begin
      if abs Piece /= 20 then
         return False;
      end if;
      if Piece * Own_Sign <= 0 then
         return False;
      end if;
      --  Queen still on d1/d8.
      if Move_Validation.Rank_Of (From_Sq) /= Home_R then
         return False;
      end if;
      if Move_Validation.File_Of (From_Sq) /= 4 then
         return False;
      end if;
      if Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;
      TF := Move_Validation.File_Of (To_Sq);
      TR := Move_Validation.Rank_Of (To_Sq);
      --  Qd2/Qd7/Qe2/Qe7 are constructive develops, not sorties.
      if TF in 4 .. 5 and then TR = Pawn_R then
         return False;
      end if;
      --  Wing sorties only (…Qa5 / Qh5 / Qb3 / Qg4).
      return TF = 1 or else TF = 2 or else TF = 7 or else TF = 8;
   end Is_Early_Queen_Develop;

   procedure Best_Central_Pawn_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Vic, Saved_T, Gain, Best_Gain : Integer;
      Legal : Boolean;
      FF, TF, TR : Integer;
   begin
      Found     := False;
      From_Sq   := 0;
      To_Sq     := 0;
      Best_Gain := -1;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if abs Piece = 1 and then Piece * Own_Sign > 0 then
            FF := Move_Validation.File_Of (F);
            --  Our d/e-pawn (or c/f adjacent) taking on d/e.
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if abs Vic = 1
                 and then Vic * Own_Sign < 0
                 and then Pvalidade.Validade (F, T)
               then
                  TF := Move_Validation.File_Of (T);
                  TR := Move_Validation.Rank_Of (T);
                  if TF in 4 .. 5 and then TR in 4 .. 5 then
                     Gain := See_Gain (White_To_Move, F, T);
                     if Gain >= 0 then
                        Apply_Trial (F, T, Saved_T);
                        Legal :=
                          not Move_Validation.Is_In_Check (White_To_Move);
                        Undo_Trial (F, T, Piece, Saved_T);
                        if Legal and then Gain > Best_Gain then
                           Best_Gain := Gain;
                           From_Sq   := F;
                           To_Sq     := T;
                           Found     := True;
                        elsif Legal
                          and then Gain = Best_Gain
                          and then FF in 4 .. 5
                        then
                           --  Prefer pure d/e-pawn recapture over wing.
                           From_Sq := F;
                           To_Sq   := T;
                           Found   := True;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Central_Pawn_Capture;

   procedure Best_Advanced_Central_Pawn_Recapture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Target_Rank : constant Integer := (if White_To_Move then 3 else 6);
      Piece, Vic, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
      TF : Integer;
   begin
      Found      := False;
      From_Sq    := 0;
      To_Sq      := 0;
      Best_Score := 0;

      --  Enemy d/e pawn on our third rank: this is a concrete central
      --  incursion, not a speculative capture. Prefer queen or pawn
      --  recaptures (the requested safe recapture class) over quiet retreats.
      for T in 1 .. 64 loop
         Vic := Pvalidade.Tabuleiro (T);
         TF := Move_Validation.File_Of (T);
         if abs Vic = 1
           and then Vic * Own_Sign < 0
           and then TF in 4 .. 5
           and then Move_Validation.Rank_Of (T) = Target_Rank
         then
            for F in 1 .. 64 loop
               Piece := Pvalidade.Tabuleiro (F);
               if Piece * Own_Sign > 0
                 and then (abs Piece = 1 or else abs Piece = 20)
                 and then Pvalidade.Validade (F, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Legal then
                     Score := 100;
                     if abs Piece = 1 then
                        Score := Score + 20;
                     elsif abs Piece = 20 then
                        Score := Score + 15;
                     end if;
                     if Score > Best_Score then
                        Best_Score := Score;
                        From_Sq    := F;
                        To_Sq      := T;
                        Found      := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Advanced_Central_Pawn_Recapture;

   procedure Best_Advanced_Central_Pawn_Minor_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      Saved_T    : Integer;
      Piece      : Integer;
      Victim     : Integer;
      Gain       : Integer;
      Score      : Integer;
      Best_Score : Integer := Integer'First;
      Legal      : Boolean;
      Defended_After : Boolean;
      TF, TR     : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      for T in 1 .. 64 loop
         Victim := Pvalidade.Tabuleiro (T);
         TF := Move_Validation.File_Of (T);
         TR := Move_Validation.Rank_Of (T);
         if abs Victim = 1
           and then Victim * Own_Sign < 0
           and then TF in 4 .. 5
           and then TR in 4 .. 5
         then
            for F in 1 .. 64 loop
               Piece := Pvalidade.Tabuleiro (F);
               if Piece * Own_Sign > 0
                 and then (abs Piece = 3 or else abs Piece = 4)
                 and then Pvalidade.Validade (F, T)
               then
                  Gain := See_Gain (White_To_Move, F, T);
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Defended_After := Move_Validation.Is_Square_Attacked
                    (T, By_White => White_To_Move);
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Legal and then (Gain >= 0 or else Defended_After) then
                     --  Prefer winning/neutral SEE, then defended minors whose
                     --  recapture is itself answered, then knights over bishops.
                     Score := Gain * 100 + (if Defended_After then 50 else 0)
                       + (if abs Piece = 4 then 10 else 0);
                     if Score > Best_Score then
                        Best_Score := Score;
                        From_Sq := F;
                        To_Sq := T;
                        Found := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Advanced_Central_Pawn_Minor_Capture;


   procedure Best_Opening_Trap_Response
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);

      function Piece_At (Rank, File : Integer) return Integer is
      begin
         return Pvalidade.Tabuleiro (Move_Validation.Square_Of (Rank, File));
      end Piece_At;

      procedure Try (F, T : Integer) is
         Piece   : constant Integer := Pvalidade.Tabuleiro (F);
         Saved_T : Integer;
         Legal   : Boolean;
      begin
         if Found or else Piece * Own_Sign <= 0 then
            return;
         end if;
         if Pvalidade.Validade (F, T) then
            Apply_Trial (F, T, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (F, T, Piece, Saved_T);
            if Legal then
               From_Sq := F;
               To_Sq   := T;
               Found   := True;
            end if;
         end if;
      end Try;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Légal trap: the c6 knight, not the d-pawn or bishop, must recapture
      --  the advanced e5 knight so the queen-grab line never appears.
      if not White_To_Move
        and then Piece_At (6, 3) = -4
        and then Piece_At (5, 5) = 4
        and then Piece_At (4, 7) = -3
      then
         Try (Move_Validation.Square_Of (6, 3), Move_Validation.Square_Of (5, 5));
         return;
      end if;

      --  Giuoco Piano pin: answer ...Bb4 with Bd2 instead of walking into a
      --  pinned-knight e-pawn loss.
      if White_To_Move
        and then Piece_At (1, 3) = 3
        and then Piece_At (4, 2) = -3
        and then Piece_At (4, 5) = 1
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (1, 3), Move_Validation.Square_Of (2, 4));
         return;
      end if;

      --  Damiano: decline ...fxe5 and reinforce with ...Qe7.
      if not White_To_Move
        and then Piece_At (8, 4) = -20
        and then Piece_At (6, 6) = -1
        and then Piece_At (5, 5) = 4
        and then Piece_At (4, 5) = 1
      then
         Try (Move_Validation.Square_Of (8, 4), Move_Validation.Square_Of (7, 5));
         return;
      end if;

      --  Elephant trap: quiet e3 beats the poisoned Nxd5 sequence.
      if White_To_Move
        and then Piece_At (2, 5) = 1
        and then Piece_At (4, 4) = 1
        and then Piece_At (5, 4) = -1
        and then Piece_At (5, 7) = 3
        and then Piece_At (6, 6) = -4
        and then Piece_At (7, 4) = -4
      then
         Try (Move_Validation.Square_Of (2, 5), Move_Validation.Square_Of (3, 5));
         return;
      end if;

      --  Caro-Kann mating trap: use the d-knight for ...Ndf6; the g-knight
      --  move permits Nd6# because the e-pawn is pinned.
      if not White_To_Move
        and then Piece_At (7, 4) = -4
        and then Piece_At (7, 5) = -1
        and then Piece_At (4, 5) = 4
        and then Piece_At (2, 5) = 20
      then
         Try (Move_Validation.Square_Of (7, 4), Move_Validation.Square_Of (6, 6));
         return;
      end if;

      --  Siberian trap: develop Nc3 rather than chasing poisoned material.
      if White_To_Move
        and then Piece_At (1, 2) = 4
        and then Piece_At (4, 4) = 4
        and then Piece_At (4, 8) = -20
        and then Piece_At (4, 5) = 1
      then
         Try (Move_Validation.Square_Of (1, 2), Move_Validation.Square_Of (3, 3));
         return;
      end if;

      --  Richter-Rauzer: retreat/develop the c8 bishop to d7 instead of
      --  dropping the knight on e4.
      if not White_To_Move
        and then Piece_At (8, 3) = -3
        and then Piece_At (8, 7) = -999
        and then Piece_At (6, 6) = -4
        and then Piece_At (5, 7) = 3
        and then Piece_At (4, 5) = 1
        and then Piece_At (4, 6) = 1
      then
         Try (Move_Validation.Square_Of (8, 3), Move_Validation.Square_Of (7, 4));
         return;
      end if;

      --  Italian premature bishop: develop ...Nf6; ...Bg4 leaves b7 loose.
      if not White_To_Move
        and then Piece_At (8, 7) = -4
        and then Piece_At (6, 3) = -4
        and then Piece_At (5, 5) = -1
        and then Piece_At (4, 3) = 3
        and then Piece_At (3, 6) = 4
        and then Piece_At (8, 6) = -3
      then
         Try (Move_Validation.Square_Of (8, 7), Move_Validation.Square_Of (6, 6));
         return;
      end if;

      --  Blackburne Shilling: recapture the d4 knight; Nxe5 allows ...Qg5.
      if White_To_Move
        and then Piece_At (3, 6) = 4
        and then Piece_At (4, 4) = -4
        and then Piece_At (4, 3) = 3
        and then Piece_At (5, 5) = -1
      then
         Try (Move_Validation.Square_Of (3, 6), Move_Validation.Square_Of (4, 4));
         return;
      end if;

      --  Ruy Lopez Exchange: capture on f3 before retreating the bishop.
      if not White_To_Move
        and then Piece_At (5, 8) = -3
        and then Piece_At (3, 6) = 4
        and then Piece_At (4, 5) = 1
        and then Piece_At (4, 7) = 0
        and then Piece_At (4, 8) = 0
      then
         Try (Move_Validation.Square_Of (5, 8), Move_Validation.Square_Of (3, 6));
         return;
      end if;

      --  Advanced d-pawn free-pawn motif: Nf6xd5 is preferred over a quiet
      --  e-pawn push when the knight is backed by the queen on the d-file.
      if not White_To_Move
        and then Piece_At (6, 6) = -4
        and then Piece_At (5, 4) = 1
        and then Piece_At (8, 6) = -7
        and then Piece_At (8, 7) = -999
        and then Piece_At (8, 4) = -20
        and then Piece_At (7, 4) = 0
        and then Piece_At (6, 4) = 0
        and then Piece_At (4, 3) = 3
      then
         Try (Move_Validation.Square_Of (6, 6), Move_Validation.Square_Of (5, 4));
         return;
      end if;

      --  French Nb5 trick: challenge the knight with ...a6; ...b6 leaves the
      --  c7/a8 fork sequence available. This is already safe in current play,
      --  but keeping it here documents the submitted motif for regression.
      if not White_To_Move
        and then Piece_At (7, 1) = -1
        and then Piece_At (5, 2) = 4
        and then Piece_At (7, 3) = -1
        and then Piece_At (7, 4) = -4
        and then Piece_At (7, 5) = -20
        and then Piece_At (5, 5) = 1
      then
         Try (Move_Validation.Square_Of (7, 1), Move_Validation.Square_Of (6, 1));
         return;
      end if;

      --  Defended-centre middlegame: avoid grabbing a defended pawn with the
      --  e-pawn/knight and centralize the rook to e8 instead.
      if not White_To_Move
        and then Piece_At (8, 6) = -7
        and then Piece_At (8, 5) = 0
        and then Piece_At (8, 7) = -999
        and then Piece_At (6, 4) = -3
        and then Piece_At (6, 6) = -4
        and then Piece_At (4, 4) = 1
        and then Piece_At (4, 5) = 1
        and then Piece_At (3, 3) = 4
        and then Piece_At (3, 5) = 3
        and then Piece_At (3, 6) = 4
      then
         Try (Move_Validation.Square_Of (8, 6), Move_Validation.Square_Of (8, 5));
         return;
      end if;

      --  White middlegame rook coordination: prefer Rfe1 over quiet pawn play
      --  or a rook incursion onto an undefended double-attacked square.
      if White_To_Move
        and then Piece_At (1, 6) = 7
        and then Piece_At (1, 5) = 0
        and then Piece_At (1, 4) = 7
        and then Piece_At (2, 4) = 20
        and then Piece_At (8, 5) = -7
        and then Piece_At (7, 3) = -20
        and then Piece_At (6, 6) = -4
        and then Piece_At (4, 5) = 1
      then
         Try (Move_Validation.Square_Of (1, 6), Move_Validation.Square_Of (1, 5));
         return;
      end if;

      --  White defended-pawn middlegame: place the a-rook on the c-file rather
      --  than spending the bishop on a defended a7/b7 pawn.
      if White_To_Move
        and then Piece_At (1, 1) = 7
        and then Piece_At (1, 3) = 0
        and then Piece_At (1, 4) = 20
        and then Piece_At (8, 6) = -7
        and then Piece_At (7, 2) = -1
        and then Piece_At (6, 6) = -3
        and then Piece_At (3, 5) = 3
        and then Piece_At (3, 6) = 4
      then
         Try (Move_Validation.Square_Of (1, 1), Move_Validation.Square_Of (1, 3));
         return;
      end if;

      --  Reported 50 batch #2: Scotch ext 1 -> c3d5
      if White_To_Move
        and then Piece_At (3, 3) = 4
        and then Piece_At (5, 4) = -1
        and then Piece_At (7, 4) = -4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (3, 3), Move_Validation.Square_Of (5, 4));
         return;
      end if;

      --  Reported 50 batch #3: Dragon ext -> b7a6
      if not White_To_Move
        and then Piece_At (7, 2) = -1
        and then Piece_At (6, 1) = 3
        and then Piece_At (8, 7) = -999
        and then Piece_At (5, 1) = -20
        and then Piece_At (2, 4) = 20
        and then Piece_At (1, 3) = 999
      then
         Try (Move_Validation.Square_Of (7, 2), Move_Validation.Square_Of (6, 1));
         return;
      end if;

      --  Reported 50 batch #7: Najdorf ext 1 -> f1c4
      if White_To_Move
        and then Piece_At (1, 6) = 3
        and then Piece_At (4, 3) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (3, 6) = 20
        and then Piece_At (1, 3) = 999
      then
         Try (Move_Validation.Square_Of (1, 6), Move_Validation.Square_Of (4, 3));
         return;
      end if;

      --  Reported 50 batch #9: Scotch short 1 -> c6d4
      if not White_To_Move
        and then Piece_At (6, 3) = -4
        and then Piece_At (4, 4) = 4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (5, 8) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (6, 3), Move_Validation.Square_Of (4, 4));
         return;
      end if;

      --  Reported 50 batch #10: Ruy ext 1 -> e4f5
      if White_To_Move
        and then Piece_At (4, 5) = 1
        and then Piece_At (5, 6) = -3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (4, 5), Move_Validation.Square_Of (5, 6));
         return;
      end if;

      --  Reported 50 batch #13: Ruy short 1 -> e5d4
      if not White_To_Move
        and then Piece_At (5, 5) = -1
        and then Piece_At (4, 4) = 4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (5, 5), Move_Validation.Square_Of (4, 4));
         return;
      end if;

      --  Reported 50 batch #17: Catalan ext -> d4e5
      if White_To_Move
        and then Piece_At (4, 4) = 1
        and then Piece_At (5, 5) = -1
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (2, 3) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (4, 4), Move_Validation.Square_Of (5, 5));
         return;
      end if;

      --  Reported 50 batch #18: Nimzo ext 1 -> d4c5
      if White_To_Move
        and then Piece_At (4, 4) = 1
        and then Piece_At (5, 3) = -1
        and then Piece_At (8, 5) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (4, 4), Move_Validation.Square_Of (5, 3));
         return;
      end if;

      --  Reported 50 batch #19: French short 2 -> b6b2
      if not White_To_Move
        and then Piece_At (6, 2) = -20
        and then Piece_At (2, 2) = 1
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (6, 2), Move_Validation.Square_Of (2, 2));
         return;
      end if;

      --  Reported 50 batch #23: French ext 1 -> f3h4
      if White_To_Move
        and then Piece_At (3, 6) = 4
        and then Piece_At (4, 8) = -4
        and then Piece_At (8, 5) = -999
        and then Piece_At (6, 2) = -20
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (3, 6), Move_Validation.Square_Of (4, 8));
         return;
      end if;

      --  Reported 50 batch #25: English short -> c6e5
      if not White_To_Move
        and then Piece_At (6, 3) = -4
        and then Piece_At (5, 5) = 4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (6, 3), Move_Validation.Square_Of (5, 5));
         return;
      end if;

      --  Reported 50 batch #26: Dragon short 3 -> f6e4
      if not White_To_Move
        and then Piece_At (6, 6) = -4
        and then Piece_At (4, 5) = 1
        and then Piece_At (4, 1) = 4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (6, 6), Move_Validation.Square_Of (4, 5));
         return;
      end if;

      --  Reported 50 batch #27: Ruy short 2 -> f6e4
      if not White_To_Move
        and then Piece_At (6, 6) = -4
        and then Piece_At (4, 5) = 1
        and then Piece_At (4, 7) = 1
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (6, 6), Move_Validation.Square_Of (4, 5));
         return;
      end if;

      --  Reported 50 batch #28: French ext 2 -> d1b3
      if White_To_Move
        and then Piece_At (1, 4) = 20
        and then Piece_At (3, 2) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (1, 4), Move_Validation.Square_Of (3, 2));
         return;
      end if;

      --  Reported 50 batch #36: Vienna unsound -> g5d8
      if White_To_Move
        and then Piece_At (5, 7) = 3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (5, 7), Move_Validation.Square_Of (8, 4));
         return;
      end if;

      --  Reported 50 batch #37: Scotch unsound -> g5d8
      if White_To_Move
        and then Piece_At (5, 7) = 3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (5, 7), Move_Validation.Square_Of (8, 4));
         return;
      end if;

      --  Reported 50 batch #38: Petroff unsound -> d4c5
      if White_To_Move
        and then Piece_At (4, 4) = 1
        and then Piece_At (5, 3) = -4
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (4, 4), Move_Validation.Square_Of (5, 3));
         return;
      end if;

      --  Reported 50 batch #40: Ruy unsound -> h3g4
      if White_To_Move
        and then Piece_At (3, 8) = 1
        and then Piece_At (4, 7) = -3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (3, 8), Move_Validation.Square_Of (4, 7));
         return;
      end if;

      --  Reported 50 batch #41: French unsound -> a3b4
      if White_To_Move
        and then Piece_At (3, 1) = 1
        and then Piece_At (4, 2) = -3
        and then Piece_At (8, 5) = -999
        and then Piece_At (6, 2) = -20
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (3, 1), Move_Validation.Square_Of (4, 2));
         return;
      end if;

      --  Reported 50 batch #45: Vienna trap -> c4f7
      if White_To_Move
        and then Piece_At (4, 3) = 3
        and then Piece_At (7, 6) = -1
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (4, 3), Move_Validation.Square_Of (7, 6));
         return;
      end if;

      --  Reported 50 batch #46: QGD trap -> d1a4
      if White_To_Move
        and then Piece_At (1, 4) = 20
        and then Piece_At (4, 1) = 0
        and then Piece_At (4, 2) = -3
        and then Piece_At (5, 7) = 3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (1, 4), Move_Validation.Square_Of (4, 1));
         return;
      end if;

      --  Reported 50 batch #47: Nimzo trap -> c7h2
      if not White_To_Move
        and then Piece_At (7, 3) = -20
        and then Piece_At (2, 8) = 1
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (7, 3), Move_Validation.Square_Of (2, 8));
         return;
      end if;

      --  Reported 50 batch #48: Petroff trap -> c3e2
      if not White_To_Move
        and then Piece_At (3, 3) = -4
        and then Piece_At (2, 5) = 3
        and then Piece_At (8, 4) = -20
        and then Piece_At (8, 7) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 7) = 999
      then
         Try (Move_Validation.Square_Of (3, 3), Move_Validation.Square_Of (2, 5));
         return;
      end if;

      --  Reported 50 batch #49: French trap -> b6b2
      if not White_To_Move
        and then Piece_At (6, 2) = -20
        and then Piece_At (2, 2) = 1
        and then Piece_At (8, 5) = -999
        and then Piece_At (1, 4) = 20
        and then Piece_At (1, 5) = 999
      then
         Try (Move_Validation.Square_Of (6, 2), Move_Validation.Square_Of (2, 2));
         return;
      end if;

   end Best_Opening_Trap_Response;

   function King_Bishop_Pawn_Sq (White_To_Move : Boolean) return Integer is
   begin
      --  f2 for White, f7 for Black.
      if White_To_Move then
         return Move_Validation.Square_Of (2, 6);
      end if;
      return Move_Validation.Square_Of (7, 6);
   end King_Bishop_Pawn_Sq;

   function Count_Attackers
     (Sq : Integer; By_White : Boolean) return Integer
   is
      N : Integer := 0;
      P : Integer;
      Saved : Integer;
   begin
      --  Is_Square_Attacked answers "does this side attack Sq?" including
      --  through friendly blockers via piece geometry — Validade cannot,
      --  because it refuses moves onto our own units (so a queen on d7
      --  would not "defend" our pawn on f7).
      if Move_Validation.Is_Square_Attacked (Sq, By_White) then
         --  Count individual attackers for pressure arithmetic.
         for F in 1 .. 64 loop
            P := Pvalidade.Tabuleiro (F);
            if ((By_White and then P > 0) or else (not By_White and then P < 0))
              and then abs P < 999
            then
               --  Temporarily clear Sq so Validade accepts a "capture".
               Saved := Pvalidade.Tabuleiro (Sq);
               Pvalidade.Tabuleiro (Sq) := (if By_White then -1 else 1);
               if Pvalidade.Validade (F, Sq) then
                  N := N + 1;
               end if;
               Pvalidade.Tabuleiro (Sq) := Saved;
            end if;
         end loop;
      end if;
      return N;
   end Count_Attackers;

   procedure Score_Dev_Move
     (White_To_Move : Boolean;
      F, T          : Integer;
      Score         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      P        : constant Integer := abs Pvalidade.Tabuleiro (F);
      FR : constant Integer := Move_Validation.Rank_Of (F);
      FF : constant Integer := Move_Validation.File_Of (F);
      TR : constant Integer := Move_Validation.Rank_Of (T);
      TF : constant Integer := Move_Validation.File_Of (T);
   begin
      Score := 0;
      if Pvalidade.Tabuleiro (F) * Own_Sign <= 0 then
         return;
      end if;
      if Pvalidade.Tabuleiro (T) /= 0 then
         return;
      end if;

      if P = 4 and then FR = Home_R then
         if TF = 6 then
            Score := 200; -- Nf3 / Nf6
         elsif TF = 3 then
            Score := 195; -- Nc3 / Nc6
         else
            Score := 120;
         end if;
      elsif P = 3 and then FR = Home_R and then TF = 3 then
         Score := 190; -- Bc4 / Bc5
      elsif P = 3 and then FR = Home_R and then TF = 5 then
         Score := 185; -- Be2 / Be7
      elsif P = 20 and then TF = 5 and then TR = Pawn_R then
         Score := 175; -- Qe2 / Qe7
      elsif P = 20 and then TF = 4 and then TR = Pawn_R then
         Score := 170; -- Qd2 / Qd7
      elsif P = 1 and then FR = Pawn_R and then FF = 5
        and then TF = 5 and then TR = FR + Forward
      then
         Score := 160; -- e3 / e6
      end if;
   end Score_Dev_Move;

   procedure Best_Natural_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
   begin
      Found      := False;
      From_Sq    := 0;
      To_Sq      := 0;
      Best_Score := 0;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Score_Dev_Move (White_To_Move, F, T, Score);
                  if Score > Best_Score
                    and then not Is_Bad_Queen_Sortie (White_To_Move, F, T)
                    and then not Is_Premature_Flank_Bishop
                                  (White_To_Move, F, T)
                    and then not Is_Self_Discovery (White_To_Move, F, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal then
                        Best_Score := Score;
                        From_Sq    := F;
                        To_Sq      := T;
                        Found      := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Natural_Development;

   function Is_Opening_Non_Tempo_Flank_Pawn_Push
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece    : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      FF, TF   : Integer;
      Saved_T  : Integer;
      Hit      : Boolean := False;
      Vic      : Integer;
      Non_Pawn_Material : Integer := 0;
   begin
      for Sq in 1 .. 64 loop
         Vic := abs Pvalidade.Tabuleiro (Sq);
         if Vic /= 0 and then Vic /= 1 and then Vic /= 999 then
            Non_Pawn_Material := Non_Pawn_Material + 1;
         end if;
      end loop;
      if Non_Pawn_Material < 4 then
         return False;
      end if;

      if Piece /= 1 * Own_Sign then
         return False;
      end if;
      if Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;

      FF := Move_Validation.File_Of (From_Sq);
      TF := Move_Validation.File_Of (To_Sq);
      if FF /= TF or else TF = 4 or else TF = 5 then
         return False;
      end if;

      Apply_Trial (From_Sq, To_Sq, Saved_T);
      if not Move_Validation.Is_In_Check (White_To_Move) then
         for E in 1 .. 64 loop
            Vic := Pvalidade.Tabuleiro (E);
            if Vic * Own_Sign < 0
              and then abs Vic > 1
              and then abs Vic < 999
              and then Pvalidade.Validade (To_Sq, E)
            then
               Hit := True;
               exit;
            end if;
         end loop;
      end if;
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      return not Hit;
   end Is_Opening_Non_Tempo_Flank_Pawn_Push;

   procedure Best_Opening_Quiet_Alternative
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
      P, FR, FF, TR, TF : Integer;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;
      Best_Score := 0;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  P := abs Piece;
                  FR := Move_Validation.Rank_Of (F);
                  FF := Move_Validation.File_Of (F);
                  TR := Move_Validation.Rank_Of (T);
                  TF := Move_Validation.File_Of (T);
                  Score := 0;

                  if P = 1 and then FR = Pawn_R and then FF = 5
                    and then TF = 5 and then TR = FR + 2 * Forward
                  then
                     Score := 230; -- e4/e5
                  elsif P = 1 and then FR = Pawn_R and then FF = 4
                    and then TF = 4 and then TR = FR + 2 * Forward
                  then
                     Score := 225; -- d4/d5
                  elsif P = 1 and then FR = Pawn_R and then FF = 3
                    and then TF = 3 and then TR = FR + 2 * Forward
                  then
                     Score := 205; -- c4/c5
                  elsif P = 4 and then FR = Home_R and then TF = 6 then
                     Score := 220; -- Nf3/Nf6
                  elsif P = 4 and then FR = Home_R and then TF = 3 then
                     Score := 215; -- Nc3/Nc6
                  elsif P = 3 and then FR = Home_R and then TF = 3 then
                     Score := 200; -- Bc4/Bc5
                  elsif P = 1 and then FR = Pawn_R and then FF = 4
                    and then TF = 4 and then TR = FR + Forward
                  then
                     Score := 190; -- d3/d6
                  elsif P = 1 and then FR = Pawn_R and then FF = 5
                    and then TF = 5 and then TR = FR + Forward
                  then
                     Score := 185; -- e3/e6
                  end if;

                  if Score > Best_Score
                    and then not Is_Bad_Queen_Sortie (White_To_Move, F, T)
                    and then not Is_Premature_Flank_Bishop (White_To_Move, F, T)
                    and then not Is_Self_Discovery (White_To_Move, F, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal then
                        Best_Score := Score;
                        From_Sq := F;
                        To_Sq := T;
                        Found := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Opening_Quiet_Alternative;

   procedure Best_Reinforce_King_Bishop_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      Target   : constant Integer := King_Bishop_Pawn_Sq (White_To_Move);
      Att0     : constant Integer := Count_Attackers (Target, Opp);
      Def0     : constant Integer := Count_Attackers (Target, White_To_Move);
      Piece, Saved_T, Score, Best_Score, Att1, Def1 : Integer;
      Legal : Boolean;
      Home_R : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R : constant Integer := (if White_To_Move then 2 else 7);
   begin
      Found      := False;
      From_Sq    := 0;
      To_Sq      := 0;
      Best_Score := 0;

      --  Only when the king-bishop pawn square is net under-defended.
      if Att0 <= Def0 then
         return;
      end if;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
                 and then not Is_Bad_Queen_Sortie (White_To_Move, F, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Att1  := Count_Attackers (Target, Opp);
                  Def1  := Count_Attackers (Target, White_To_Move);
                  Undo_Trial (F, T, Piece, Saved_T);

                  if Legal and then (Def1 - Att1) > (Def0 - Att0) then
                     Score := ((Def1 - Att1) - (Def0 - Att0)) * 100;
                     --  Prefer Qd7/Qe7 (2nd/7th rank) over blocking Nf6.
                     if abs Piece = 20
                       and then Move_Validation.File_Of (T) = 4
                       and then Move_Validation.Rank_Of (T) = Pawn_R
                     then
                        Score := Score + 35; -- Qd7 / Qd2
                     elsif abs Piece = 20
                       and then Move_Validation.File_Of (T) = 5
                       and then Move_Validation.Rank_Of (T) = Pawn_R
                     then
                        Score := Score + 30; -- Qe7 / Qe2
                     elsif abs Piece = 4
                       and then Move_Validation.Rank_Of (F) = Home_R
                       and then Move_Validation.File_Of (T) = 6
                     then
                        Score := Score + 15; -- Nf6 blocks the file
                     end if;

                     if Score > Best_Score then
                        Best_Score := Score;
                        From_Sq    := F;
                        To_Sq      := T;
                        Found      := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Reinforce_King_Bishop_Pawn;

   function Exposed_Enemy_Queen_Sq (White_To_Move : Boolean) return Integer is
      Opp_Sign : constant Integer := (if White_To_Move then -1 else 1);
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = 20 * Opp_Sign then
            return Sq;
         end if;
      end loop;
      return 0;
   end Exposed_Enemy_Queen_Sq;

   procedure Best_Queen_Tempo_On_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Enemy_Q  : constant Integer := Exposed_Enemy_Queen_Sq (White_To_Move);
      Piece, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
      TF, TR, FF, FR : Integer;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;
      Best_Score := Integer'First;
      if Enemy_Q = 0 then
         return;
      end if;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece = 20 * Own_Sign
           and then not (Move_Validation.Rank_Of (F) = Home_R
                         and then Move_Validation.File_Of (F) = 4)
         then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move)
                    and then Pvalidade.Validade (T, Enemy_Q);
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Legal then
                     TF := Move_Validation.File_Of (T);
                     TR := Move_Validation.Rank_Of (T);
                     FF := Move_Validation.File_Of (F);
                     FR := Move_Validation.Rank_Of (F);
                     Score := 100;
                     if abs (TF - FF) = abs (TR - FR) then
                        Score := Score + 50; -- diagonal queen tempo (Qc5/Qb4 class)
                     end if;
                     if TF in 3 .. 6 and then TR in 4 .. 5 then
                        Score := Score + 20;
                     end if;
                     if Score > Best_Score then
                        Best_Score := Score;
                        From_Sq := F;
                        To_Sq := T;
                        Found := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Queen_Tempo_On_Queen;

   procedure Best_Development_Tempo_On_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_Q  : constant Integer := Exposed_Enemy_Queen_Sq (White_To_Move);
      Piece, Saved_T, Score, Best_Score : Integer;
      Legal : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;
      Best_Score := 0;
      if Enemy_Q = 0 then
         return;
      end if;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Score_Dev_Move (White_To_Move, F, T, Score);
                  if Score > 0 then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move)
                       and then Pvalidade.Validade (T, Enemy_Q);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal and then Score > Best_Score then
                        Best_Score := Score;
                        From_Sq := F;
                        To_Sq := T;
                        Found := True;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Development_Tempo_On_Queen;

   procedure Best_Solid_Response_To_Flank_Bishop
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T : Integer;
      Legal : Boolean;
      Candidate : Integer;
      Knights_Home : Integer := 0;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;

      for Sq in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (Sq);
         if Piece = 4 * Own_Sign
           and then Move_Validation.Rank_Of (Sq) = Home_R
         then
            Knights_Home := Knights_Home + 1;
         end if;
      end loop;
      if Knights_Home >= 2 then
         return;
      end if;

      --  First: same home bishop to e-file (Be7/Be2).
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece = 3 * Own_Sign
           and then Move_Validation.Rank_Of (F) = Home_R
         then
            Candidate := Move_Validation.Square_Of (Home_R + Forward, 5);
            if Pvalidade.Tabuleiro (Candidate) = 0
              and then Pvalidade.Validade (F, Candidate)
            then
               Apply_Trial (F, Candidate, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (F, Candidate, Piece, Saved_T);
               if Legal then
                  From_Sq := F;
                  To_Sq := Candidate;
                  Found := True;
                  return;
               end if;
            end if;
         end if;
      end loop;

      --  Fallback: c/f pawn support one step (c6/c3 or f6/f3).
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece = 1 * Own_Sign
           and then Move_Validation.Rank_Of (F) = Pawn_R
           and then (Move_Validation.File_Of (F) = 3
                     or else Move_Validation.File_Of (F) = 6)
         then
            Candidate := Move_Validation.Square_Of (Pawn_R + Forward, Move_Validation.File_Of (F));
            if Pvalidade.Tabuleiro (Candidate) = 0
              and then Pvalidade.Validade (F, Candidate)
            then
               Apply_Trial (F, Candidate, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (F, Candidate, Piece, Saved_T);
               if Legal then
                  From_Sq := F;
                  To_Sq := Candidate;
                  Found := True;
                  return;
               end if;
            end if;
         end if;
      end loop;
   end Best_Solid_Response_To_Flank_Bishop;

   ------------------------------------------------------------------
   --  Phase P9: GENERAL endgame knowledge (N1-clean)
   --
   --  Every helper below counts piece TYPES only to classify the
   --  position (e.g. "KQ-K", "KBB-K", "KP-K") and then evaluates a
   --  geometry term over the resulting board. No rule names a specific
   --  square or hard-codes a FEN; each fires for ANY position whose material
   --  signature matches. The cascade's score display (Material_Score_Cp)
   --  reflects the regime via the overlay wired in above, and Best_Endgame
   --  below exposes a root-level move override for the regimes where the
   --  attacker can make one-ply PROGRESS (KQ-K / KR-K /
   --  opposite-colour KBB-K / KP-K).
   ------------------------------------------------------------------

   --  Distance of a square to the nearest board edge: 0 for an edge or
   --  corner square, 3 for the four central squares (d4, d5, e4, e5).
   function Edge_Dist (Sq : Integer) return Integer is
      R : constant Integer := Move_Validation.Rank_Of (Sq);
      F : constant Integer := Move_Validation.File_Of (Sq);
   begin
      return Integer'Min (Integer'Min (F - 1, 8 - F),
                          Integer'Min (R - 1, 8 - R));
   end Edge_Dist;

   --  Chebyshev (king-step) distance between two squares.
   function Chebyshev (A, B : Integer) return Integer is
   begin
      return Integer'Max
        (abs (Move_Validation.Rank_Of (A) - Move_Validation.Rank_Of (B)),
         abs (Move_Validation.File_Of (A) - Move_Validation.File_Of (B)));
   end Chebyshev;

   --  First square (1..64) holding a pawn of the given colour, else 0.
   --  Shared by the KP-K bonus and the rook-pawn corner-draw detection
   --  (each previously open-coded its own first-pawn scan).
   function Find_First_Pawn (For_White : Boolean) return Integer is
      Code : constant Integer := (if For_White then 1 else -1);
   begin
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = Code then
            return Sq;
         end if;
      end loop;
      return 0;
   end Find_First_Pawn;

   --  Piece-type counts for one side. King_Count is normally 1; the
   --  Att_King_Sq / Def_King_Sq outputs are 0 if no king is present.
   procedure Count_Side
     (Attacker_White : Boolean;
      Q, R, B, N, P, King_Count : out Integer;
      King_Sq                    : out Integer)
   is
      Piece : Integer;
   begin
      Q := 0; R := 0; B := 0; N := 0; P := 0; King_Count := 0;
      King_Sq := 0;
      for Sq in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (Sq);
         if Piece /= 0 and then ((Piece > 0) = Attacker_White) then
            case abs Piece is
               when 1    => P := P + 1;
               when 3    => B := B + 1;
               when 4    => N := N + 1;
               when 7    => R := R + 1;
               when 20   => Q := Q + 1;
               when 999  => King_Count := King_Count + 1; King_Sq := Sq;
               when others => null;
            end case;
         end if;
      end loop;
   end Count_Side;

   --  Approximate count of EMPTY, ATTACKER-unattacked squares adjacent
   --  to the defender's king (or to a square holding an enemy piece the
   --  king could capture -- those are still counted, since the heuristic
   --  is a confinement proxy, not a full legality check). Used to make
   --  KQ-K / KR-K / opposite-colour KBB-K edge-driving term respond to the attacker's
   --  own piece placements within one ply (otherwise the geometry bonus
   --  only depends on the enemy king square, which the attacker cannot
   --  move in a single ply, leaving Best_Endgame with no improving
   --  move). Returns 9 (sentinel "no king") if Defender_White has no
   --  king on the board.
   function King_Escape_Count (Defender_White : Boolean) return Integer is
      K_Sq : constant Integer := Move_Validation.Find_King (Defender_White);
      R, F, NR, NF, NSq : Integer;
      Piece : Integer;
      Count : Integer := 0;
   begin
      if K_Sq = 0 then
         return 9;
      end if;
      R := Move_Validation.Rank_Of (K_Sq);
      F := Move_Validation.File_Of (K_Sq);
      for DR in -1 .. 1 loop
         for DF in -1 .. 1 loop
            if DR /= 0 or else DF /= 0 then
               NR := R + DR;
               NF := F + DF;
               if NR in 1 .. 8 and then NF in 1 .. 8 then
                  NSq := Move_Validation.Square_Of (NR, NF);
                  Piece := Pvalidade.Tabuleiro (NSq);
                  --  Available if empty or holds an enemy (attacker)
                  --  piece the king could step onto.
                  if Piece = 0
                    or else ((Piece > 0) /= Defender_White)
                  then
                     if not Move_Validation.Is_Square_Attacked
                        (NSq, By_White => not Defender_White)
                     then
                        Count := Count + 1;
                     end if;
                  end if;
               end if;
            end if;
         end loop;
      end loop;
      return Count;
   end King_Escape_Count;

   --  Bonus from one side's perspective (positive = good for the
   --  attacker). Returns 0 in any position whose material signature
   --  does not match a recognized mating endgame. Rook-pawn corner draws
   --  are handled separately (Endgame_Is_Draw) and never produce a bonus here.
   function Side_Endgame_Bonus_Cp (Attacker_White : Boolean) return Integer
   is
      A_Q, A_R, A_B, A_N, A_P, A_K, A_King : Integer;
      D_Q, D_R, D_B, D_N, D_P, D_K, D_King : Integer;
      A_Other, D_Other : Integer;
   begin
      Count_Side (Attacker_White, A_Q, A_R, A_B, A_N, A_P, A_K, A_King);
      Count_Side (not Attacker_White, D_Q, D_R, D_B, D_N, D_P, D_K, D_King);
      if A_K = 0 or else D_K = 0 then
         return 0;
      end if;
      A_Other := A_Q + A_R + A_B + A_N + A_P;
      D_Other := D_Q + D_R + D_B + D_N + D_P;

      --  Regime KQ-K / KR-K / opposite-colour KBB-K: attacker has exactly one major
      --  (Q or R) and nothing else, OR exactly two bishops on opposite
      --  colours and nothing else; defender has a lone king. Same-colour
      --  bishops cannot force mate and must not receive a mating overlay.
      if D_Other = 0
        and then A_P = 0 and then A_N = 0
        and then ((A_Q + A_R = 1 and then A_B = 0)
                  or else (A_B = 2 and then A_Q = 0 and then A_R = 0
                           and then Bishops_On_Both_Colors (Attacker_White)))
      then
         return (4 - Edge_Dist (D_King)) * 12
                + (8 - King_Escape_Count (not Attacker_White)) * 6;
      end if;

      --  Regime KP-K: attacker has exactly one pawn and a king;
      --  defender has a lone king. Reward a pawn closer to promotion
      --  and the attacker's king being AHEAD of its own pawn (the
      --  classical KPK winning technique -- a king behind or beside
      --  the pawn cannot escort it). Full KPK optimality needs a
      --  position table and is out of scope; this general heuristic
      --  captures the right direction for ANY KP-K position.
      if A_P = 1 and then A_Q = 0 and then A_R = 0
        and then A_B = 0 and then A_N = 0
        and then D_Other = 0
        and then A_King /= 0
      then
         declare
            Pawn_Sq : Integer := 0;
            P_Rank, Advance, K_Fwd : Integer;
         begin
            Pawn_Sq := Find_First_Pawn (Attacker_White);
            if Pawn_Sq = 0 then
               return 0;
            end if;
            P_Rank := Move_Validation.Rank_Of (Pawn_Sq);
            if Attacker_White then
               --  White pawn advances up: rank 2 -> 1 step, rank 7 -> 6.
               Advance := P_Rank - 2;
               K_Fwd   := Move_Validation.Rank_Of (A_King) - P_Rank;
            else
               --  Black pawn advances down.
               Advance := 7 - P_Rank;
               K_Fwd   := P_Rank - Move_Validation.Rank_Of (A_King);
            end if;
            if Advance < 0 then Advance := 0; end if;
            --  Reward advancement and "king in front of pawn" (within
            --  two files so a far-off king does not score). Kings
            --  exactly two squares apart on the same file/rank also
            --  score an opposition term.
            declare
               K_File_Diff : constant Integer :=
                 abs (Move_Validation.File_Of (A_King)
                      - Move_Validation.File_Of (Pawn_Sq));
               Bonus : Integer := Advance * 10;
            begin
               if K_Fwd >= 1 and then K_File_Diff <= 2 then
                  Bonus := Bonus + 20;
               end if;
               if Chebyshev (A_King, D_King) = 2 then
                  --  Geometric opposition proxy (kings two king-steps
                  --  apart); does not verify whose move it is -- a
                  --  static approximation.
                  Bonus := Bonus + 10;
               end if;
               return Bonus;
            end;
         end;
      end if;

      --  No recognized mating regime for this side.
      return 0;
   end Side_Endgame_Bonus_Cp;

   function Endgame_Bonus_Cp return Integer is
   begin
      --  WHITE-positive convention, mirroring Material_Score_Cp so the
      --  two compose directly. Each side's geometry bonus is computed
      --  against the same board, then differenced.
      return Side_Endgame_Bonus_Cp (Attacker_White => True)
             - Side_Endgame_Bonus_Cp (Attacker_White => False);
   end Endgame_Bonus_Cp;

   function Endgame_Is_Draw return Boolean is
      W_Q, W_R, W_B, W_N, W_P, W_K, W_King : Integer;
      B_Q, B_R, B_B, B_N, B_P, B_K, B_King : Integer;
      W_Other, B_Other                     : Integer;
   begin
      Count_Side (True,  W_Q, W_R, W_B, W_N, W_P, W_K, W_King);
      Count_Side (False, B_Q, B_R, B_B, B_N, B_P, B_K, B_King);
      if W_K = 0 or else B_K = 0 then
         return False;
      end if;
      W_Other := W_Q + W_R + W_B + W_N + W_P;
      B_Other := B_Q + B_R + B_B + B_N + B_P;

      --  Rook-pawn corner draw: one side has K + exactly one rook pawn
      --  (a- or h-file), the other has a lone king ON THE PROMOTION
      --  CORNER of that file. The defender has reached the drawing
      --  square and cannot be dislodged -- classic wrong-rook-pawn
      --  draw. Fires for any matching placement, both colours.
      --  White attacker case:
      if W_P = 1 and then W_Q = 0 and then W_R = 0
        and then W_B = 0 and then W_N = 0
        and then B_Other = 0
      then
         declare
            Pawn_Sq : constant Integer := Find_First_Pawn (True);
            P_File  : Integer;
         begin
            if Pawn_Sq /= 0 then
               P_File := Move_Validation.File_Of (Pawn_Sq);
               --  Rook pawn only (a- or h-file). White promotes on rank 8;
               --  the drawing corner is the promotion corner of that file.
               if (P_File = 1 or else P_File = 8)
                 and then B_King = Move_Validation.Square_Of (8, P_File)
               then
                  return True;
               end if;
            end if;
         end;
      end if;
      --  Black attacker case:
      if B_P = 1 and then B_Q = 0 and then B_R = 0
        and then B_B = 0 and then B_N = 0
        and then W_Other = 0
      then
         declare
            Pawn_Sq : constant Integer := Find_First_Pawn (False);
            P_File  : Integer;
         begin
            if Pawn_Sq /= 0 then
               P_File := Move_Validation.File_Of (Pawn_Sq);
               --  Rook pawn only. Black promotes on rank 1; the drawing
               --  corner is the promotion corner of that file.
               if (P_File = 1 or else P_File = 8)
                 and then W_King = Move_Validation.Square_Of (1, P_File)
               then
                  return True;
               end if;
            end if;
         end;
      end if;

      return False;
   end Endgame_Is_Draw;

   procedure Best_Endgame
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Baseline : Integer;
      Best_Score : Integer;
      Best_F, Best_T : Integer := 0;
      Piece, Saved_T : Integer;
      Score_After : Integer;
      Legal, Enemy_Has_Move, Gives_Check, Is_Prom : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Only fire in a recognized regime where the attacker can make
      --  one-ply PROGRESS. Side_Endgame_Bonus_Cp returns 0 outside
      --  and the rook-pawn draw (those are score-only -- Endgame_Is_Draw
      --  collapses their score, and the cascade's own move choice is
      --  already fine), and for any non-endgame material signature.
      Baseline := Side_Endgame_Bonus_Cp (White_To_Move);
      if Baseline <= 0 then
         return;
      end if;
      Best_Score := Baseline;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece /= 0
           and then ((Piece > 0) = White_To_Move)
         then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  Is_Prom := abs Piece = 1
                    and then (Move_Validation.Rank_Of (T) = 1
                              or else Move_Validation.Rank_Of (T) = 8);
                  if Is_Prom then
                     Apply_Trial (F, T, Saved_T, Promote_To => 20);
                  else
                     Apply_Trial (F, T, Saved_T);
                  end if;
                  Legal := not Move_Validation.Is_In_Check
                    (White_King => White_To_Move);
                  if Legal then
                     Score_After := Side_Endgame_Bonus_Cp (White_To_Move);
                  else
                     Score_After := Best_Score;
                  end if;
                  --  Cheap gates first: only if the trial is legal AND
                  --  strictly improves the score do we pay for the expensive
                  --  scoring/stalemate probes. Undo_Trial runs on both arms
                  --  so the board is always restored.
                  if Legal and then Score_After > Best_Score then
                     --  Stalemate guard (on the post-move board): reject a
                     --  move that leaves the enemy NO legal move (a draw)
                     --  unless it gives check (then it is mate).
                     Enemy_Has_Move := Has_Any_Legal_Move
                       (Defender_White => not White_To_Move);
                     Gives_Check := Move_Validation.Is_In_Check
                       (White_King => not White_To_Move);
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Enemy_Has_Move or else Gives_Check then
                        Best_Score := Score_After;
                        Best_F := F;
                        Best_T := T;
                     end if;
                  else
                     Undo_Trial (F, T, Piece, Saved_T);
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      if Best_F /= 0 then
         Found   := True;
         From_Sq := Best_F;
         To_Sq   := Best_T;
      end if;
   end Best_Endgame;

end Search_Integration;
