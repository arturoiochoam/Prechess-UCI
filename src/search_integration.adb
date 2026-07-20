with Ada.Strings.Fixed;
with Ada.Text_IO;
with Pvalidade;
with Move_Validation;
with BCH_Hash;
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
      end if;
   end Push_State;

   function Is_Threefold_Repetition return Boolean is
      Count : Integer := 0;
      Current_Hash : Hash_Key;
   begin
      if History_Count = 0 then return False; end if;

      Current_Hash := History (History_Count);
      for I in reverse 1 .. History_Count - 1 loop
         if History (I) = Current_Hash then
            Count := Count + 1;
            if Count >= 2 then
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

   function Is_Insufficient_Material return Boolean is
      White_Knights : Integer := 0;
      White_Bishops : Integer := 0;
      Black_Knights : Integer := 0;
      Black_Bishops : Integer := 0;
      Other_Pieces  : Integer := 0;
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

      if Other_Pieces > 0 then return False; end if;

      --  K-K, KB-K, KN-K, KNN-K, KB-KB (same-colored bishops only --
      --  see the note above), KN-KN. K-K, KB-K, KN-K and same-color
      --  KB-KB are FIDE Article 5.2.2 dead positions (no series of
      --  legal moves can produce checkmate); KNN-K and KN-KN are kept
      --  per this project's spec as practically drawn (mate exists
      --  only by helpmate and can never be forced) -- the distinction
      --  is documented in IMPLEMENTATION.md, and since this detection
      --  only produces an advisory info string (the engine plays on;
      --  adjudication is the GUI's), the looser members are harmless.
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 0 then
         return True;
      end if;
      if White_Knights = 0 and White_Bishops = 1 and Black_Knights = 0 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 1 then return True; end if;
      if White_Knights = 1 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 1 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 2 and White_Bishops = 0 and Black_Knights = 0 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 0 and Black_Knights = 2 and Black_Bishops = 0 then return True; end if;
      if White_Knights = 0 and White_Bishops = 1 and Black_Knights = 0 and Black_Bishops = 1
        and White_Bishop_Color = Black_Bishop_Color then return True; end if;
      if White_Knights = 1 and White_Bishops = 0 and Black_Knights = 1 and Black_Bishops = 0 then return True; end if;

      return False;
   end Is_Insufficient_Material;

   function Is_Draw return Boolean is
   begin
      return Is_Threefold_Repetition or else Is_Fifty_Move_Rule or else Is_Insufficient_Material;
   end Is_Draw;

   ------------------------------------------------------------------
   --  FEN parsing
   ------------------------------------------------------------------

   procedure Parse_FEN (FEN : String; White_To_Move : out Boolean) is
      Rank : Integer := 8;
      File : Integer := 1;
      Idx  : Integer := FEN'First;
      Ch   : Character;
      Piece_Code : Integer;
      Half_Move  : Integer := 0;
   begin
      for I in 1 .. 64 loop
         Pvalidade.Tabuleiro (I) := 0;
      end loop;
      Move_Validation.Reset_State;
      White_To_Move := True;

      --  Field 1: piece placement.
      while Idx <= FEN'Last and then Rank >= 1 loop
         Ch := FEN (Idx);
         if Ch = '/' then
            Rank := Rank - 1;
            File := 1;
         elsif Ch = ' ' then
            Idx := Idx + 1;
            exit;
         elsif Ch >= '1' and then Ch <= '8' then
            File := File + Character'Pos (Ch) - Character'Pos ('0');
         else
            Piece_Code := 0;
            case Ch is
               when 'P' => Piece_Code := 1;
               when 'N' => Piece_Code := 4;
               when 'B' => Piece_Code := 3;
               when 'R' => Piece_Code := 7;
               when 'Q' => Piece_Code := 20;
               when 'K' => Piece_Code := 999;
               when 'p' => Piece_Code := -1;
               when 'n' => Piece_Code := -4;
               when 'b' => Piece_Code := -3;
               when 'r' => Piece_Code := -7;
               when 'q' => Piece_Code := -20;
               when 'k' => Piece_Code := -999;
               when others => null;
            end case;
            if Piece_Code /= 0 then
               Pvalidade.Tabuleiro ((Rank - 1) * 8 + File) := Piece_Code;
               File := File + 1;
            end if;
         end if;
         Idx := Idx + 1;
      end loop;

      --  Field 2: active color.
      if Idx <= FEN'Last then
         White_To_Move := FEN (Idx) /= 'b';
         while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
            Idx := Idx + 1;
         end loop;
         Idx := Idx + 1;
      end if;

      --  Field 3: castling availability.
      declare
         WK, WQ, BK, BQ : Boolean := False;
      begin
         while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
            case FEN (Idx) is
               when 'K' => WK := True;
               when 'Q' => WQ := True;
               when 'k' => BK := True;
               when 'q' => BQ := True;
               when others => null; -- '-' : no rights
            end case;
            Idx := Idx + 1;
         end loop;
         Move_Validation.Set_Castling_Rights (WK, WQ, BK, BQ);
         Idx := Idx + 1;
      end;

      --  Field 4: en-passant target square.
      Move_Validation.En_Passant_Sq := 0;
      if Idx <= FEN'Last and then FEN (Idx) /= '-'
        and then Idx + 1 <= FEN'Last
        and then FEN (Idx) in 'a' .. 'h'
        and then FEN (Idx + 1) in '1' .. '8'
      then
         Move_Validation.En_Passant_Sq :=
           Move_Validation.Square_Of
             (Character'Pos (FEN (Idx + 1)) - Character'Pos ('0'),
              Character'Pos (FEN (Idx)) - Character'Pos ('a') + 1);
      end if;
      while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
         Idx := Idx + 1;
      end loop;
      Idx := Idx + 1;

      --  Field 5: halfmove clock (feeds the 50-move counter directly).
      if Idx <= FEN'Last then
         declare
            Start : constant Integer := Idx;
         begin
            while Idx <= FEN'Last and then FEN (Idx) /= ' ' loop
               Idx := Idx + 1;
            end loop;
            begin
               Half_Move := Integer'Value (FEN (Start .. Idx - 1));
            exception
               when others => Half_Move := 0;
            end;
         end;
      end if;
      --  Field 6 (full-move number) does not affect engine behaviour.

      Push_State
        (H => BCH_Hash.Compute_Hash
               (White_To_Move   => White_To_Move,
                Ep_Square       => Move_Validation.En_Passant_Sq,
                Castling_Rights => Move_Validation.Castling_Rights_Bits),
         Half_Move => Half_Move);
   end Parse_FEN;

   ------------------------------------------------------------------
   --  Move application
   ------------------------------------------------------------------

   procedure Make_Move_UCI (Move_Str : String) is
      F_File : constant Integer := Character'Pos (Move_Str (Move_Str'First)) - Character'Pos ('a') + 1;
      F_Rank : constant Integer := Character'Pos (Move_Str (Move_Str'First + 1)) - Character'Pos ('1') + 1;
      T_File : constant Integer := Character'Pos (Move_Str (Move_Str'First + 2)) - Character'Pos ('a') + 1;
      T_Rank : constant Integer := Character'Pos (Move_Str (Move_Str'First + 3)) - Character'Pos ('1') + 1;
   begin
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
         Was_Capture  : Boolean := Pvalidade.Tabuleiro (To_Sq) /= 0;
         New_Half_Move : Integer;
      begin
         if Moving_Piece = 0 then
            return; -- nothing there to move; defensive no-op
         end if;

         --  En passant: a pawn moving diagonally onto the recorded
         --  target square, which is empty by definition, must remove
         --  the pawn it passed rather than the (empty) destination.
         if Is_Pawn and then To_Sq = Move_Validation.En_Passant_Sq
           and then F_File /= T_File and then not Was_Capture
         then
            Pvalidade.Tabuleiro (Move_Validation.Square_Of (F_Rank, T_File)) := 0;
            Was_Capture := True;
         end if;

         --  Castling: the king hops two files; move the rook too.
         if abs Moving_Piece = 999 and then abs (T_File - F_File) = 2 then
            Move_Validation.Apply_Castle_Rook_Move
              (White_To_Move => White_Moved, Kingside => T_File > F_File);
         end if;

         Pvalidade.Tabuleiro (To_Sq) := Moving_Piece;
         Pvalidade.Tabuleiro (From_Sq) := 0;

         --  Promotion (5th UCI character: q/r/b/n).
         if Move_Str'Length >= 5 then
            declare
               Prom_Char : constant Character := Move_Str (Move_Str'First + 4);
               Sign : constant Integer := (if White_Moved then 1 else -1);
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

         Push_State
           (H => BCH_Hash.Compute_Hash
                  (White_To_Move   => not White_Moved,
                   Ep_Square       => Move_Validation.En_Passant_Sq,
                   Castling_Rights => Move_Validation.Castling_Rights_Bits),
            Half_Move => New_Half_Move);
      end;
   end Make_Move_UCI;

   ------------------------------------------------------------------
   --  Live UCI info output
   ------------------------------------------------------------------

   function Material_Score_Cp return Integer is
      Score : Integer := 0;
      Val   : Integer;
   begin
      for Sq in 1 .. 64 loop
         case abs (Pvalidade.Tabuleiro (Sq)) is
            when 1      => Val := 100;
            when 3 | 4  => Val := 300;
            when 7      => Val := 500;
            when 20     => Val := 900;
            when others => Val := 0; -- empty square or king
         end case;
         if Pvalidade.Tabuleiro (Sq) > 0 then
            Score := Score + Val;
         elsif Pvalidade.Tabuleiro (Sq) < 0 then
            Score := Score - Val;
         end if;
      end loop;
      return Score;
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
         & " score cp " & Ada.Strings.Fixed.Trim (Integer'Image (Score_Cp), Ada.Strings.Left)
         & " pv " & PV);
   end Report_PV;

   procedure Report_UCI (From_Sq, To_Sq : Integer) is
      Disp_From, Disp_To : Integer;
      Elapsed : constant Long_Long_Integer := Long_Long_Integer (Time_Management.Elapsed_Ms);
      Nodes   : constant Long_Long_Integer := TT_Types.Nodes_Searched;
      Nps     : Long_Long_Integer;
      Score   : Integer := Material_Score_Cp;
   begin
      if Suppress_Info then
         return; -- PV-probe search in progress; see Suppress_Info in the spec
      end if;
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
         --  pprechess2.adb. seldepth 10: Quarto_Lance through
         --  Decimo_Lance (plies 4-10) extend a targeted, minimax-shaped
         --  material-safety check seven plies past the nominal search,
         --  alternating opponent reply / computer answer down to the
         --  ply-10 leaf -- the same way a real engine's seldepth
         --  exceeds its nominal depth during check/capture extensions.
         --  It is not a full 10-ply search (no mate/check detection
         --  past ply 3), so it is reported as seldepth rather than
         --  claimed as depth 10.
         Ada.Text_IO.Put_Line
           ("info depth 3 seldepth 10 time " & Trimmed_Image (Elapsed)
            & " nodes " & Trimmed_Image (Nodes)
            & " nps " & Trimmed_Image (Nps)
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
   --  en passant), with auto-queen promotion.
   procedure Apply_Trial (F, T : Integer; Saved_T : out Integer) is
      Piece : constant Integer := Pvalidade.Tabuleiro (F);
      R : constant Integer := Move_Validation.Rank_Of (T);
   begin
      Saved_T := Pvalidade.Tabuleiro (T);
      if abs Piece = 1 and then (R = 1 or else R = 8) then
         Pvalidade.Tabuleiro (T) := (if Piece > 0 then 20 else -20);
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
   begin
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Side_Piece (Piece, Defender_White) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  Apply_Trial (F, T, Saved_T);
                  Escapes := not Move_Validation.Is_In_Check (Defender_White);
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Escapes then
                     return True;
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
   begin
      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Side_Piece (Piece, Attacker_White) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  Apply_Trial (F, T, Saved_T);
                  Mates := not Move_Validation.Is_In_Check (Attacker_White)
                    and then Is_Mated (not Attacker_White);
                  Undo_Trial (F, T, Piece, Saved_T);
                  if Mates then
                     return True;
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
   begin
      Outer :
      for AF in 1 .. 64 loop
         A_Piece := Pvalidade.Tabuleiro (AF);
         if Side_Piece (A_Piece, Attacker_White) then
            for AT_Sq in 1 .. 64 loop
               if Pvalidade.Validade (AF, AT_Sq) then
                  Apply_Trial (AF, AT_Sq, A_Saved);
                  --  Only legal moves that give check start a mate net.
                  if not Move_Validation.Is_In_Check (Attacker_White)
                    and then Move_Validation.Is_In_Check (not Attacker_White)
                  then
                     if not Has_Any_Legal_Move (not Attacker_White) then
                        Result := True; -- mate in one
                     else
                        --  Forced mate in two iff EVERY legal defender
                        --  escape is answered by an immediate mate.
                        Forced := True;
                        Def :
                        for DF in 1 .. 64 loop
                           D_Piece := Pvalidade.Tabuleiro (DF);
                           if Side_Piece (D_Piece, not Attacker_White) then
                              for DT in 1 .. 64 loop
                                 if Pvalidade.Validade (DF, DT) then
                                    Apply_Trial (DF, DT, D_Saved);
                                    if not Move_Validation.Is_In_Check (not Attacker_White)
                                      and then not Has_Mating_Reply (Attacker_White)
                                    then
                                       Forced := False;
                                    end if;
                                    Undo_Trial (DF, DT, D_Piece, D_Saved);
                                    exit Def when not Forced;
                                 end if;
                              end loop;
                           end if;
                        end loop Def;
                        Result := Forced;
                     end if;
                  end if;
                  Undo_Trial (AF, AT_Sq, A_Piece, A_Saved);
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

   -----------------------------------------------------------------------
   --  Deferred-tactic booster (see spec, Best_Forcing_Move).
   -----------------------------------------------------------------------

   --  White-positive material of the current board in the legacy value
   --  scale, kings excluded (a king is never a material target).
   function Board_Material return Integer is
      S : Integer := 0;
      P : Integer;
   begin
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if abs P /= 999 then
            S := S + P;
         end if;
      end loop;
      return S;
   end Board_Material;

   Mate_Sentinel : constant Integer := 100_000;
   --  Caps the booster's worst-case cost to a small fixed overhead
   --  (~20 ms). Real material-winning tactics resolve in the first few
   --  thousand nodes, well within this, so the cap never hides one.
   Node_Budget   : constant Integer := 60_000;

   --  Best material the side to move can force, White-positive, exploring
   --  only forcing moves (captures and checks) plus a stand-pat option,
   --  but ALL legal replies when the side to move is itself in check (so
   --  a check's evasions are never missed). Node-bounded; on budget
   --  exhaustion it returns the static material (a safe, neutral stop).
   function Forcing_Value
     (White_To_Move : Boolean; Depth : Integer; Nodes : in out Integer)
      return Integer
   is
      In_Chk   : constant Boolean := Move_Validation.Is_In_Check (White_To_Move);
      Best     : Integer;
      Piece    : Integer;
      Saved_T  : Integer;
      Val      : Integer;
      Any_Move : Boolean := False;
   begin
      if Depth = 0 or else Nodes <= 0 then
         return Board_Material;
      end if;

      --  A side not in check may decline to continue the forcing sequence
      --  (stand pat); a side in check must find a legal move or be mated.
      if In_Chk then
         Best := (if White_To_Move then -Mate_Sentinel else Mate_Sentinel);
      else
         Best := Board_Material;
      end if;

      for F in 1 .. 64 loop
         if Side_Piece (Pvalidade.Tabuleiro (F), White_To_Move) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  declare
                     Is_Capture : constant Boolean :=
                       Side_Piece (Pvalidade.Tabuleiro (T), not White_To_Move);
                  begin
                     Piece := Pvalidade.Tabuleiro (F);
                     Apply_Trial (F, T, Saved_T);
                     if not Move_Validation.Is_In_Check (White_To_Move) then
                        --  Legal. Explore it only if it is forcing, or if
                        --  we are in check (then every escape must be tried).
                        if In_Chk
                          or else Is_Capture
                          or else Move_Validation.Is_In_Check (not White_To_Move)
                        then
                           Any_Move := True;
                           Nodes := Nodes - 1;
                           Val := Forcing_Value (not White_To_Move, Depth - 1, Nodes);
                           if White_To_Move then
                              if Val > Best then Best := Val; end if;
                           else
                              if Val < Best then Best := Val; end if;
                           end if;
                        end if;
                     end if;
                     Undo_Trial (F, T, Piece, Saved_T);
                  end;
               end if;
            end loop;
         end if;
      end loop;

      --  In check with no legal move at all: checkmate for the side to move.
      if In_Chk and then not Any_Move then
         return (if White_To_Move then -Mate_Sentinel else Mate_Sentinel);
      end if;
      return Best;
   end Forcing_Value;

   procedure Best_Forcing_Move
     (Mover_White : Boolean; From, To : out Integer; Gain : out Integer)
   is
      Base    : constant Integer := Board_Material;
      Depth   : constant := 5;              -- up to three mover moves deep
      Nodes   : Integer := Node_Budget;
      Piece   : Integer;
      Saved_T : Integer;
      Val     : Integer;
      --  Signed so that "better for the mover" is always "larger".
      Best_Signed : Integer := 0;           -- gain over stand-pat, mover's view
      Sign        : constant Integer := (if Mover_White then 1 else -1);
   begin
      From := 0;
      To   := 0;
      Gain := 0;

      for F in 1 .. 64 loop
         if Side_Piece (Pvalidade.Tabuleiro (F), Mover_White) then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  declare
                     Is_Capture : constant Boolean :=
                       Side_Piece (Pvalidade.Tabuleiro (T), not Mover_White);
                  begin
                     Piece := Pvalidade.Tabuleiro (F);
                     Apply_Trial (F, T, Saved_T);
                     if not Move_Validation.Is_In_Check (Mover_White)
                       and then (Is_Capture
                                 or else Move_Validation.Is_In_Check (not Mover_White))
                     then
                        Val := Forcing_Value (not Mover_White, Depth - 1, Nodes);
                        --  Net material for the mover vs. not acting.
                        if (Val - Base) * Sign > Best_Signed then
                           Best_Signed := (Val - Base) * Sign;
                           From := F;
                           To   := T;
                        end if;
                     end if;
                     Undo_Trial (F, T, Piece, Saved_T);
                  end;
               end if;
            end loop;
         end if;
      end loop;

      --  Ignore mate-tinged values: this booster is about winning
      --  material only; mate handling is the forced-mate machinery's job.
      if Best_Signed > 0 and then Best_Signed < Mate_Sentinel / 2 then
         Gain := Best_Signed;
      else
         From := 0;
         To   := 0;
         Gain := 0;
      end if;
   end Best_Forcing_Move;

   function Forced_Gain_Of
     (Mover_White : Boolean; From, To : Integer) return Integer
   is
      Base    : constant Integer := Board_Material;
      Nodes   : Integer := Node_Budget;
      Saved_T : Integer;
      Piece   : constant Integer := Pvalidade.Tabuleiro (From);
      Sign    : constant Integer := (if Mover_White then 1 else -1);
      Val     : Integer;
   begin
      if not Side_Piece (Piece, Mover_White)
        or else not Pvalidade.Validade (From, To)
      then
         return -Mate_Sentinel;
      end if;
      Apply_Trial (From, To, Saved_T);
      if Move_Validation.Is_In_Check (Mover_White) then
         Undo_Trial (From, To, Piece, Saved_T);
         return -Mate_Sentinel;
      end if;
      Val := Forcing_Value (not Mover_White, 4, Nodes);
      Undo_Trial (From, To, Piece, Saved_T);
      return (Val - Base) * Sign;
   end Forced_Gain_Of;

   --  Centrality of a square by file distance from the centre, matching
   --  the legacy cascade's own quiet-move tie-break (Quiet_Move_Score):
   --  d/e files score highest, a/h files lowest.
   function Centrality (Sq : Integer) return Integer is
      File : constant Integer := Move_Validation.File_Of (Sq);
   begin
      return 8 - abs (2 * File - 9);
   end Centrality;

   --  Could some Enemy_White pawn, with a single forthcoming push (one
   --  square, or two from its home rank), come to attack the empty
   --  square Sq? Used to discount "mobility" squares that a pawn can chase
   --  away next move -- the mechanism behind the reported bishop trap.
   function Pawn_Push_Threatens
     (Sq : Integer; Enemy_White : Boolean) return Boolean
   is
      Rs   : constant Integer := Move_Validation.Rank_Of (Sq);
      Fs   : constant Integer := Move_Validation.File_Of (Sq);
      Dir  : constant Integer := (if Enemy_White then 1 else -1);
      Home : constant Integer := (if Enemy_White then 2 else 7);
      Code : constant Integer := (if Enemy_White then 1 else -1);
      Ra   : constant Integer := Rs - Dir; -- rank a pawn must reach to hit Sq
   begin
      if Ra not in 1 .. 8 then
         return False;
      end if;
      for Cf in Fs - 1 .. Fs + 1 loop
         if Cf in 1 .. 8 and then Cf /= Fs then
            declare
               Land  : constant Integer := Move_Validation.Square_Of (Ra, Cf);
               One_R : constant Integer := Ra - Dir;
            begin
               if Pvalidade.Tabuleiro (Land) = 0 and then One_R in 1 .. 8 then
                  if Pvalidade.Tabuleiro
                       (Move_Validation.Square_Of (One_R, Cf)) = Code
                  then
                     return True; -- single push reaches Land
                  end if;
                  declare
                     Two_R : constant Integer := Ra - 2 * Dir;
                  begin
                     if Two_R = Home
                       and then Pvalidade.Tabuleiro
                                  (Move_Validation.Square_Of (One_R, Cf)) = 0
                       and then Pvalidade.Tabuleiro
                                  (Move_Validation.Square_Of (Two_R, Cf)) = Code
                     then
                        return True; -- double push from home rank reaches Land
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return False;
   end Pawn_Push_Threatens;

   --  Number of onward squares the piece now standing on Sq can move to
   --  that are durably safe: empty, not attacked by the opponent, and not
   --  a near-term enemy pawn push away from being attacked.
   function Durable_Mobility (Sq : Integer; Mover_White : Boolean) return Integer
   is
      N : Integer := 0;
   begin
      for D in 1 .. 64 loop
         if D /= Sq and then Pvalidade.Tabuleiro (D) = 0
           and then Pvalidade.Validade (Sq, D)
           and then not Move_Validation.Is_Square_Attacked (D, not Mover_White)
           and then not Pawn_Push_Threatens (D, not Mover_White)
         then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Durable_Mobility;

   function Improved_Minor_Retreat (From, To : Integer) return Integer is
      Piece        : constant Integer := Pvalidade.Tabuleiro (From);
      Mover_White  : constant Boolean := Piece > 0;
      Best_Sq      : Integer := To;
      Best_Mob     : Integer;
      Best_Cent    : Integer;
      Saved_T      : Integer;
      Mob          : Integer;
   begin
      --  Only a minor piece, only a flight, only a quiet destination.
      if (abs Piece /= 3 and then abs Piece /= 4)
        or else not Move_Validation.Is_Square_Attacked (From, not Mover_White)
        or else Pvalidade.Tabuleiro (To) /= 0
      then
         return To;
      end if;

      --  Baseline: the legacy's own choice, scored on the post-move board.
      Apply_Trial (From, To, Saved_T);
      Best_Mob  := Durable_Mobility (To, Mover_White);
      Undo_Trial (From, To, Piece, Saved_T);
      Best_Cent := Centrality (To);

      for D in 1 .. 64 loop
         if D /= From and then D /= To and then Pvalidade.Tabuleiro (D) = 0
           and then Pvalidade.Validade (From, D)
         then
            Apply_Trial (From, D, Saved_T);
            --  Candidate must be legal (not leaving the mover's own king
            --  in check -- the piece may be pinned) AND materially safe
            --  (not attacked at all on arrival -- deliberately
            --  conservative). The legacy cascade applied its own
            --  king-exposure filter to the move it chose; a substitute
            --  square must clear the same bar independently.
            if not Move_Validation.Is_In_Check (Mover_White)
              and then not Move_Validation.Is_Square_Attacked (D, not Mover_White)
            then
               Mob := Durable_Mobility (D, Mover_White);
               if Mob > Best_Mob
                 or else (Mob = Best_Mob and then Centrality (D) > Best_Cent)
               then
                  Best_Sq   := D;
                  Best_Mob  := Mob;
                  Best_Cent := Centrality (D);
               end if;
            end if;
            Undo_Trial (From, D, Piece, Saved_T);
         end if;
      end loop;
      return Best_Sq;
   end Improved_Minor_Retreat;

end Search_Integration;
