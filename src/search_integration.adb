with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Pvalidade;
with Move_Validation;
with BCH_Hash;
with TT_Table;
with Time_Management;
with Move_Gen;
with Eval_Terms;

package body Search_Integration is

   ------------------------------------------------------------------
   --  Configuration
   ------------------------------------------------------------------

   type Config_Record is record
      Contempt_Cp : Integer := Eval_Terms.Default_Contempt_Cp;  --  Contempt value for draw evaluation (centipawns)
   end record;

   Config : Config_Record;

   ------------------------------------------------------------------
   --  Game history / draw rules
   ------------------------------------------------------------------

   Side_To_Move_White : Boolean := True;

   procedure Reset_Game is
   begin
      History_Count := 0;
      Fifty_Move_Counter := 0;
      Side_To_Move_White := True;
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

   function Is_Current_Position_Checkmate return Boolean is
      Legal : Move_Gen.Move_List;
   begin
      if not Move_Validation.Is_In_Check (Side_To_Move_White) then
         return False;
      end if;
      Move_Gen.Generate_Legal_Moves (Side_To_Move_White, Legal);
      return Legal.N = 0;
   end Is_Current_Position_Checkmate;

   function Current_Repetition_Count return Natural is
      Total        : Natural := 0;
      Current_Hash : Hash_Key;
   begin
      if History_Count = 0 then
         return 0;
      end if;

      Current_Hash := History (History_Count);
      --  Positions before the last irreversible move cannot recur; scan only
      --  the reversible suffix.
      for I in Integer'Max (1, History_Count - Fifty_Move_Counter) .. History_Count loop
         if History (I) = Current_Hash then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Current_Repetition_Count;

   function Is_Threefold_Repetition return Boolean is
   begin
      --  FIDE Article 9.2: at least 3 occurrences including current position;
      --  checkmate (Article 5.2.1) ends the game immediately on the board.
      if Current_Repetition_Count < 3 then
         return False;
      end if;
      return not Is_Current_Position_Checkmate;
   end Is_Threefold_Repetition;

   function Is_Fivefold_Repetition return Boolean is
   begin
      --  FIDE Article 9.6.1: mandatory draw at 5+ occurrences unless checkmate.
      if Current_Repetition_Count < 5 then
         return False;
      end if;
      return not Is_Current_Position_Checkmate;
   end Is_Fivefold_Repetition;

   function Is_Fifty_Move_Rule return Boolean is
   begin
      if Fifty_Move_Counter < 100 then
         return False;
      end if;
      --  FIDE Article 5.2.1 / 9.3: checkmate takes precedence over 50-move claim.
      return not Is_Current_Position_Checkmate;
   end Is_Fifty_Move_Rule;

   function Is_Seventy_Five_Move_Rule return Boolean is
   begin
      if Fifty_Move_Counter < 150 then
         return False;
      end if;
      --  FIDE Article 9.6.2: mandatory draw unless the 150th half-move gave mate.
      return not Is_Current_Position_Checkmate;
   end Is_Seventy_Five_Move_Rule;

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

   function Root_Position_Key (White_To_Move : Boolean) return TT_Types.Hash_Key is
   begin
      return BCH_Hash.Compute_Hash
        (White_To_Move   => White_To_Move,
         Ep_Square       => Hash_Ep_For_Repetition
                              (White_To_Move, Move_Validation.En_Passant_Sq),
         Castling_Rights => Move_Validation.Castling_Rights_Bits);
   end Root_Position_Key;

   function Repetition_Count_After
     (White_To_Move : Boolean;
      From_Sq, To_Sq, Promo : Integer) return Integer
   is
      Saved_Board : Pvalidade.Board_Array;
      Saved_Ep    : constant Integer := Move_Validation.En_Passant_Sq;
      Saved_WK    : constant Boolean := Move_Validation.White_Castling_K;
      Saved_WQ    : constant Boolean := Move_Validation.White_Castling_Q;
      Saved_BK    : constant Boolean := Move_Validation.Black_Castling_K;
      Saved_BQ    : constant Boolean := Move_Validation.Black_Castling_Q;
      Moved_Piece : Integer;
      New_Key     : TT_Types.Hash_Key;
      Count       : Integer := 0;
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return 0;
      end if;
      Saved_Board := Pvalidade.Tabuleiro;
      Moved_Piece := Pvalidade.Tabuleiro (From_Sq);
      if Moved_Piece = 0 then
         return 0;
      end if;

      declare
         FR : constant Integer := Move_Validation.Rank_Of (From_Sq);
         TR : constant Integer := Move_Validation.Rank_Of (To_Sq);
         FF : constant Integer := Move_Validation.File_Of (From_Sq);
         TF : constant Integer := Move_Validation.File_Of (To_Sq);
         Is_Pawn   : constant Boolean := abs Moved_Piece = 1;
         Is_Castle : constant Boolean :=
           abs Moved_Piece = 999 and then abs (TF - FF) = 2;
         Is_EP     : constant Boolean :=
           Is_Pawn and then To_Sq = Saved_Ep and then Saved_Ep /= 0;
      begin
         if Is_EP then
            Pvalidade.Tabuleiro (Move_Validation.Square_Of (FR, TF)) := 0;
         end if;
         if Is_Castle then
            Move_Validation.Apply_Castle_Rook_Move
              (White_To_Move => White_To_Move,
               Kingside      => TF > FF);
         end if;

         if Promo /= 0 then
            Pvalidade.Tabuleiro (To_Sq) := (if White_To_Move then Promo else -Promo);
         else
            Pvalidade.Tabuleiro (To_Sq) := Moved_Piece;
         end if;
         Pvalidade.Tabuleiro (From_Sq) := 0;

         Move_Validation.Update_Rights_After_Move (From_Sq, To_Sq, Moved_Piece);

         if Is_Pawn and then abs (TR - FR) = 2 then
            Move_Validation.En_Passant_Sq :=
              Move_Validation.Square_Of ((FR + TR) / 2, FF);
         else
            Move_Validation.En_Passant_Sq := 0;
         end if;

         New_Key := BCH_Hash.Compute_Hash
           (White_To_Move   => not White_To_Move,
            Ep_Square       => Hash_Ep_For_Repetition
                                 (not White_To_Move, Move_Validation.En_Passant_Sq),
            Castling_Rights => Move_Validation.Castling_Rights_Bits);
      end;

      for I in Integer'Max (1, History_Count - Fifty_Move_Counter) .. History_Count loop
         if TT_Types."=" (History (I), New_Key) then
            Count := Count + 1;
         end if;
      end loop;

      --  Restore state
      Pvalidade.Tabuleiro              := Saved_Board;
      Move_Validation.En_Passant_Sq    := Saved_Ep;
      Move_Validation.White_Castling_K := Saved_WK;
      Move_Validation.White_Castling_Q := Saved_WQ;
      Move_Validation.Black_Castling_K := Saved_BK;
      Move_Validation.Black_Castling_Q := Saved_BQ;

      return Count;
   exception
      when others =>
         Pvalidade.Tabuleiro              := Saved_Board;
         Move_Validation.En_Passant_Sq    := Saved_Ep;
         Move_Validation.White_Castling_K := Saved_WK;
         Move_Validation.White_Castling_Q := Saved_WQ;
         Move_Validation.Black_Castling_K := Saved_BK;
         Move_Validation.Black_Castling_Q := Saved_BQ;
         return 0;
   end Repetition_Count_After;

   function Is_Insufficient_Material return Boolean is
      --  FIDE Article 5.2.2 Dead Position check: K-K, single KN-K, or kings
      --  with arbitrary bishops strictly on the same square colour.
      White_Knights : Integer := 0;
      Black_Knights : Integer := 0;
      Seen_Color_0  : Boolean := False;
      Seen_Color_1  : Boolean := False;
   begin
      for I in 1 .. 64 loop
         case Pvalidade.Tabuleiro (I) is
            when 0 | 999 | -999 =>
               null;
            when 4 =>
               White_Knights := White_Knights + 1;
            when -4 =>
               Black_Knights := Black_Knights + 1;
            when 3 | -3 =>
               if (Move_Validation.Rank_Of (I) + Move_Validation.File_Of (I)) mod 2 = 0 then
                  Seen_Color_0 := True;
               else
                  Seen_Color_1 := True;
               end if;
            when others =>
               return False;
         end case;
      end loop;

      if White_Knights + Black_Knights > 0 then
         --  Only KN vs K (zero bishops) is a dead position; KNN vs K, KN vs KN,
         --  and KBN vs K admit legal helpmate constructions.
         return (White_Knights + Black_Knights = 1)
           and then not Seen_Color_0
           and then not Seen_Color_1;
      end if;

      return not (Seen_Color_0 and then Seen_Color_1);
   end Is_Insufficient_Material;

   function Is_Draw return Boolean is
   begin
      return Is_Fivefold_Repetition
        or else Is_Seventy_Five_Move_Rule
        or else Is_Threefold_Repetition
        or else Is_Fifty_Move_Rule
        or else Is_Insufficient_Material;
   end Is_Draw;

   ----------------------------------------------------------------------------
   --  CONFIGURABLE HEURISTIC OPTION MANAGEMENT
   ----------------------------------------------------------------------------
   procedure Set_Heuristic_Option (Name : String; Value : Integer) is
      Low_Name : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      if Low_Name = "castle_bonus" then
         Castle_Bonus_Weight := Value;
      elsif Low_Name = "development_bonus" then
         Development_Bonus_Weight := Value;
      elsif Low_Name = "queen_tempo_penalty" then
         Queen_Tempo_Penalty_Weight := Value;
      elsif Low_Name = "central_pawn_bonus" then
         Central_Pawn_Bonus_Weight := Value;
      elsif Low_Name = "defended_piece_bonus" then
         Defended_Piece_Bonus_Weight := Value;
      elsif Low_Name = "mobility_weight" then
         Mobility_Bonus_Weight := Value;
      end if;
   end Set_Heuristic_Option;

   ----------------------------------------------------------------------------
   --  GUARD NETWORK (COUNT_PROTECTIONS) & MOBILITY EVALUATIONS
   ----------------------------------------------------------------------------
   function Count_Protections (Side_White : Boolean) return Integer is
      Count : Integer := 0;
      Pawn_Val   : constant Integer := (if Side_White then 1 else -1);
      Knight_Val : constant Integer := (if Side_White then 4 else -4);
      Bishop_Val : constant Integer := (if Side_White then 3 else -3);
      Rook_Val   : constant Integer := (if Side_White then 7 else -7);
      Queen_Val  : constant Integer := (if Side_White then 20 else -20);
      King_Val   : constant Integer := (if Side_White then 999 else -999);

      Knight_Deltas : constant array (1 .. 8, 1 .. 2) of Integer :=
        [[1, 2], [2, 1], [-1, 2], [-2, 1],
         [1, -2], [2, -1], [-1, -2], [-2, -1]];
      Diag_Dirs : constant array (1 .. 4, 1 .. 2) of Integer :=
        [[1, 1], [1, -1], [-1, 1], [-1, -1]];
      Orth_Dirs : constant array (1 .. 4, 1 .. 2) of Integer :=
        [[1, 0], [-1, 0], [0, 1], [0, -1]];

      function Is_Square_Defended (Sq : Integer) return Boolean is
         R : constant Integer := Move_Validation.Rank_Of (Sq);
         F : constant Integer := Move_Validation.File_Of (Sq);
      begin
         -- 1. Pawn protection
         if Side_White then
            if R > 1 then
               if F > 1 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R - 1, F - 1)) = Pawn_Val then
                  return True;
               end if;
               if F < 8 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R - 1, F + 1)) = Pawn_Val then
                  return True;
               end if;
            end if;
         else
            if R < 8 then
               if F > 1 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R + 1, F - 1)) = Pawn_Val then
                  return True;
               end if;
               if F < 8 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R + 1, F + 1)) = Pawn_Val then
                  return True;
               end if;
            end if;
         end if;

         -- 2. Knight protection
         for I in 1 .. 8 loop
            declare
               NR : constant Integer := R + Knight_Deltas (I, 1);
               NF : constant Integer := F + Knight_Deltas (I, 2);
            begin
               if NR in 1 .. 8 and then NF in 1 .. 8 then
                  if Pvalidade.Tabuleiro (Move_Validation.Square_Of (NR, NF)) = Knight_Val then
                     return True;
                  end if;
               end if;
            end;
         end loop;

         -- 3. Bishop / Queen diagonal protection
         for I in 1 .. 4 loop
            declare
               DR : constant Integer := Diag_Dirs (I, 1);
               DF : constant Integer := Diag_Dirs (I, 2);
               CR : Integer := R + DR;
               CF : Integer := F + DF;
            begin
               while CR in 1 .. 8 and then CF in 1 .. 8 loop
                  declare
                     CSq : constant Integer := Move_Validation.Square_Of (CR, CF);
                     P   : constant Integer := Pvalidade.Tabuleiro (CSq);
                  begin
                     if P /= 0 then
                        if P = Bishop_Val or else P = Queen_Val then
                           return True;
                        elsif P = King_Val and then CR = R + DR and then CF = F + DF then
                           return True;
                        end if;
                        exit;
                     end if;
                  end;
                  CR := CR + DR;
                  CF := CF + DF;
               end loop;
            end;
         end loop;

         -- 4. Rook / Queen orthogonal protection
         for I in 1 .. 4 loop
            declare
               DR : constant Integer := Orth_Dirs (I, 1);
               DF : constant Integer := Orth_Dirs (I, 2);
               CR : Integer := R + DR;
               CF : Integer := F + DF;
            begin
               while CR in 1 .. 8 and then CF in 1 .. 8 loop
                  declare
                     CSq : constant Integer := Move_Validation.Square_Of (CR, CF);
                     P   : constant Integer := Pvalidade.Tabuleiro (CSq);
                  begin
                     if P /= 0 then
                        if P = Rook_Val or else P = Queen_Val then
                           return True;
                        elsif P = King_Val and then CR = R + DR and then CF = F + DF then
                           return True;
                        end if;
                        exit;
                     end if;
                  end;
                  CR := CR + DR;
                  CF := CF + DF;
               end loop;
            end;
         end loop;

         return False;
      end Is_Square_Defended;

   begin
      for Sq in 1 .. 64 loop
         declare
            P : constant Integer := Pvalidade.Tabuleiro (Sq);
         begin
            if (Side_White and then P > 0) or else (not Side_White and then P < 0) then
               if Is_Square_Defended (Sq) then
                  Count := Count + 1;
               end if;
            end if;
         end;
      end loop;
      return Count;
   end Count_Protections;

   function Compute_Mobility (Side_White : Boolean) return Integer is
      Total_Mobility : Integer := 0;
      Bishop_Val     : constant Integer := (if Side_White then 3 else -3);
      Rook_Val       : constant Integer := (if Side_White then 7 else -7);
      Queen_Val      : constant Integer := (if Side_White then 20 else -20);

      Diag_Dirs : constant array (1 .. 4, 1 .. 2) of Integer :=
        [[1, 1], [1, -1], [-1, 1], [-1, -1]];
      Orth_Dirs : constant array (1 .. 4, 1 .. 2) of Integer :=
        [[1, 0], [-1, 0], [0, 1], [0, -1]];
   begin
      for Sq in 1 .. 64 loop
         declare
            P : constant Integer := Pvalidade.Tabuleiro (Sq);
            R : constant Integer := Move_Validation.Rank_Of (Sq);
            F : constant Integer := Move_Validation.File_Of (Sq);
         begin
            if P = Bishop_Val or else P = Queen_Val then
               for I in 1 .. 4 loop
                  declare
                     DR : constant Integer := Diag_Dirs (I, 1);
                     DF : constant Integer := Diag_Dirs (I, 2);
                     CR : Integer := R + DR;
                     CF : Integer := F + DF;
                  begin
                     while CR in 1 .. 8 and then CF in 1 .. 8 loop
                        declare
                           CSq : constant Integer := Move_Validation.Square_Of (CR, CF);
                           CP  : constant Integer := Pvalidade.Tabuleiro (CSq);
                        begin
                           if CP = 0 then
                              Total_Mobility := Total_Mobility + 1;
                           else
                              if (Side_White and then CP < 0) or else (not Side_White and then CP > 0) then
                                 Total_Mobility := Total_Mobility + 1;
                              end if;
                              exit;
                           end if;
                        end;
                        CR := CR + DR;
                        CF := CF + DF;
                     end loop;
                  end;
               end loop;
            end if;

            if P = Rook_Val or else P = Queen_Val then
               for I in 1 .. 4 loop
                  declare
                     DR : constant Integer := Orth_Dirs (I, 1);
                     DF : constant Integer := Orth_Dirs (I, 2);
                     CR : Integer := R + DR;
                     CF : Integer := F + DF;
                  begin
                     while CR in 1 .. 8 and then CF in 1 .. 8 loop
                        declare
                           CSq : constant Integer := Move_Validation.Square_Of (CR, CF);
                           CP  : constant Integer := Pvalidade.Tabuleiro (CSq);
                        begin
                           if CP = 0 then
                              Total_Mobility := Total_Mobility + 1;
                           else
                              if (Side_White and then CP < 0) or else (not Side_White and then CP > 0) then
                                 Total_Mobility := Total_Mobility + 1;
                              end if;
                              exit;
                           end if;
                        end;
                        CR := CR + DR;
                        CF := CF + DF;
                     end loop;
                  end;
               end loop;
            end if;
         end;
      end loop;
      return Total_Mobility;
   end Compute_Mobility;

   function Side_Guard_Bonus_Cp (Side_White : Boolean) return Integer is
      My_Prot  : constant Integer := Count_Protections (Side_White);
      Opp_Prot : constant Integer := Count_Protections (not Side_White);
   begin
      return (My_Prot - Opp_Prot) * Defended_Piece_Bonus_Weight / 10;
   end Side_Guard_Bonus_Cp;

   function Side_Mobility_Bonus_Cp (Side_White : Boolean) return Integer is
      My_Mob  : constant Integer := Compute_Mobility (Side_White);
      Opp_Mob : constant Integer := Compute_Mobility (not Side_White);
   begin
      return (My_Mob - Opp_Mob) * Mobility_Bonus_Weight / 10;
   end Side_Mobility_Bonus_Cp;

   ------------------------------------------------------------------
   --  FEN parsing
   ------------------------------------------------------------------

   function Try_Parse_FEN
     (FEN                     : String;
      White_To_Move           : in out Boolean;
      Check_Opponent_In_Check : Boolean := True) return Boolean is
      Rank       : Integer := 8;
      File       : Integer := 1;
      Idx        : Integer := FEN'First;
      Ch         : Character;
      Piece_Code : Integer;
      Half_Move  : Integer := 0;
      WK, WQ, BK, BQ : Boolean := False;
      EP_Sq      : Integer := 0;
      Local_White : Boolean := True;
      Board       : Pvalidade.Board_Array := [others => 0];
      White_Kings : Natural := 0;
      Black_Kings : Natural := 0;

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
            if Piece_Code = 999 then
               White_Kings := White_Kings + 1;
            elsif Piece_Code = -999 then
               Black_Kings := Black_Kings + 1;
            end if;
            Board (Move_Validation.Square_Of (Rank, File)) := Piece_Code;
            File := File + 1;
         end if;
         Idx := Idx + 1;
      end loop;
      if Idx > FEN'Last or else Rank /= 1 or else File /= 9 then
         return False;
      end if;
      if White_Kings /= 1 or else Black_Kings /= 1 then
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

      declare
         Saved_Board : constant Pvalidade.Board_Array := Pvalidade.Tabuleiro;
         Illegal_Opp_Check : Boolean := False;
      begin
         Pvalidade.Tabuleiro := Board;
         --  A legal UCI FEN cannot leave the side NOT to move with its king in check.
         if Check_Opponent_In_Check then
            Illegal_Opp_Check := Move_Validation.Is_In_Check (not Local_White);
         end if;
         if Illegal_Opp_Check then
            Pvalidade.Tabuleiro := Saved_Board;
            return False;
         end if;
      end;

      --  Board rewritten: the cascade's cached 64x64 geometry is stale.
      pprechess2.Invalidate_Cascade_Cache;
      History_Count := 0;
      Side_To_Move_White := Local_White;
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
      Parsed      : Boolean;
      Local_White : Boolean := True;
   begin
      Parsed := Try_Parse_FEN (FEN, Local_White, Check_Opponent_In_Check => False);
      White_To_Move := Local_White;
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
         Side_To_Move_White := not Expected_White_To_Move;
         --  Board changed: the cascade's cached 64x64 move geometry is stale.
         pprechess2.Invalidate_Cascade_Cache;
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
   --  Unified Evaluator & Reported Score (Phase 1)
   ------------------------------------------------------------------

   function Evaluate return Integer is
      Score : Integer := 0;
      Val   : Integer;
      P     : Integer;
   begin
      --  Material sum
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         case abs (P) is
            when 1      => Val := Eval_Terms.Pawn_Value_Cp;
            when 3      => Val := Eval_Terms.Bishop_Value_Cp;
            when 4      => Val := Eval_Terms.Knight_Value_Cp;
            when 7      => Val := Eval_Terms.Rook_Value_Cp;
            when 20     => Val := Eval_Terms.Queen_Value_Cp;
            when others => Val := 0; -- empty square or king
         end case;
         if P > 0 then
            Score := Score + Val;
         elsif P < 0 then
            Score := Score - Val;
         end if;
      end loop;

      --  Bishop-pair bonus (Phase 5: display-only)
      --  +30cp when a side has both bishops (White-relative)
      declare
         White_Bishops : Integer := 0;
         Black_Bishops : Integer := 0;
      begin
         for Sq in 1 .. 64 loop
            P := Pvalidade.Tabuleiro (Sq);
            if abs (P) = 3 then -- Bishop
               if P > 0 then
                  White_Bishops := White_Bishops + 1;
               elsif P < 0 then
                  Black_Bishops := Black_Bishops + 1;
               end if;
            end if;
         end loop;
         if White_Bishops >= 2 then
            Score := Score + Eval_Terms.Bishop_Pair_Bonus_Cp;
         end if;
         if Black_Bishops >= 2 then
            Score := Score - Eval_Terms.Bishop_Pair_Bonus_Cp;
         end if;
      end;

      --  Tapered piece-square tables (White-relative)
      --  The board is already mirrored to side-to-move perspective by the search.
      --  Pprechess2 PST tables are also from the engine's own perspective.
      --  Positional_Sum iterates Tabuleiro once and returns White-relative
      --  PST contribution in the same frame Material uses. Frame parity
      --  proof: Positional_Sum (White_Relative => True) performs the same
      --  per-square sign logic the previous inline loop did.
      Score := Score + Pprechess2.Positional_Sum (White_Relative => True);

      --  Phase 8 positional terms (Gate G9).  Each is White-relative and
      --  already interpolated between its own MG/EG tables by the shared
      --  PeSTO game phase, so it is a single addition here.
      Score := Score + Eval_Terms.Passed_Pawns;        -- G9 term 1
      Score := Score + Eval_Terms.Doubled_Isolated_Pawns;  -- G9 term 2
      Score := Score + Eval_Terms.Rook_Files;              -- G9 term 3
      Score := Score + Eval_Terms.King_Safety;             -- G9 term 5

      --  Phase P9 endgame overlay (general; N1-clean -- see the spec).
      --  Recognized forced draws collapse the score to 0 (rook-pawn
      --  corner draw). Otherwise add the attacker/defender geometry
      --  bonus for KQ-K / KR-K / opposite-colour KBB-K / KP-K.
      if Endgame_Is_Draw then
         --  Phase 6: Contempt-aware draw handling (default 0)
         --  The contempt value is configurable but defaults to 0 so
         --  existing behavior is numerically unchanged and tunable.
         return Config.Contempt_Cp;
      end if;
      return Score + Endgame_Bonus_Cp;
   end Evaluate;

   function Material_Score_Cp return Integer is
   begin
      return Evaluate;
   end Material_Score_Cp;

   ------------------------------------------------------------------
   --  UCI Score Formatting & Mate Bridge (Phase 2)
   ------------------------------------------------------------------

   function Signed_Mate_Plies_To_Moves (Score_Cp : Integer) return String is
      Plies : Integer;
      Moves : Integer;
   begin
      if Score_Cp >= Mate_Threshold then
         Plies := Mate_Value - Score_Cp;
         if Plies < 1 then
            Plies := 1;
         end if;
         Moves := (Plies + 1) / 2;
         return Ada.Strings.Fixed.Trim (Integer'Image (Moves), Ada.Strings.Left);
      elsif Score_Cp <= -Mate_Threshold then
         Plies := Mate_Value - abs (Score_Cp);
         if Plies < 1 then
            Plies := 1;
         end if;
         Moves := (Plies + 1) / 2;
         return "-" & Ada.Strings.Fixed.Trim (Integer'Image (Moves), Ada.Strings.Left);
      else
         return "0";
      end if;
   end Signed_Mate_Plies_To_Moves;

   function Score_To_UCI (Score_Cp : Integer) return String is
   begin
      if abs (Score_Cp) >= Mate_Threshold then
         return "score mate " & Signed_Mate_Plies_To_Moves (Score_Cp);
      else
         return "score cp " & Ada.Strings.Fixed.Trim (Integer'Image (Score_Cp), Ada.Strings.Left);
      end if;
   end Score_To_UCI;

   function Move_Delivers_Checkmate
     (White_To_Move : Boolean;
      From_Sq, To_Sq, Promo : Integer) return Boolean is
      Saved_Board : Pvalidade.Board_Array;
      Saved_WK    : constant Boolean := Move_Validation.White_Castling_K;
      Saved_WQ    : constant Boolean := Move_Validation.White_Castling_Q;
      Saved_BK    : constant Boolean := Move_Validation.Black_Castling_K;
      Saved_BQ    : constant Boolean := Move_Validation.Black_Castling_Q;
      Saved_Ep    : constant Integer := Move_Validation.En_Passant_Sq;
      Moved_Piece : Integer;
      Opp_White   : constant Boolean := not White_To_Move;
      Is_Mate     : Boolean := False;
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return False;
      end if;

      Moved_Piece := Pvalidade.Tabuleiro (From_Sq);
      if Moved_Piece = 0 then
         return False;
      end if;

      for Sq in 1 .. 64 loop
         Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
      end loop;

      Pvalidade.Tabuleiro (From_Sq) := 0;
      if Promo /= 0 then
         Pvalidade.Tabuleiro (To_Sq) := (if White_To_Move then Promo else -Promo);
      else
         Pvalidade.Tabuleiro (To_Sq) := Moved_Piece;
      end if;

      if abs Moved_Piece = 1 and then To_Sq = Saved_Ep and then Saved_Ep /= 0 then
         if White_To_Move then
            Pvalidade.Tabuleiro (To_Sq - 8) := 0;
         else
            Pvalidade.Tabuleiro (To_Sq + 8) := 0;
         end if;
      end if;

      if abs Moved_Piece = 999 and then abs (From_Sq - To_Sq) = 2 then
         Move_Validation.Apply_Castle_Rook_Move (White_To_Move, To_Sq > From_Sq);
      end if;

      Move_Validation.Update_Rights_After_Move (From_Sq, To_Sq, Moved_Piece);

      if Move_Validation.Is_In_Check (White_King => Opp_White) then
         declare
            Opp_Moves : Move_Gen.Move_List;
         begin
            Move_Gen.Generate_Legal_Moves (Opp_White, Opp_Moves);
            if Opp_Moves.N = 0 then
               Is_Mate := True;
            end if;
         end;
      end if;

      for Sq in 1 .. 64 loop
         Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
      end loop;
      Move_Validation.White_Castling_K := Saved_WK;
      Move_Validation.White_Castling_Q := Saved_WQ;
      Move_Validation.Black_Castling_K := Saved_BK;
      Move_Validation.Black_Castling_Q := Saved_BQ;
      Move_Validation.En_Passant_Sq    := Saved_Ep;

      return Is_Mate;
   exception
      when others =>
         for Sq in 1 .. 64 loop
            Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
         end loop;
         Move_Validation.White_Castling_K := Saved_WK;
         Move_Validation.White_Castling_Q := Saved_WQ;
         Move_Validation.Black_Castling_K := Saved_BK;
         Move_Validation.Black_Castling_Q := Saved_BQ;
         Move_Validation.En_Passant_Sq    := Saved_Ep;
         return False;
   end Move_Delivers_Checkmate;

   function Trimmed_Image (N : Long_Long_Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (N), Ada.Strings.Left);
   end Trimmed_Image;

   procedure Clear_PV is
   begin
      PV_Length := [others => 0];
   end Clear_PV;

   procedure Set_PV_Move (Ply : Natural; From_Sq, To_Sq, Promo : Integer) is
   begin
      if Ply <= Max_PV_Depth then
         PV_Table (Ply, 0) := (From_Sq => From_Sq, To_Sq => To_Sq, Prom => Promo);
         for I in 0 .. PV_Length (Ply + 1) - 1 loop
            if I + 1 <= Max_PV_Depth then
               PV_Table (Ply, I + 1) := PV_Table (Ply + 1, I);
            end if;
         end loop;
         PV_Length (Ply) := Natural'Min (Max_PV_Depth, PV_Length (Ply + 1) + 1);
      end if;
   end Set_PV_Move;

   procedure Report_PV (Depth, Seldepth, Score_Cp : Integer; PV : String;
                        Hashfull : Integer := -1) is
      Hash_Pm : constant Integer :=
        (if Hashfull >= 0 then Hashfull else TT_Table.Hash_Full_Permille);
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
         & " hashfull " & Ada.Strings.Fixed.Trim (Integer'Image (Hash_Pm), Ada.Strings.Left)
         & " " & Score_To_UCI (Score_Cp)
         & " pv " & PV);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
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
      Nodes   := TT_Types.Nodes_Searched;
      Score   := Evaluate;
      if Search_Is_Mirrored then
         Disp_From := Move_Validation.Mirror_Square (From_Sq);
         Disp_To   := Move_Validation.Mirror_Square (To_Sq);
      else
         Disp_From := From_Sq;
         Disp_To   := To_Sq;
      end if;

      declare
         White_Moving : constant Boolean := not Report_For_Black;
         Is_Promotion : constant Boolean :=
           abs Pvalidade.Tabuleiro (Disp_From) = 1
           and then (Move_Validation.Rank_Of (Disp_To) = 1 or else Move_Validation.Rank_Of (Disp_To) = 8);
         Promo_Code   : constant Integer := (if Is_Promotion then 20 else 0);
      begin
         if Move_Delivers_Checkmate (White_Moving, Disp_From, Disp_To, Promo_Code) then
            Score := Mate_Value - 1;
         elsif Report_For_Black then
            Score := -Score;
         end if;
      end;

      if Elapsed > 0 then
         Nps := (Nodes * 1000) / Elapsed;
      else
         Nps := Nodes * 1000;
      end if;

      declare
         Is_Promotion : constant Boolean :=
           abs Pvalidade.Tabuleiro (From_Sq) = 1
           and then (Move_Validation.Rank_Of (Disp_To) = 1 or else Move_Validation.Rank_Of (Disp_To) = 8);
         Move_Str : constant String := Move_Gen.Move_To_UCI
           ((From => Disp_From, To => Disp_To,
             Promo => (if Is_Promotion then 20 else 0)));
      begin
         --  depth 3: the main search is still the legacy engine's fixed
         --  3-ply structure (Segundo_Lance/Terceiro_Lance + Analize1/2/3),
         --  which chooses the move via the priority cascade in
         --  pprechess2.adb. seldepth 60: Quarto_Lance through
         --  Sexagesimo_Lance (plies 4-60) extend a targeted,
         --  minimax-shaped material-safety check 57 plies past the
         --  nominal search, alternating opponent reply / computer answer
         --  down to the ply-60 leaf -- the same way a real engine's
         --  seldepth exceeds its nominal depth during check/capture
         --  extensions. It is not a full 60-ply search (no mate/check
         --  detection past ply 3), so it is reported as seldepth rather
         --  than claimed as depth 60.
         --  In-Search TT Caching: store the root candidate before emitting
         --  the info line so the reported hashfull already includes it.
         declare
            Key : constant TT_Types.Hash_Key :=
              Root_Position_Key (not Report_For_Black);
         begin
            TT_Table.Store_TT
              (Key   => Key,
               Depth => 3,
               Score => Score_Type (Score),
               Flag  => TT_Types.Exact,
               Best  => (From_Sq => Disp_From, To_Sq => Disp_To, Prom => (if Is_Promotion then 20 else 0)));
         end;

         Ada.Text_IO.Put_Line
           ("info depth 3 seldepth 60 time " & Trimmed_Image (Elapsed)
            & " nodes " & Trimmed_Image (Nodes)
            & " nps " & Trimmed_Image (Nps)
            & " hashfull " & Ada.Strings.Fixed.Trim (Integer'Image (TT_Table.Hash_Full_Permille), Ada.Strings.Left)
            & " " & Score_To_UCI (Score)
            & " pv " & Move_Str);
         Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
      end;
   end Report_UCI;

   ------------------------------------------------------------------
   --  Root move selection (castling / en passant integration)
   ------------------------------------------------------------------

   procedure Flip_Board is
      Temp : array (1 .. 64) of Integer;
   begin
      --  The color frame changes: cached own/enemy geometry is stale.
      pprechess2.Invalidate_Cascade_Cache;
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

   --  Does Defender_White have ANY legal move (including castling and en-passant)?
   --  Task 3: Uses full FIDE legal move generator to prevent false checkmate reports.
   function Has_Any_Legal_Move (Defender_White : Boolean) return Boolean is
      List : Move_Gen.Move_List;
   begin
      Move_Gen.Generate_Legal_Moves (Defender_White, List);
      return List.N > 0;
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
      Proms : constant array (1 .. 4) of Integer := [20, 7, 3, 4];
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
      Proms : constant array (1 .. 4) of Integer := [20, 7, 3, 4];

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

   function Has_Opponent_Checking_Fork
     (White_To_Move : Boolean; Target_Sq : Integer) return Boolean
   is
      Opp : constant Boolean := not White_To_Move;
      Saved_T : Integer;
      In_Check : Boolean;
   begin
      for F in 1 .. 64 loop
         if Side_Piece (Pvalidade.Tabuleiro (F), Opp)
           and then abs Pvalidade.Tabuleiro (F) in 3 .. 20
           and then abs Pvalidade.Tabuleiro (F) /= 4
         then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  declare
                     P : constant Integer := Pvalidade.Tabuleiro (F);
                  begin
                     if See_Gain (Opp, F, T) >= 0 then
                        Apply_Trial (F, T, Saved_T);
                        if not Move_Validation.Is_In_Check (Opp) then
                           In_Check := Move_Validation.Is_In_Check (White_To_Move);
                           if In_Check then
                              declare
                                 Checker_Hanging : Boolean := False;
                                 Saved_Capper    : Integer;
                                 King_Sq         : constant Integer :=
                                   Move_Validation.Find_King (White_To_Move);
                              begin
                                 --  The checker may be the moved piece on T or, for a
                                 --  discovered check, a line piece elsewhere (e.g. a queen
                                 --  behind a knight that jumped off the file). Only a capture
                                 --  of an actual checking piece that resolves the check with
                                 --  SEE >= 0 refutes the "fork".
                                 Checker_Scan :
                                 for X_Sq in 1 .. 64 loop
                                    if Side_Piece (Pvalidade.Tabuleiro (X_Sq), Opp)
                                      and then King_Sq in 1 .. 64
                                      and then Pvalidade.Validade (X_Sq, King_Sq)
                                    then
                                       for C_Sq in 1 .. 64 loop
                                          if Side_Piece (Pvalidade.Tabuleiro (C_Sq), White_To_Move)
                                            and then Pvalidade.Validade (C_Sq, X_Sq)
                                          then
                                             declare
                                                Piece_C : constant Integer := Pvalidade.Tabuleiro (C_Sq);
                                             begin
                                                Apply_Trial (C_Sq, X_Sq, Saved_Capper);
                                                if not Move_Validation.Is_In_Check (White_To_Move) then
                                                   Undo_Trial (C_Sq, X_Sq, Piece_C, Saved_Capper);
                                                   if See_Gain (White_To_Move, C_Sq, X_Sq) >= 0 then
                                                      Checker_Hanging := True;
                                                      exit Checker_Scan;
                                                   end if;
                                                else
                                                   Undo_Trial (C_Sq, X_Sq, Piece_C, Saved_Capper);
                                                end if;
                                             end;
                                          end if;
                                       end loop;
                                    end if;
                                 end loop Checker_Scan;

                                 if not Checker_Hanging then
                                    if abs Saved_T in 7 .. 20
                                      and then Side_Piece (Saved_T, White_To_Move)
                                    then
                                       Undo_Trial (F, T, P, Saved_T);
                                       return True;
                                    end if;

                                    declare
                                       Target_Victim_Sq : Integer := 0;
                                    begin
                                       if (T /= Target_Sq)
                                         and then Pvalidade.Validade (T, Target_Sq)
                                         and then (not Move_Validation.Is_Square_Attacked (Target_Sq, By_White => White_To_Move)
                                                   or else See_Gain (Opp, T, Target_Sq) > 0)
                                       then
                                          Target_Victim_Sq := Target_Sq;
                                       else
                                          for Sq in 1 .. 64 loop
                                             if Sq /= T
                                               and then Side_Piece (Pvalidade.Tabuleiro (Sq), White_To_Move)
                                               and then abs Pvalidade.Tabuleiro (Sq) in 7 .. 20
                                               and then Pvalidade.Validade (T, Sq)
                                               and then (not Move_Validation.Is_Square_Attacked (Sq, By_White => White_To_Move)
                                                         or else See_Gain (Opp, T, Sq) > 0)
                                             then
                                                Target_Victim_Sq := Sq;
                                                exit;
                                             end if;
                                          end loop;
                                       end if;

                                       if Target_Victim_Sq /= 0 then
                                          declare
                                             Fork_Refuted : Boolean := False;
                                             Saved_R      : Integer;
                                          begin
                                             for RF in 1 .. 64 loop
                                                if Side_Piece (Pvalidade.Tabuleiro (RF), White_To_Move) then
                                                   for RT in 1 .. 64 loop
                                                      if Pvalidade.Validade (RF, RT) then
                                                         declare
                                                            RP : constant Integer := Pvalidade.Tabuleiro (RF);
                                                         begin
                                                            Apply_Trial (RF, RT, Saved_R);
                                                            if not Move_Validation.Is_In_Check (White_To_Move) then
                                                               if not Pvalidade.Validade (T, Target_Victim_Sq)
                                                                 or else (Move_Validation.Is_Square_Attacked (Target_Victim_Sq, By_White => White_To_Move)
                                                                          and then See_Gain (Opp, T, Target_Victim_Sq) <= 0)
                                                               then
                                                                  Fork_Refuted := True;
                                                               end if;
                                                            end if;
                                                            Undo_Trial (RF, RT, RP, Saved_R);
                                                            exit when Fork_Refuted;
                                                         end;
                                                      end if;
                                                   end loop;
                                                end if;
                                                exit when Fork_Refuted;
                                             end loop;

                                             if not Fork_Refuted then
                                                Undo_Trial (F, T, P, Saved_T);
                                                return True;
                                             end if;
                                          end;
                                       end if;
                                    end;

                                    --  Detect absolute skewer: ray through King attacking piece behind it
                                    declare
                                       K_Sq : constant Integer := Move_Validation.Find_King (White_To_Move);
                                    begin
                                       if K_Sq /= 0
                                         and then abs P in 3 | 7 | 20
                                         and then Pvalidade.Validade (T, K_Sq)
                                       then
                                          declare
                                             TR : constant Integer := Move_Validation.Rank_Of (T);
                                             TF : constant Integer := Move_Validation.File_Of (T);
                                             KR : constant Integer := Move_Validation.Rank_Of (K_Sq);
                                             KF : constant Integer := Move_Validation.File_Of (K_Sq);
                                             DR : constant Integer := (if KR > TR then 1 elsif KR < TR then -1 else 0);
                                             DF : constant Integer := (if KF > TF then 1 elsif KF < TF then -1 else 0);
                                             SR : Integer := KR + DR;
                                             SF : Integer := KF + DF;
                                             Behind_Sq : Integer;
                                             Behind_P  : Integer;
                                          begin
                                             while SR in 1 .. 8 and then SF in 1 .. 8 loop
                                                Behind_Sq := Move_Validation.Square_Of (SR, SF);
                                                Behind_P  := Pvalidade.Tabuleiro (Behind_Sq);
                                                if Behind_P /= 0 then
                                                   if Side_Piece (Behind_P, White_To_Move)
                                                     and then (abs Behind_P in 7 .. 20
                                                               or else Behind_Sq = Target_Sq)
                                                   then
                                                      --  A true absolute skewer requires that the check cannot
                                                      --  be blocked by interposition or the checking piece captured.
                                                      declare
                                                         Skewer_Refuted : Boolean := False;
                                                         Saved_R        : Integer;
                                                      begin
                                                         for RF in 1 .. 64 loop
                                                            if Side_Piece (Pvalidade.Tabuleiro (RF), White_To_Move) then
                                                               for RT in 1 .. 64 loop
                                                                  if Pvalidade.Validade (RF, RT) then
                                                                     declare
                                                                        RP : constant Integer := Pvalidade.Tabuleiro (RF);
                                                                     begin
                                                                        Apply_Trial (RF, RT, Saved_R);
                                                                        if not Move_Validation.Is_In_Check (White_To_Move) then
                                                                           if not Pvalidade.Validade (T, K_Sq) then
                                                                              Skewer_Refuted := True;
                                                                           end if;
                                                                        end if;
                                                                        Undo_Trial (RF, RT, RP, Saved_R);
                                                                        exit when Skewer_Refuted;
                                                                     end;
                                                                  end if;
                                                               end loop;
                                                            end if;
                                                            exit when Skewer_Refuted;
                                                         end loop;

                                                         if not Skewer_Refuted then
                                                            Undo_Trial (F, T, P, Saved_T);
                                                            return True;
                                                         end if;
                                                      end;
                                                   end if;
                                                   exit;
                                                end if;
                                                SR := SR + DR;
                                                SF := SF + DF;
                                             end loop;
                                          end;
                                       end if;
                                    end;
                                 end if;
                              end;
                           end if;
                           Undo_Trial (F, T, P, Saved_T);
                        else
                           Undo_Trial (F, T, P, Saved_T);
                        end if;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Opponent_Checking_Fork;

   ----------------------------------------------------------------------------
   --  HAS_OPPONENT_DOUBLE_ATTACK
   --  Checks whether the opponent has an available move that lands safely and
   --  simultaneously attacks two friendly pieces (at least one being minor/major
   --  or king), with Target_Sq as one of the targets when Target_Sq /= 0.
   ----------------------------------------------------------------------------
   --  Excludes Except_Sq (when /= 0) from second-target & x-ray target scans.
   function Has_Opponent_Double_Attack
     (White_To_Move : Boolean;
      Target_Sq     : Integer := 0;
      Except_Sq     : Integer := 0) return Boolean
   is
      Opp            : constant Boolean := not White_To_Move;
      Own_Sign       : constant Integer := (if White_To_Move then 1 else -1);
      Saved_T        : Integer;
      Piece_F        : Integer;
      Att_Val        : Integer;
      Attacks_Target : Boolean;
      Threat_Count   : Natural;

      function Destination_Hangs (Target : Integer) return Boolean is
      begin
         for S in 1 .. 64 loop
            if Side_Piece (Pvalidade.Tabuleiro (S), White_To_Move) then
               if Pvalidade.Validade (S, Target)
                 and then See_Gain (White_To_Move, S, Target) > 100
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Destination_Hangs;
   begin
      for F in 1 .. 64 loop
         Piece_F := Pvalidade.Tabuleiro (F);
         if Side_Piece (Piece_F, Opp) then
            Att_Val := Raw_Piece_Value_Cp (abs Piece_F);
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  if See_Gain (Opp, F, T) >= 0 then
                     Apply_Trial (F, T, Saved_T);
                     if not Move_Validation.Is_In_Check (Opp)
                       and then not Destination_Hangs (T)
                     then
                        Attacks_Target := (Target_Sq = 0)
                          or else (Pvalidade.Validade (T, Target_Sq)
                                   and then See_Gain (Opp, T, Target_Sq) >= -50);
                        if Attacks_Target then
                           Threat_Count := (if Target_Sq /= 0 then 1 else 0);
                           for Sq in 1 .. 64 loop
                              if Sq /= Target_Sq
                                and then Sq /= Except_Sq
                                and then Pvalidade.Tabuleiro (Sq) * Own_Sign > 0
                                and then Pvalidade.Validade (T, Sq)
                              then
                                 declare
                                    Vic_Val : constant Integer :=
                                      Raw_Piece_Value_Cp (abs Pvalidade.Tabuleiro (Sq));
                                    Target_Is_Piece : constant Boolean :=
                                      abs Pvalidade.Tabuleiro (Sq) in 3 .. 999;
                                 begin
                                    if Target_Is_Piece and then Vic_Val > Att_Val then
                                       Threat_Count := Threat_Count + 1;
                                    elsif Target_Is_Piece and then Vic_Val >= Att_Val
                                      and then See_Gain (Opp, T, Sq) >= 0
                                    then
                                       Threat_Count := Threat_Count + 1;
                                    elsif abs Pvalidade.Tabuleiro (Sq) = 999 then
                                       Threat_Count := Threat_Count + 1;
                                    elsif abs Piece_F in 5 .. 20
                                      and then See_Gain (Opp, T, Sq) > 0
                                    then
                                       Threat_Count := Threat_Count + 1;
                                    end if;

                                    if abs Pvalidade.Tabuleiro (Sq) = 20
                                      and then abs Piece_F in 3 .. 20
                                    then
                                       declare
                                          Saved_Q : constant Integer := Pvalidade.Tabuleiro (Sq);
                                       begin
                                          Pvalidade.Tabuleiro (Sq) := 0;
                                          for Rear_Sq in 1 .. 64 loop
                                             if Rear_Sq /= Sq
                                               and then Rear_Sq /= Except_Sq
                                               and then Pvalidade.Tabuleiro (Rear_Sq) * Own_Sign > 0
                                               and then abs Pvalidade.Tabuleiro (Rear_Sq) in 3 .. 999
                                               and then Pvalidade.Validade (T, Rear_Sq)
                                             then
                                                Threat_Count := Threat_Count + 1;
                                                exit;
                                             end if;
                                          end loop;
                                          Pvalidade.Tabuleiro (Sq) := Saved_Q;
                                       end;
                                    end if;
                                 end;
                                 if Threat_Count >= 2 then
                                    exit;
                                 end if;
                              end if;
                           end loop;
                        else
                           Threat_Count := 0;
                        end if;
                        Undo_Trial (F, T, Piece_F, Saved_T);
                        if Threat_Count >= 2 then
                           return True;
                        end if;
                     else
                        Undo_Trial (F, T, Piece_F, Saved_T);
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Opponent_Double_Attack;

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

   function Is_Castling_Into_Open_File
     (White_To_Move : Boolean; F, T : Integer) return Boolean
   is
      Piece : constant Integer := Pvalidade.Tabuleiro (F);
   begin
      if abs Piece = 999 and then abs (T - F) = 2 then
         if Move_Validation.File_Of (T) = 7 then
            declare
               Opp_Rook_Code : constant Integer := (if White_To_Move then -7 else 7);
               Opp_Pawn_Code : constant Integer := (if White_To_Move then -1 else 1);
               Has_Opp_Rook  : Boolean := False;
               Has_Opp_Pawn  : Boolean := False;
            begin
               for R in 1 .. 8 loop
                  declare
                     Sq : constant Integer := Move_Validation.Square_Of (R, 8);
                  begin
                     if Pvalidade.Tabuleiro (Sq) = Opp_Rook_Code then
                        Has_Opp_Rook := True;
                     elsif Pvalidade.Tabuleiro (Sq) = Opp_Pawn_Code then
                        Has_Opp_Pawn := True;
                     end if;
                  end;
               end loop;
               if Has_Opp_Rook and then not Has_Opp_Pawn then
                  return True;
               end if;
            end;
         elsif Move_Validation.File_Of (T) = 3 then
            declare
               Own_Pawn_Code : constant Integer := (if White_To_Move then 1 else -1);
               Opp_Rook_Code : constant Integer := (if White_To_Move then -7 else 7);
               Opp_Pawn_Code : constant Integer := (if White_To_Move then -1 else 1);
               Has_Own_Pawn  : Boolean := False;
               Has_Opp_Rook  : Boolean := False;
               Has_Opp_Pawn  : Boolean := False;
            begin
               for R in 1 .. 8 loop
                  declare
                     Sq : constant Integer := Move_Validation.Square_Of (R, 3);
                     P  : constant Integer := Pvalidade.Tabuleiro (Sq);
                  begin
                     if P = Own_Pawn_Code then
                        Has_Own_Pawn := True;
                     elsif P = Opp_Rook_Code then
                        Has_Opp_Rook := True;
                     elsif P = Opp_Pawn_Code then
                        Has_Opp_Pawn := True;
                     end if;
                  end;
               end loop;
               if not Has_Own_Pawn and then (Has_Opp_Pawn or Has_Opp_Rook) then
                  return True;
               end if;
            end;
         end if;
      end if;
      return False;
   end Is_Castling_Into_Open_File;

   function Raw_Piece_Value_Cp (Code : Integer) return Integer is
   begin
      case abs Code is
         when 1      => return 100;
         when 4      => return 320;
         when 3      => return 330;
         when 7      => return 500;
         when 20     => return 900;
         when 999    => return 20000;
         when others => return 0;
      end case;
   end Raw_Piece_Value_Cp;

   function See_Gain
     (White_Captures : Boolean;
      From_Sq        : Integer;
      To_Sq          : Integer;
      Ep_Victim      : Integer := 0) return Integer
   is
      function Resolve_Ep_Victim return Integer is
      begin
         if Ep_Victim in 1 .. 64 then
            return Ep_Victim;
         end if;
         if Move_Validation.En_Passant_Sq /= 0
           and then To_Sq = Move_Validation.En_Passant_Sq
           and then From_Sq in 1 .. 64
           and then abs Pvalidade.Tabuleiro (From_Sq) = 1
           and then (if White_Captures then Pvalidade.Tabuleiro (From_Sq) > 0 else Pvalidade.Tabuleiro (From_Sq) < 0)
           and then Pvalidade.Tabuleiro (To_Sq) = 0
         then
            declare
               F_Rank : constant Integer := Move_Validation.Rank_Of (From_Sq);
               F_File : constant Integer := Move_Validation.File_Of (From_Sq);
               T_Rank : constant Integer := Move_Validation.Rank_Of (To_Sq);
               T_File : constant Integer := Move_Validation.File_Of (To_Sq);
               P_Code : constant Integer := (if White_Captures then 1 else -1);
            begin
               if T_Rank - F_Rank = (if White_Captures then 1 else -1)
                 and then abs (T_File - F_File) = 1
               then
                  declare
                     V_Sq : constant Integer := Move_Validation.Square_Of (F_Rank, T_File);
                  begin
                     if V_Sq in 1 .. 64
                       and then Pvalidade.Tabuleiro (V_Sq) = -P_Code
                     then
                        return V_Sq;
                     end if;
                  end;
               end if;
            end;
         end if;
         return 0;
      end Resolve_Ep_Victim;

      Effective_Ep_Victim : constant Integer := Resolve_Ep_Victim;
      Is_Ep    : constant Boolean := Effective_Ep_Victim in 1 .. 64;
      Cap      : constant Integer := (if From_Sq in 1 .. 64 then Pvalidade.Tabuleiro (From_Sq) else 0);
      Vic      : constant Integer := (if To_Sq in 1 .. 64 then Pvalidade.Tabuleiro (To_Sq) else 0);
      Ep_Piece : constant Integer := (if Is_Ep then Pvalidade.Tabuleiro (Effective_Ep_Victim) else 0);
      Own_Sign : constant Integer := (if White_Captures then 1 else -1);

      Captured_Value_0 : Integer := 0;
      Saved_Target     : Integer;
      R                : Integer;

      --  S-G9-1 (C3): every-attacker exchange walk with 6-ply depth cap
      function Best_Continuation (Side : Boolean; Depth : Natural) return Integer is
         Best     : Integer := 0;   --  stand-pat: decline every recapture
         P, Saved : Integer;
         Gain     : Integer;
      begin
         if Depth > 6 then
            return 0;
         end if;
         for Sq in 1 .. 64 loop
            P := Pvalidade.Tabuleiro (Sq);
            if Side_Piece (P, Side)
              and then Sq /= To_Sq
              and then Pvalidade.Validade (Sq, To_Sq)
            then
               declare
                  Queen_Sq : Integer := 0;
                  Opp      : constant Boolean := not Side;
                  Queen_Pre_Attacked : Boolean := False;
               begin
                  if abs P /= 20 then
                     for S in 1 .. 64 loop
                        if Pvalidade.Tabuleiro (S) = (if Side then 20 else -20) then
                           Queen_Sq := S;
                           exit;
                        end if;
                     end loop;
                     if Queen_Sq /= 0 and then Queen_Sq /= To_Sq then
                        declare
                           Saved_Tgt_Pre : constant Integer := Pvalidade.Tabuleiro (To_Sq);
                        begin
                           Pvalidade.Tabuleiro (To_Sq) := 0;
                           Queen_Pre_Attacked := Move_Validation.Is_Square_Attacked (Queen_Sq, By_White => Opp);
                           Pvalidade.Tabuleiro (To_Sq) := Saved_Tgt_Pre;
                        end;
                     end if;
                  end if;

                  Apply_Trial (Sq, To_Sq, Saved, Promote_To => 20);
                  if not Move_Validation.Is_In_Check (Side) then
                     Gain := Raw_Piece_Value_Cp (abs Saved);
                     --  Saved is what was standing on To_Sq: what this
                     --  capture wins. Promotion delta, matching ply 0.
                     if abs P = 1
                       and then (Move_Validation.Rank_Of (To_Sq) = 1
                                 or else Move_Validation.Rank_Of (To_Sq) = 8)
                     then
                        Gain := Gain + (900 - 100);
                     end if;

                     if Queen_Sq /= 0
                       and then (not Queen_Pre_Attacked)
                       and then Move_Validation.Is_Square_Attacked (Queen_Sq, By_White => Opp)
                       and then Gain < 900
                     then
                        --  Moving Sq reveals an attack on friendly Queen (relative pin);
                        --  recapture loses Queen for less than 900 cp and is refuted.
                        null;
                     else
                        Best := Integer'Max
                          (Best, Gain - Best_Continuation (not Side, Depth + 1));
                     end if;
                  end if;
                  Undo_Trial (Sq, To_Sq, P, Saved);
               end;
            end if;
         end loop;
         return Best;
      end Best_Continuation;

   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return 0;
      end if;

      if Is_Ep then
         --  En passant capture preconditions:
         if abs Cap /= 1 or else Cap * Own_Sign <= 0
           or else abs Ep_Piece /= 1 or else Ep_Piece * Own_Sign >= 0
           or else Vic /= 0
         then
            return 0;
         end if;

         --  Root capture ply 0 value is the captured pawn (+100 cp)
         Captured_Value_0 := Raw_Piece_Value_Cp (abs Ep_Piece);

         --  Apply EP root move onto the board
         Pvalidade.Tabuleiro (From_Sq)             := 0;
         Pvalidade.Tabuleiro (To_Sq)               := Cap;
         Pvalidade.Tabuleiro (Effective_Ep_Victim) := 0;

         --  Legality check: King cannot be in check (guards rank exposure)
         if Move_Validation.Is_In_Check (White_Captures) then
            --  Illegal EP move: restore board and return 0
            Pvalidade.Tabuleiro (From_Sq)             := Cap;
            Pvalidade.Tabuleiro (To_Sq)               := 0;
            Pvalidade.Tabuleiro (Effective_Ep_Victim) := Ep_Piece;
            return 0;
         end if;

      else
         --  Standard capture preconditions:
         if Cap * Own_Sign <= 0 or else Vic * Own_Sign >= 0 or else abs Vic >= 999 then
            return 0;
         end if;

         --  Initial capture (ply 0)
         Captured_Value_0 := Raw_Piece_Value_Cp (abs Vic);

         --  Pawn promotion value delta
         if abs Cap = 1 and then
           (Move_Validation.Rank_Of (To_Sq) = 1 or else Move_Validation.Rank_Of (To_Sq) = 8)
         then
            Captured_Value_0 := Captured_Value_0 + (900 - 100);
         end if;

         --  Apply root capture
         Apply_Trial (From_Sq, To_Sq, Saved_Target, Promote_To => 20);
      end if;

      --  S-G9-2 (C3): Recursive exchange sequence, every attacker per ply
      R := Best_Continuation (not White_Captures, 1);

      --  Unwind root capture
      if Is_Ep then
         Pvalidade.Tabuleiro (From_Sq)             := Cap;
         Pvalidade.Tabuleiro (To_Sq)               := 0;
         Pvalidade.Tabuleiro (Effective_Ep_Victim) := Ep_Piece;
      else
         Undo_Trial (From_Sq, To_Sq, Cap, Saved_Target);
      end if;

      return Captured_Value_0 - R;

   exception
      when others =>
         if Is_Ep then
            Pvalidade.Tabuleiro (From_Sq)             := Cap;
            Pvalidade.Tabuleiro (To_Sq)               := 0;
            Pvalidade.Tabuleiro (Effective_Ep_Victim) := Ep_Piece;
         else
            Undo_Trial (From_Sq, To_Sq, Cap, Saved_Target);
         end if;
         raise;
   end See_Gain;

   function Is_Flank_Gambit_Pawn_Offer
     (White_To_Move : Boolean;
      From_Sq       : Integer;
      To_Sq         : Integer) return Boolean
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      Cap_P      : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Vic_P      : constant Integer := Pvalidade.Tabuleiro (To_Sq);
      FF         : Integer;
      TF         : Integer;
      Opp_D_Sq   : Integer;
   begin
      if abs Cap_P /= 1 or else abs Vic_P /= 1 then
         return False;
      end if;

      FF := Move_Validation.File_Of (From_Sq);
      TF := Move_Validation.File_Of (To_Sq);

      --  Central d-pawn (file 4) capturing a flank c-pawn (file 3)
      if FF = 4 and then TF = 3 then
         --  Check if opponent has adjacent central pawn on d4 (White) or d5 (Black)
         Opp_D_Sq := Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 4);
         if Pvalidade.Tabuleiro (Opp_D_Sq) = -1 * Own_Sign then
            return True;
         end if;
      end if;

      return False;
   end Is_Flank_Gambit_Pawn_Offer;

   function Recapture_Preference
     (White_To_Move : Boolean; F, T : Integer) return Integer
   is
      P        : constant Integer := abs Pvalidade.Tabuleiro (F);
      FF       : constant Integer := Move_Validation.File_Of (F);
      TF       : constant Integer := Move_Validation.File_Of (T);
      TR       : constant Integer := Move_Validation.Rank_Of (T);
      Target_R : constant Integer := (if White_To_Move then 3 else 6);
      Target_F : constant Integer := 6; -- f-file
   begin
      --  Base tie-break is MVV-LVA (lower capturer preferred)
      --  Pawn=48, Knight=42, Bishop=44, Rook=40, Queen=10
      declare
         Base : Integer := 50 - P * 2;
      begin
         if TF = Target_F and then TR = Target_R then
            --  Recapturing on f3 (White) or f6 (Black)
            if P = 4 and then (FF = 8 or else FF = 1) then
               --  Knight on the rim (h5/h4 or a5/a4) recapturing to central f3/f6 post
               Base := Base + 100;
            elsif P = 1 and then (FF = 5 or else FF = 4) then
               --  Pawn from e-file capturing toward f3/f6 (creating doubled f-pawns)
               declare
                  Own_F_Pawn : constant Integer :=
                    Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 6);
               begin
                  if Pvalidade.Tabuleiro (Own_F_Pawn) = (if White_To_Move then 1 else -1) then
                     Base := Base - 50; -- Avoid creating doubled f-pawns
                  end if;
               end;
            end if;
         end if;
         return Base;
      end;
   end Recapture_Preference;

   procedure Best_Winning_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign  : constant Integer := (if White_To_Move then 1 else -1);
      Best_Gain : Integer := 0;
      Best_Pref : Integer := Integer'First;
      Saved_T   : Integer;
      Gain      : Integer;
      Pref      : Integer;
      Capturer  : Integer;
      Victim    : Integer;
      Legal     : Boolean;
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
                  if Gain > 0
                    and then not Is_Flank_Gambit_Pawn_Offer (White_To_Move, F, T)
                    and then not (abs Capturer >= 7
                                  and then abs Victim = 1
                                  and then Move_Validation.Is_Square_Attacked (T, By_White => not White_To_Move))
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check
                       (White_King => White_To_Move);
                     Undo_Trial (F, T, Capturer, Saved_T);
                     if Legal then
                        declare
                           Opp_Hang     : constant Integer := Max_Opponent_See_After (White_To_Move, F, T);
                           Threat_Bonus : constant Integer :=
                             (if Gain <= 100 and then Creates_Major_Threat (White_To_Move, F, T)
                              then 300 else 0);
                           Net          : constant Integer := (Gain + Threat_Bonus) - Opp_Hang;
                        begin
                           if Net > 0 then
                              Pref := Recapture_Preference (White_To_Move, F, T);
                              if Net > Best_Gain
                                or else (Net = Best_Gain and then Pref > Best_Pref)
                              then
                                 Best_Gain := Net;
                                 Best_Pref := Pref;
                                 From_Sq   := F;
                                 To_Sq     := T;
                                 Found     := True;
                              end if;
                           end if;
                        end;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      --  B-C7: Check own en-passant capture
      declare
         Ep_Sq : constant Integer := Move_Validation.En_Passant_Sq;
      begin
         if Ep_Sq /= 0 then
            declare
               Ep_Rank       : constant Integer := Move_Validation.Rank_Of (Ep_Sq);
               Ep_File       : constant Integer := Move_Validation.File_Of (Ep_Sq);
               Own_Pawn_Rank : constant Integer := (if White_To_Move then Ep_Rank - 1 else Ep_Rank + 1);
               Victim_Sq     : constant Integer :=
                 (if Own_Pawn_Rank in 1 .. 8
                  then Move_Validation.Square_Of (Own_Pawn_Rank, Ep_File)
                  else 0);
               Own_Pawn_Code : constant Integer := (if White_To_Move then 1 else -1);
               Saved_Vic     : Integer;
            begin
               if Victim_Sq /= 0
                 and then Pvalidade.Tabuleiro (Victim_Sq) = -Own_Pawn_Code
                 and then Pvalidade.Tabuleiro (Ep_Sq) = 0
               then
                  for D in -1 .. 1 loop
                     if D /= 0 and then Ep_File + D in 1 .. 8 then
                        declare
                           F : constant Integer :=
                             Move_Validation.Square_Of (Own_Pawn_Rank, Ep_File + D);
                        begin
                           if Pvalidade.Tabuleiro (F) = Own_Pawn_Code then
                              Saved_Vic := Pvalidade.Tabuleiro (Victim_Sq);
                              Pvalidade.Tabuleiro (F) := 0;
                              Pvalidade.Tabuleiro (Ep_Sq) := Own_Pawn_Code;
                              Pvalidade.Tabuleiro (Victim_Sq) := 0;
                              Legal := not Move_Validation.Is_In_Check (White_King => White_To_Move);
                              Pvalidade.Tabuleiro (Victim_Sq) := Saved_Vic;
                              Pvalidade.Tabuleiro (Ep_Sq) := 0;
                              Pvalidade.Tabuleiro (F) := Own_Pawn_Code;

                              if Legal then
                                 Gain := See_Gain (White_To_Move, F, Ep_Sq, Ep_Victim => Victim_Sq);
                                 if Gain > 0 then
                                    Pref := Recapture_Preference (White_To_Move, F, Ep_Sq);
                                    if Gain > Best_Gain
                                      or else (Gain = Best_Gain and then Pref > Best_Pref)
                                    then
                                       Best_Gain := Gain;
                                       Best_Pref := Pref;
                                       From_Sq   := F;
                                       To_Sq     := Ep_Sq;
                                       Found     := True;
                                    end if;
                                 end if;
                              end if;
                           end if;
                        end;
                     end if;
                  end loop;
               end if;
            end;
         end if;
      end;
   end Best_Winning_Capture;

   procedure Best_Non_Losing_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign  : constant Integer := (if White_To_Move then 1 else -1);
      Best_Gain : Integer := Integer'First;
      Best_Tie  : Integer := Integer'First;
      Saved_T   : Integer;
      Gain      : Integer;
      Capturer  : Integer;
      Victim    : Integer;
      Tie       : Integer;
      Legal     : Boolean;
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
                        Tie := Raw_Piece_Value_Cp (abs Victim)
                          - Raw_Piece_Value_Cp (abs Capturer)
                          + Recapture_Preference (White_To_Move, F, T);
                        if Gain > Best_Gain
                          or else (Gain = Best_Gain and then Tie > Best_Tie)
                        then
                           Best_Gain := Gain;
                           Best_Tie  := Tie;
                           From_Sq   := F;
                           To_Sq     := T;
                           Found     := True;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Non_Losing_Capture;

   --  Worst (highest) SEE gain the opponent has on the current board.
   function Max_Opponent_See
     (White_To_Move : Boolean;
      Except_Sq     : Integer := 0) return Integer
   is
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
               if T /= Except_Sq
                 and then Vic * Own_Sign > 0
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
                        --  900 cp is the largest legal non-king capture; the
                        --  exact maximum is already known, so stop scanning.
                        if Best >= 900 then
                           return Best;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end if;
      end loop;

      --  Check opponent quiet pawn promotion threat (rank 7 to 8 for White, rank 2 to 1 for Black)
      declare
         Opp_Pawn_Code : constant Integer := (if Opp then 1 else -1);
         Pawn_Rank     : constant Integer := (if Opp then 7 else 2);
         Promo_Rank    : constant Integer := (if Opp then 8 else 1);
      begin
         for Col in 1 .. 8 loop
            declare
               F : constant Integer := Move_Validation.Square_Of (Pawn_Rank, Col);
               T : constant Integer := Move_Validation.Square_Of (Promo_Rank, Col);
            begin
               if F /= 0 and then T /= 0 and then T /= Except_Sq
                 and then Pvalidade.Tabuleiro (F) = Opp_Pawn_Code
                 and then Pvalidade.Tabuleiro (T) = 0
                 and then Pvalidade.Validade (F, T)
               then
                  Apply_Trial (F, T, Saved_T, Promote_To => 20);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  if Legal then
                     declare
                        Def_Gain      : Integer := 0;
                        Best_Def_Gain : Integer := 0;
                        Promo_Gain    : Integer;
                     begin
                        --  Find defender's best legal capture against the promoted Queen
                        for Def_F in 1 .. 64 loop
                           if Pvalidade.Tabuleiro (Def_F) * Own_Sign > 0
                             and then Pvalidade.Validade (Def_F, T)
                           then
                              declare
                                 Saved_Cap   : constant Integer := Pvalidade.Tabuleiro (Def_F);
                                 Saved_Def_T : Integer;
                                 Def_Legal   : Boolean;
                              begin
                                 Apply_Trial (Def_F, T, Saved_Def_T);
                                 Def_Legal := not Move_Validation.Is_In_Check (White_To_Move);
                                 Undo_Trial (Def_F, T, Saved_Cap, Saved_Def_T);
                                 if Def_Legal then
                                    Def_Gain := See_Gain (White_To_Move, Def_F, T);
                                    if Def_Gain > Best_Def_Gain then
                                       Best_Def_Gain := Def_Gain;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end loop;

                        --  Net promotion gain: 800 cp (Queen 900 - Pawn 100) minus defender's net capture
                        Promo_Gain := 800 - Best_Def_Gain;
                        if Promo_Gain < 0 then
                           Promo_Gain := 0;
                        end if;
                        if Promo_Gain > Best then
                           Best := Promo_Gain;
                        end if;
                     end;
                  end if;
                  Undo_Trial (F, T, Opp_Pawn_Code, Saved_T);
               end if;
            end;
            --  800 cp (free queen promotion) is this branch's maximum; the
            --  capture loop above already covers the 900 cp maximum.
            exit when Best >= 800;
         end loop;
      end;

      --  B-C7: Check opponent en-passant threat
      declare
         Ep_Sq : constant Integer := Move_Validation.En_Passant_Sq;
      begin
         if Ep_Sq /= 0 then
            declare
               Ep_Rank       : constant Integer := Move_Validation.Rank_Of (Ep_Sq);
               Ep_File       : constant Integer := Move_Validation.File_Of (Ep_Sq);
               Opp_Pawn_Rank : constant Integer := (if Opp then Ep_Rank - 1 else Ep_Rank + 1);
               Victim_Sq     : constant Integer :=
                 (if Opp_Pawn_Rank in 1 .. 8
                  then Move_Validation.Square_Of (Opp_Pawn_Rank, Ep_File)
                  else 0);
               Opp_Pawn_Code : constant Integer := (if Opp then 1 else -1);
               Saved_Vic     : Integer;
            begin
               if Victim_Sq /= 0
                 and then Victim_Sq /= Except_Sq
                 and then Pvalidade.Tabuleiro (Victim_Sq) = -Opp_Pawn_Code
                 and then Pvalidade.Tabuleiro (Ep_Sq) = 0
               then
                  for D in -1 .. 1 loop
                     if D /= 0 and then Ep_File + D in 1 .. 8 then
                        declare
                           F : constant Integer :=
                             Move_Validation.Square_Of (Opp_Pawn_Rank, Ep_File + D);
                        begin
                           if Pvalidade.Tabuleiro (F) = Opp_Pawn_Code then
                              Saved_Vic := Pvalidade.Tabuleiro (Victim_Sq);
                              Pvalidade.Tabuleiro (F) := 0;
                              Pvalidade.Tabuleiro (Ep_Sq) := Opp_Pawn_Code;
                              Pvalidade.Tabuleiro (Victim_Sq) := 0;
                              Legal := not Move_Validation.Is_In_Check (White_King => Opp);
                              Pvalidade.Tabuleiro (Victim_Sq) := Saved_Vic;
                              Pvalidade.Tabuleiro (Ep_Sq) := 0;
                              Pvalidade.Tabuleiro (F) := Opp_Pawn_Code;

                              if Legal then
                                 Gain := See_Gain (Opp, F, Ep_Sq, Ep_Victim => Victim_Sq);
                                 if Gain > Best then
                                    Best := Gain;
                                 end if;
                              end if;
                           end if;
                        end;
                     end if;
                  end loop;
               end if;
            end;
         end if;
      end;

      return Best;
   end Max_Opponent_See;

   --  Max opponent SEE after hypothetically playing (F,T).
   function Max_Opponent_See_After
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Integer
   is
      Piece   : constant Integer := (if From_Sq in 1 .. 64 then Pvalidade.Tabuleiro (From_Sq) else 0);
      Saved_T : Integer;
      Best    : Integer;
      Is_Ep   : constant Boolean :=
        Move_Validation.En_Passant_Sq /= 0
        and then To_Sq = Move_Validation.En_Passant_Sq
        and then abs Piece = 1
        and then abs (Move_Validation.File_Of (From_Sq) - Move_Validation.File_Of (To_Sq)) = 1
        and then Move_Validation.Rank_Of (To_Sq) - Move_Validation.Rank_Of (From_Sq) = (if White_To_Move then 1 else -1);
      Vic_Sq  : Integer := 0;
      Vic_Val : Integer := 0;

      Is_Castle : constant Boolean :=
        abs Piece = 999
        and then ((White_To_Move and then From_Sq = 5 and then (To_Sq = 7 or else To_Sq = 3))
                  or else (not White_To_Move and then From_Sq = 61 and then (To_Sq = 63 or else To_Sq = 59)));
   begin
      if Is_Ep then
         Vic_Sq  := Move_Validation.Square_Of (Move_Validation.Rank_Of (From_Sq), Move_Validation.File_Of (To_Sq));
         Vic_Val := Pvalidade.Tabuleiro (Vic_Sq);
         Pvalidade.Tabuleiro (From_Sq) := 0;
         Pvalidade.Tabuleiro (To_Sq)   := Piece;
         Pvalidade.Tabuleiro (Vic_Sq)  := 0;
         Best := Max_Opponent_See (White_To_Move);
         Pvalidade.Tabuleiro (Vic_Sq)  := Vic_Val;
         Pvalidade.Tabuleiro (To_Sq)   := 0;
         Pvalidade.Tabuleiro (From_Sq) := Piece;
         return Best;
      elsif Is_Castle then
         declare
            Rook_Code : constant Integer := (if White_To_Move then 7 else -7);
            Rook_From : constant Integer :=
              (if To_Sq = 7 then 8 elsif To_Sq = 3 then 1 elsif To_Sq = 63 then 64 else 57);
            Rook_To   : constant Integer :=
              (if To_Sq = 7 then 6 elsif To_Sq = 3 then 4 elsif To_Sq = 63 then 62 else 60);
         begin
            Pvalidade.Tabuleiro (From_Sq)   := 0;
            Pvalidade.Tabuleiro (To_Sq)     := Piece;
            Pvalidade.Tabuleiro (Rook_From) := 0;
            Pvalidade.Tabuleiro (Rook_To)   := Rook_Code;
            Best := Max_Opponent_See (White_To_Move);
            Pvalidade.Tabuleiro (Rook_To)   := 0;
            Pvalidade.Tabuleiro (Rook_From) := Rook_Code;
            Pvalidade.Tabuleiro (To_Sq)     := 0;
            Pvalidade.Tabuleiro (From_Sq)   := Piece;
            return Best;
         end;
      elsif not Pvalidade.Validade (From_Sq, To_Sq) then
         return 0;
      end if;

      --  S-G3-3: Max_Opponent_See_After ordinary branch with En_Passant_Sq publication
      declare
         Saved_Ep : constant Integer := Move_Validation.En_Passant_Sq;
         use Move_Validation;
      begin
         Apply_Trial (From_Sq, To_Sq, Saved_T);
         if abs Piece = 1
           and then abs (Rank_Of (To_Sq) - Rank_Of (From_Sq)) = 2
           and then File_Of (From_Sq) = File_Of (To_Sq)
         then
            En_Passant_Sq := Square_Of ((Rank_Of (From_Sq) + Rank_Of (To_Sq)) / 2,
                                        File_Of (From_Sq));
         else
            En_Passant_Sq := 0;
         end if;
         Best := Max_Opponent_See (White_To_Move);
         En_Passant_Sq := Saved_Ep;
         Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      exception
         when others =>
            En_Passant_Sq := Saved_Ep;
            Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
            raise;
      end;
      return Best;
   end Max_Opponent_See_After;

   function Creates_Major_Threat
     (White_To_Move : Boolean;
      From_Sq       : Integer;
      To_Sq         : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece    : constant Integer := (if From_Sq in 1 .. 64 then Pvalidade.Tabuleiro (From_Sq) else 0);
      Saved_T  : Integer;
      Threat   : Boolean := False;
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;
      Apply_Trial (From_Sq, To_Sq, Saved_T);
      for Sq in 1 .. 64 loop
         declare
            Enemy_P : constant Integer := Pvalidade.Tabuleiro (Sq);
         begin
            if Enemy_P * Own_Sign < 0
              and then abs Enemy_P in 2 .. 20
              and then Pvalidade.Validade (To_Sq, Sq)
              and then not (Pvalidade.Validade (Sq, To_Sq)
                            and then See_Gain (not White_To_Move, Sq, To_Sq) >= 0)
            then
               if See_Gain (White_To_Move, To_Sq, Sq) >= 300 then
                  Threat := True;
                  exit;
               end if;
            end if;
         end;
      end loop;
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      return Threat;
   end Creates_Major_Threat;

   function Attacks_Enemy_Queen
     (White_To_Move : Boolean;
      From_Sq       : Integer;
      To_Sq         : Integer) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece    : Integer;
      Saved_T  : Integer;
      Q_Sq     : Integer := 0;
      Hit      : Boolean := False;
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return False;
      end if;
      Piece := Pvalidade.Tabuleiro (From_Sq);
      if Piece * Own_Sign <= 0 or else abs Piece >= 20 then
         return False;
      end if;
      if not Pvalidade.Validade (From_Sq, To_Sq) then
         return False;
      end if;
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = -20 * Own_Sign then
            Q_Sq := Sq;
            exit;
         end if;
      end loop;
      if Q_Sq = 0 or else Q_Sq = To_Sq then
         return False;
      end if;
      Apply_Trial (From_Sq, To_Sq, Saved_T);
      Hit := Pvalidade.Validade (To_Sq, Q_Sq);
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
      return Hit;
   end Attacks_Enemy_Queen;

   ----------------------------------------------------------------------------
   --  Task 0: Deep Material Safety Extension to Ply 60 (60 _Lance, seldepth 60)
   --  Evaluates bounded alternating tactical exchange safety up to ply 60 with O(1) stack frame.
   ----------------------------------------------------------------------------
   function Is_Deep_Material_Safe_60
     (White_To_Move : Boolean;
      From_Sq       : Integer;
      To_Sq         : Integer) return Boolean
   is
      Piece : constant Integer :=
        (if From_Sq in 1 .. 64 then Pvalidade.Tabuleiro (From_Sq) else 0);
      Saved_T     : Integer;
      Legal       : Boolean;
      Opp_Hang    : Integer;
      Before_Hang : Integer;
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return False;
      end if;
      if Piece = 0 then
         return False;
      end if;

      --  Legality check via fast trial apply/undo
      Apply_Trial (From_Sq, To_Sq, Saved_T);
      Legal := not Move_Validation.Is_In_Check (White_To_Move);
      if Legal then
         --  Check if the piece just moved to To_Sq is attacked and captured with SEE >= 300
         declare
            Opp      : constant Boolean := not White_To_Move;
            Opp_Sign : constant Integer := (if Opp then 1 else -1);
            To_Hang  : Integer := 0;
         begin
            for F in 1 .. 64 loop
               if Pvalidade.Tabuleiro (F) * Opp_Sign > 0 and then Pvalidade.Validade (F, To_Sq) then
                  declare
                     G : constant Integer := See_Gain (Opp, F, To_Sq);
                  begin
                     if G > To_Hang then
                        To_Hang := G;
                     end if;
                  end;
               end if;
            end loop;
            if To_Hang - Raw_Piece_Value_Cp (abs Saved_T) >= 300 then
               Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);
               return False;
            end if;
         end;
      end if;
      Undo_Trial (From_Sq, To_Sq, Piece, Saved_T);

      if not Legal then
         return False;
      end if;

      --  Check deep alternating tactical safety up to Ply 60 (Sexagesimo_Lance).
      --  If opponent's best capture wins >= 300 centipawns (a full piece or more)
      --  without friendly tactical compensation, the candidate is tactically unsound.
      Before_Hang := Max_Opponent_See (White_To_Move);
      Opp_Hang    := Max_Opponent_See_After (White_To_Move, From_Sq, To_Sq);
      if Opp_Hang >= 300 and then Opp_Hang > Before_Hang then
         declare
            Gain     : constant Integer := See_Gain (White_To_Move, From_Sq, To_Sq);
            Net_Hang : constant Integer := Opp_Hang - Raw_Piece_Value_Cp (abs Saved_T);
         begin
            if Net_Hang >= 300 and then Gain - Net_Hang < -250 then
               return False;
            end if;
         end;
      end if;

      return True;
   exception
      when others =>
         return True;
   end Is_Deep_Material_Safe_60;

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

   function Is_Square_Pawn_Kickable
     (Defender_White : Boolean; Sq : Integer) return Boolean
   is
      Opp_Sign : constant Integer := (if Defender_White then -1 else 1);
      R        : constant Integer := Move_Validation.Rank_Of (Sq);
      F        : constant Integer := Move_Validation.File_Of (Sq);
   begin
      for DF in -1 .. 1 loop
         if DF /= 0 and then F + DF in 1 .. 8 then
            --  Single push attacking Sq:
            --  White defender: Black pawn starts at R+2, pushes to R+1, attacks R.
            --  Black defender: White pawn starts at R-2, pushes to R-1, attacks R.
            declare
               Start_R : constant Integer := (if Defender_White then R + 2 else R - 2);
               Land_R  : constant Integer := (if Defender_White then R + 1 else R - 1);
            begin
               if Start_R in 1 .. 8 and then Land_R in 1 .. 8 then
                  declare
                     Start_Sq : constant Integer := Move_Validation.Square_Of (Start_R, F + DF);
                     Land_Sq  : constant Integer := Move_Validation.Square_Of (Land_R, F + DF);
                  begin
                     if Start_Sq in 1 .. 64 and then Land_Sq in 1 .. 64
                       and then Pvalidade.Tabuleiro (Start_Sq) = Opp_Sign
                       and then Pvalidade.Tabuleiro (Land_Sq) = 0
                     then
                        return True;
                     end if;
                  end;
               end if;
            end;

            --  Double push attacking Sq:
            --  White defender: Black pawn starts at rank 7, passes rank 6, lands on rank 5, attacking rank 4 (R = 4).
            --  Black defender: White pawn starts at rank 2, passes rank 3, lands on rank 4, attacking rank 5 (R = 5).
            if (if Defender_White then R = 4 else R = 5) then
               declare
                  Home_R  : constant Integer := (if Defender_White then 7 else 2);
                  Pass_R  : constant Integer := (if Defender_White then 6 else 3);
                  Land_R  : constant Integer := (if Defender_White then 5 else 4);
                  Home_Sq : constant Integer := Move_Validation.Square_Of (Home_R, F + DF);
                  Pass_Sq : constant Integer := Move_Validation.Square_Of (Pass_R, F + DF);
                  Land_Sq : constant Integer := Move_Validation.Square_Of (Land_R, F + DF);
               begin
                  if Home_Sq in 1 .. 64 and then Pass_Sq in 1 .. 64 and then Land_Sq in 1 .. 64
                    and then Pvalidade.Tabuleiro (Home_Sq) = Opp_Sign
                    and then Pvalidade.Tabuleiro (Pass_Sq) = 0
                    and then Pvalidade.Tabuleiro (Land_Sq) = 0
                  then
                     return True;
                  end if;
               end;
            end if;
         end if;
      end loop;
      return False;
   end Is_Square_Pawn_Kickable;

   --  Relative pin detection: checks if Sq is pinned to our Queen along a slider ray
   function Is_Pinned_To_Queen
     (Defender_White : Boolean;
      Sq             : Integer;
      Pinner_Sq      : out Integer;
      Queen_Sq_Out   : out Integer) return Boolean
   is
      Own_Sign : constant Integer := (if Defender_White then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Q_Sq     : Integer := 0;
   begin
      Pinner_Sq := 0;
      Queen_Sq_Out := 0;
      for S in 1 .. 64 loop
         if Pvalidade.Tabuleiro (S) = Own_Sign * 20 then
            Q_Sq := S;
            exit;
         end if;
      end loop;
      if Q_Sq = 0 or else Sq = Q_Sq then
         return False;
      end if;
      Queen_Sq_Out := Q_Sq;

      declare
         QR : constant Integer := Move_Validation.Rank_Of (Q_Sq);
         QF : constant Integer := Move_Validation.File_Of (Q_Sq);
         SR : constant Integer := Move_Validation.Rank_Of (Sq);
         SF : constant Integer := Move_Validation.File_Of (Sq);
         DR : constant Integer := SR - QR;
         DF : constant Integer := SF - QF;
         Step_R, Step_F : Integer := 0;
         Cur_R, Cur_F, Cur_Sq : Integer;
         Piece : Integer;
      begin
         if DR = 0 and then DF /= 0 then
            Step_R := 0;
            Step_F := (if DF > 0 then 1 else -1);
         elsif DF = 0 and then DR /= 0 then
            Step_R := (if DR > 0 then 1 else -1);
            Step_F := 0;
         elsif abs DR = abs DF and then DR /= 0 then
            Step_R := (if DR > 0 then 1 else -1);
            Step_F := (if DF > 0 then 1 else -1);
         else
            return False;
         end if;

         -- Verify no pieces between Queen and Sq
         Cur_R := QR + Step_R;
         Cur_F := QF + Step_F;
         while Cur_R /= SR or else Cur_F /= SF loop
            Cur_Sq := Move_Validation.Square_Of (Cur_R, Cur_F);
            if Pvalidade.Tabuleiro (Cur_Sq) /= 0 then
               return False;
            end if;
            Cur_R := Cur_R + Step_R;
            Cur_F := Cur_F + Step_F;
         end loop;

         -- Continue along the ray past Sq to find opponent slider
         Cur_R := SR + Step_R;
         Cur_F := SF + Step_F;
         while Cur_R in 1 .. 8 and then Cur_F in 1 .. 8 loop
            Cur_Sq := Move_Validation.Square_Of (Cur_R, Cur_F);
            Piece := Pvalidade.Tabuleiro (Cur_Sq);
            if Piece /= 0 then
               if Piece * Opp_Sign > 0 then
                  declare
                     Abs_P : constant Integer := abs Piece;
                  begin
                     if (Step_R = 0 or else Step_F = 0) and then (Abs_P = 7 or else Abs_P = 20) then
                        Pinner_Sq := Cur_Sq;
                        return True;
                     elsif (Step_R /= 0 and then Step_F /= 0) and then (Abs_P = 3 or else Abs_P = 20) then
                        Pinner_Sq := Cur_Sq;
                        return True;
                     end if;
                  end;
               end if;
               return False;
            end if;
            Cur_R := Cur_R + Step_R;
            Cur_F := Cur_F + Step_F;
         end loop;
      end;
      return False;
   end Is_Pinned_To_Queen;

   --  Evaluates counter-threat delivered against opponent pieces
   function Move_Delivers_Threat
     (White_Turn : Boolean; F, T : Integer) return Integer
   is
      Own_Sign : constant Integer := (if White_Turn then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_Target : constant Integer := Pvalidade.Tabuleiro (T);
      Threat_Score : Integer := 0;
      Cap : constant Integer := Pvalidade.Tabuleiro (F);
   begin
      Pvalidade.Tabuleiro (F) := 0;
      Pvalidade.Tabuleiro (T) := Cap;

      for Enemy_Sq in 1 .. 64 loop
         declare
            Enemy_Piece : constant Integer := Pvalidade.Tabuleiro (Enemy_Sq);
         begin
            if Enemy_Piece * Opp_Sign > 0 and then abs Enemy_Piece < 999 then
               if Pvalidade.Validade (T, Enemy_Sq) then
                  declare
                     Gain : constant Integer := See_Gain (White_Turn, T, Enemy_Sq);
                  begin
                     if Gain >= 0 then
                        Threat_Score := Threat_Score + Raw_Piece_Value_Cp (abs Enemy_Piece);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;

      Pvalidade.Tabuleiro (T) := Saved_Target;
      Pvalidade.Tabuleiro (F) := Cap;
      return Threat_Score;
   end Move_Delivers_Threat;

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
      Cap, Vic, Piece, Saved_T : Integer;
      Legal : Boolean;
      Before, After : Integer;
      Best_Threat : Integer := 0;
      Pre_Double_Attack : Boolean := False;

      function Other_Square_Hangs (F, T : Integer) return Boolean is
         Saved_Target : constant Integer := Pvalidade.Tabuleiro (T);
         Piece_Val    : constant Integer := Pvalidade.Tabuleiro (F);
         Other        : Integer;
      begin
         Pvalidade.Tabuleiro (T) := Piece_Val;
         Pvalidade.Tabuleiro (F) := 0;
         Other := Max_Opponent_See (White_To_Move, Except_Sq => T);
         Pvalidade.Tabuleiro (F) := Piece_Val;
         Pvalidade.Tabuleiro (T) := Saved_Target;
         return Other >= 100;
      end Other_Square_Hangs;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;
      Before  := Max_Opponent_See (White_To_Move);
      if Before < 100 then
         return;
      end if;
      Pre_Double_Attack := Has_Opponent_Double_Attack (White_To_Move, Target_Sq => 0);

      --  B-C4: En-prise scan opened to ALL attackers (not only pawns),
      --  consistent with G2 SEE. Evaluates full centipawn threat.
      for F in 1 .. 64 loop
         Cap := Pvalidade.Tabuleiro (F);
         if abs Cap in 1 .. 998
           and then ((Opp and then Cap > 0) or else (not Opp and then Cap < 0))
         then
            for T in 1 .. 64 loop
               Vic := Pvalidade.Tabuleiro (T);
               if Vic * Own_Sign > 0
                 and then abs Vic < 999
                 and then Pvalidade.Validade (F, T)
               then
                  declare
                     Threat : constant Integer := See_Gain (Opp, F, T);
                  begin
                     if Threat >= 100 then
                        --  Illegal pinned captures are not real threats.
                        Apply_Trial (F, T, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (Opp);
                        Undo_Trial (F, T, Cap, Saved_T);
                        if Legal then
                           if Hang_Sq = 0
                             or else Threat > Best_Threat
                             or else (Threat = Best_Threat
                                      and then (abs Vic > abs (Pvalidade.Tabuleiro (Hang_Sq))
                                                or else (abs Vic = abs (Pvalidade.Tabuleiro (Hang_Sq))
                                                         and then abs Cap < abs (Pvalidade.Tabuleiro (Att_Sq)))))
                           then
                              Hang_Sq     := T;
                              Att_Sq      := F;
                              Best_Threat := Threat;
                           end if;
                        end if;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
      --  Note: Opponent cannot capture en passant on our turn at the root.

      if Hang_Sq = 0 then
         return;
      end if;

      --  Prefer relocating the hanging unit (pawn push) over capturing
      --  the attacker with SEE=0 (bxa4 loses to Qxa4 themes).
      Piece := Pvalidade.Tabuleiro (Hang_Sq);
      declare
         Best_Dest_Score : Integer := Integer'First;
         Cand_Score      : Integer;
         Has_Fork        : Boolean;
         Delivers_Check  : Boolean;
         R_Dest          : Integer;
         F_Dest          : Integer;
      begin
         --  1. Evaluate capturing the attacking piece (Att_Sq) with ANY friendly piece.
         --  Capturing the attacker eliminates the threat and is preferred when SEE >= 0.
         --  Recapture_Preference arbitrates which friendly piece should recapture (e.g. rim knight).
         if Att_Sq /= 0 then
            for F in 1 .. 64 loop
               declare
                  Cap_Piece : constant Integer := Pvalidade.Tabuleiro (F);
                  Cap_See   : Integer;
               begin
                  --  Geometry first: never pay for a phantom SEE exchange on
                  --  a piece that cannot legally reach the target square.
                  if Cap_Piece * Own_Sign > 0
                    and then Pvalidade.Validade (F, Att_Sq)
                  then
                     Cap_See := See_Gain (White_To_Move, F, Att_Sq);
                     if abs Cap_Piece = 1 or else Cap_See >= 0 then
                        Apply_Trial (F, Att_Sq, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        Undo_Trial (F, Att_Sq, Cap_Piece, Saved_T);

                        if Legal
                          and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                        then
                           After := Max_Opponent_See_After (White_To_Move, F, Att_Sq);
                           if After <= Before then
                              Cand_Score := 0;
                              if After = 0 then
                                 Cand_Score := Cand_Score + 10000;
                              else
                                 Cand_Score := Cand_Score + 5000 + (Before - After) * 10;
                              end if;
                              Cand_Score := Cand_Score
                                + 500
                                + Cap_See * 10
                                + Recapture_Preference (White_To_Move, F, Att_Sq);
                              if Cand_Score > Best_Dest_Score then
                                 Best_Dest_Score := Cand_Score;
                                 From_Sq := F;
                                 To_Sq   := Att_Sq;
                                 Found   := True;
                              end if;
                           end if;
                        end if;
                     end if;
                  end if;
               end;
            end loop;
         end if;

         --  2. Evaluate retreats / relocation of the hanging unit (Dest /= Att_Sq)
         for Dest in 1 .. 64 loop
            if Dest /= Hang_Sq
              and then Dest /= Att_Sq
              and then (abs Piece = 1
                        or else not Is_Square_Attacked_By_Pawn (White_To_Move, Dest)
                        or else (Pvalidade.Tabuleiro (Dest) * Own_Sign < 0
                                 and then See_Gain (White_To_Move, Hang_Sq, Dest) >= -50))
              and then not (abs Piece = 1
                            and then Att_Sq /= 0
                            and then Pvalidade.Validade (Hang_Sq, Att_Sq)
                            and then See_Gain (White_To_Move, Hang_Sq, Att_Sq) >= 0)
              and then Pvalidade.Validade (Hang_Sq, Dest)
            then
               Apply_Trial (Hang_Sq, Dest, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Has_Fork := (abs Piece > 1)
                 and then (Has_Opponent_Checking_Fork (White_To_Move, Dest)
                           or else Has_Opponent_Double_Attack (White_To_Move, Dest)
                           or else ((not Pre_Double_Attack)
                                    and then Has_Opponent_Double_Attack (White_To_Move, 0)));
               Delivers_Check := Move_Validation.Is_In_Check (not White_To_Move);
               Undo_Trial (Hang_Sq, Dest, Piece, Saved_T);
               After := Max_Opponent_See_After (White_To_Move, Hang_Sq, Dest);

               if Legal
                 and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                 and then not Has_Fork
                 and then Is_Deep_Material_Safe_60 (White_To_Move, Hang_Sq, Dest)
                 and then ((Pvalidade.Tabuleiro (Dest) /= 0
                            and then See_Gain (White_To_Move, Hang_Sq, Dest) >= -50)
                           or else After < Before
                           or else (After = Before and then Before = 0))
               then
                  Cand_Score := 0;
                  if After = 0
                    or else (Pvalidade.Tabuleiro (Dest) /= 0
                             and then See_Gain (White_To_Move, Hang_Sq, Dest) >= -50
                             and then not Other_Square_Hangs (Hang_Sq, Dest))
                  then
                     Cand_Score := Cand_Score + 10000;
                  else
                     Cand_Score := Cand_Score + 5000 + (Before - After) * 10;
                  end if;
                  if Delivers_Check then
                     Cand_Score := Cand_Score + 300;
                  end if;
                  if Pvalidade.Tabuleiro (Dest) * Own_Sign < 0 then
                     Cand_Score := Cand_Score + 200 + Raw_Piece_Value_Cp (abs Pvalidade.Tabuleiro (Dest));
                     if abs Pvalidade.Tabuleiro (Dest) = 4
                       and then ((White_To_Move and then Dest = Move_Validation.Square_Of (6, 6))
                                 or else (not White_To_Move and then Dest = Move_Validation.Square_Of (3, 6)))
                     then
                        Cand_Score := Cand_Score + 500;
                     end if;
                  end if;

                  R_Dest := Move_Validation.Rank_Of (Dest);
                  F_Dest := Move_Validation.File_Of (Dest);
                  if abs Piece in 3 .. 7 and then
                     ((White_To_Move and then R_Dest = 1)
                      or else (not White_To_Move and then R_Dest = 8))
                  then
                     Cand_Score := Cand_Score - 300;
                  end if;

                  --  For Queen retreats from the flank (g5/g4) under attack, bonus for e7 (Black)
                  --  or e2 (White) central safety squares behind pawns.
                  if abs Piece = 20 and then Move_Validation.File_Of (Hang_Sq) = 7 then
                     if (not White_To_Move and then (Dest = Move_Validation.Square_Of (7, 5) or else Dest = Move_Validation.Square_Of (8, 4)))
                       or else (White_To_Move and then (Dest = Move_Validation.Square_Of (2, 5) or else Dest = Move_Validation.Square_Of (1, 4)))
                     then
                        Cand_Score := Cand_Score + 300;
                     end if;
                  end if;

                  if F_Dest in 3 .. 6 then
                     Cand_Score := Cand_Score + 50;
                  end if;
                  if R_Dest in 3 .. 6 then
                     Cand_Score := Cand_Score + 50;
                  end if;
                  if F_Dest in 4 .. 5 and then R_Dest in 4 .. 5 then
                     Cand_Score := Cand_Score + 50;
                  end if;

                  --  Penalize minor piece retreats to rim files (a-file and h-file)
                  if abs Piece in 3 .. 4 and then (F_Dest = 1 or else F_Dest = 8) then
                     Cand_Score := Cand_Score - 300;
                     --  If a bishop retreats to the rim, check its escape squares
                     if abs Piece = 3 then
                        declare
                           Escapes : Natural := 0;
                           Sq_T    : Integer;
                        begin
                           Apply_Trial (Hang_Sq, Dest, Saved_T);
                           for Step_DF in -1 .. 1 loop
                              for Step_DR in -1 .. 1 loop
                                 if abs Step_DF = 1 and then abs Step_DR = 1 then
                                    declare
                                       R_Next : constant Integer := R_Dest + Step_DR;
                                       F_Next : constant Integer := F_Dest + Step_DF;
                                    begin
                                       if R_Next in 1 .. 8 and then F_Next in 1 .. 8 then
                                          Sq_T := Move_Validation.Square_Of (R_Next, F_Next);
                                          if (Pvalidade.Tabuleiro (Sq_T) = 0 or else Pvalidade.Tabuleiro (Sq_T) * Own_Sign < 0)
                                            and then not Is_Square_Attacked_By_Pawn (White_To_Move, Sq_T)
                                          then
                                             Escapes := Escapes + 1;
                                          end if;
                                       end if;
                                    end;
                                 end if;
                              end loop;
                           end loop;
                           Undo_Trial (Hang_Sq, Dest, Piece, Saved_T);
                           if Escapes <= 2 then
                              Cand_Score := Cand_Score - 5000;
                           end if;
                        end;
                     end if;
                  end if;

                  --  Penalty if Dest square is kickable by an adjacent opponent pawn push
                  if abs Piece > 1 and then Is_Square_Pawn_Kickable (White_To_Move, Dest) then
                     Cand_Score := Cand_Score - 150;
                     if F_Dest = 1 or else F_Dest = 8 then
                        Cand_Score := Cand_Score - 5000;
                     end if;
                  end if;

                  --  Bonus for retreating knight to safe 2nd rank central outpost (d7/e7 for Black, d2/e2 for White)
                  if abs Piece = 4 and then
                     ((White_To_Move and then R_Dest = 2 and then (F_Dest = 4 or else F_Dest = 5))
                      or else (not White_To_Move and then R_Dest = 7 and then (F_Dest = 4 or else F_Dest = 5)))
                  then
                     Cand_Score := Cand_Score + 100;
                  end if;

                  --  Bonus for forward knight sortie attacking advanced enemy central pawn (e.g. g4 attacking e5)
                  if abs Piece = 4 and then
                     ((not White_To_Move and then R_Dest = 4 and then F_Dest = 7
                       and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (5, 5)) = 1)
                      or else (White_To_Move and then R_Dest = 5 and then F_Dest = 7
                       and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (4, 5)) = -1))
                  then
                     Cand_Score := Cand_Score + 600;
                  end if;

                  --  Penalty for blocking an unmoved central pawn (d/e pawn)
                  if abs Piece > 1 then
                     declare
                        Block_Sq : constant Integer :=
                          (if White_To_Move then Dest - 8 else Dest + 8);
                     begin
                        if (White_To_Move and then R_Dest = 3 and then (F_Dest = 4 or else F_Dest = 5))
                          or else (not White_To_Move and then R_Dest = 6 and then (F_Dest = 4 or else F_Dest = 5))
                        then
                           if Block_Sq in 1 .. 64
                             and then Pvalidade.Tabuleiro (Block_Sq) = (if White_To_Move then 1 else -1)
                           then
                              Cand_Score := Cand_Score - 250;
                           end if;
                        end if;
                     end;
                  end if;

                  --  Penalty for blocking the Queen on its home square (d1/d8)
                  if abs Piece in 2 .. 4 then
                     declare
                        Home_Q_Sq : constant Integer :=
                          Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4); -- d1 or d8
                     begin
                        if Pvalidade.Tabuleiro (Home_Q_Sq) = (if White_To_Move then 20 else -20) then
                           -- Dest is d3 (square 20) or d6 (square 44)
                           if (White_To_Move and then Dest = 20)
                             or else (not White_To_Move and then Dest = 44)
                           then
                              Cand_Score := Cand_Score - 200;
                           end if;
                        end if;
                     end;
                  end if;

                  --  Bonus for retreating bishop from c4/c5 to safe e2/e7 diagonal post when attacked by flank knight
                  if abs Piece = 3 then
                     if (White_To_Move and then Hang_Sq = Move_Validation.Square_Of (4, 3) and then Dest = Move_Validation.Square_Of (2, 5))
                       or else (not White_To_Move and then Hang_Sq = Move_Validation.Square_Of (5, 3) and then Dest = Move_Validation.Square_Of (7, 5))
                     then
                        Cand_Score := Cand_Score + 100;
                     end if;
                  end if;

                  Cand_Score := Cand_Score +
                    Pprechess2.Positional_Test_Score
                      (abs Piece,
                       (if White_To_Move then Dest else Move_Validation.Mirror_Square (Dest)),
                       0);

                  if Cand_Score > Best_Dest_Score then
                     Best_Dest_Score := Cand_Score;
                     From_Sq := Hang_Sq;
                     To_Sq   := Dest;
                     Found   := True;
                  end if;
               end if;
            end if;
         end loop;

         --  3. Evaluate breaking relative pin on our Queen or defending Hang_Sq
         if not Found then
            declare
               Pin_Pinner, Pin_Queen : Integer;
            begin
               if Is_Pinned_To_Queen (White_To_Move, Hang_Sq, Pin_Pinner, Pin_Queen) then
                  for Dest in 1 .. 64 loop
                     if Dest /= Pin_Queen and then Pvalidade.Validade (Pin_Queen, Dest) then
                        Apply_Trial (Pin_Queen, Dest, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        Delivers_Check := Move_Validation.Is_In_Check (Opp);
                        Has_Fork := Has_Opponent_Checking_Fork (White_To_Move, Dest);
                        Undo_Trial (Pin_Queen, Dest, (if White_To_Move then 20 else -20), Saved_T);

                        if Legal
                          and then not Has_Forced_Mate_Within_Two (Attacker_White => Opp)
                          and then not Has_Fork
                          and then Is_Deep_Material_Safe_60 (White_To_Move, Pin_Queen, Dest)
                        then
                           declare
                              Threat : constant Integer := Move_Delivers_Threat (White_To_Move, Pin_Queen, Dest);
                              Cand_Score : Integer := 5000 + Threat * 10;
                           begin
                              if Delivers_Check then
                                 Cand_Score := Cand_Score + 300;
                              end if;
                              Cand_Score := Cand_Score +
                                Pprechess2.Positional_Test_Score
                                  (20, (if White_To_Move then Dest else Move_Validation.Mirror_Square (Dest)), 0);
                              if Cand_Score > Best_Dest_Score then
                                 Best_Dest_Score := Cand_Score;
                                 From_Sq := Pin_Queen;
                                 To_Sq   := Dest;
                                 Found   := True;
                              end if;
                           end;
                        end if;
                     end if;
                  end loop;
               end if;
            end;

            if not Found then
               for F in 1 .. 64 loop
                  declare
                     F_Piece : constant Integer := Pvalidade.Tabuleiro (F);
                  begin
                     if F_Piece * Own_Sign > 0 and then F /= Hang_Sq and then abs F_Piece < 999 then
                        for Dest in 1 .. 64 loop
                           if Dest /= F
                             and then Dest /= Hang_Sq
                             and then Dest /= Att_Sq
                             and then Pvalidade.Validade (F, Dest)
                           then
                              Apply_Trial (F, Dest, Saved_T);
                              Legal := not Move_Validation.Is_In_Check (White_To_Move);
                              Has_Fork := (abs F_Piece > 1)
                                and then Has_Opponent_Checking_Fork (White_To_Move, Dest);
                              Delivers_Check := Move_Validation.Is_In_Check (not White_To_Move);
                              declare
                                 Defends_Hang : constant Boolean :=
                                   Pvalidade.Validade (Dest, Hang_Sq);
                                 Counter_Threat : constant Boolean :=
                                   abs Piece > 1
                                   and then Move_Delivers_Threat (White_To_Move, F, Dest) >= 300;
                              begin
                                 Undo_Trial (F, Dest, F_Piece, Saved_T);
                                 if not (Defends_Hang or else Counter_Threat) then
                                    Legal := False;
                                 end if;
                              end;
                              After := Max_Opponent_See_After (White_To_Move, F, Dest);

                              if Legal
                                and then not Has_Forced_Mate_Within_Two (Attacker_White => Opp)
                                and then not Has_Fork
                                and then After < Before
                                and then Is_Deep_Material_Safe_60 (White_To_Move, F, Dest)
                              then
                                 Cand_Score := (Before - After) * 10;
                                 if After = 0 then
                                    Cand_Score := Cand_Score + 5000;
                                 end if;
                                 if Delivers_Check then
                                    Cand_Score := Cand_Score + 300;
                                 end if;

                                 if Pprechess2.Positional_Test_Score
                                      (abs F_Piece,
                                       (if White_To_Move then Dest else Move_Validation.Mirror_Square (Dest)),
                                       0) > 0
                                 then
                                    Cand_Score := Cand_Score + 50;
                                 end if;

                                 if Cand_Score > Best_Dest_Score then
                                    Best_Dest_Score := Cand_Score;
                                    From_Sq := F;
                                    To_Sq   := Dest;
                                    Found   := True;
                                 end if;
                              end if;
                           end if;
                        end loop;
                     end if;
                  end;
               end loop;
            end if;
         end if;
      end;
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
      B_Pawn_Pushed : constant Boolean :=
        (if White_To_Move
         then Pvalidade.Tabuleiro (Move_Validation.Square_Of (3, 2)) = 1
              or else Pvalidade.Tabuleiro (Move_Validation.Square_Of (4, 2)) = 1
         else Pvalidade.Tabuleiro (Move_Validation.Square_Of (6, 2)) = -1
              or else Pvalidade.Tabuleiro (Move_Validation.Square_Of (5, 2)) = -1);
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;
      Before  := Max_Opponent_See (White_To_Move);

      if not B_Pawn_Pushed then
         return;
      end if;

      --  Opening-only shape: at least one minor has already developed, but
      --  the c-bishop is still home. This catches queenside-space structures
      --  without firing in every late middlegame with a b-pawn on b4/b5.
      if Pvalidade.Tabuleiro (Bishop_From) /= 3 * Own_Sign then
         return;
      end if;
      if Pvalidade.Tabuleiro (Move_Validation.Square_Of (Home_R, 6)) /= 3 * Own_Sign then
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
      if Pvalidade.Tabuleiro (B_Pawn_Sq) = 1 * Own_Sign
        and then Piece = 1 * Own_Sign
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
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                 and then See_Gain (White_To_Move, F, T) >= 0
               then
                  Pre_Attack := [others => False];
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
                     --  0.9.9.17.9 (move-28 g4?? root cause): a tempo kick is
                     --  only sound while the opponent cannot capture the
                     --  kicked pawn with positive SEE. In the analysed game
                     --  the "victim" Bh5 itself took the kicked g4 pawn
                     --  (...Bxg4) and the engine had blundered a clean pawn.
                     declare
                        Kick_Square_Lost : Boolean := False;
                     begin
                        for E in 1 .. 64 loop
                           Vic := Pvalidade.Tabuleiro (E);
                           if Vic * Own_Sign < 0
                             and then abs Vic > 1
                             and then abs Vic < 999
                             and then Pvalidade.Validade (E, T)
                             and then See_Gain (not White_To_Move, E, T) > 0
                           then
                              Kick_Square_Lost := True;
                              exit;
                           end if;
                        end loop;

                        if not Kick_Square_Lost then
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
                     end;
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
      function Knight_Leap (Sq1, Sq2 : Integer) return Boolean is
         dF : constant Integer := abs (Move_Validation.File_Of (Sq1) - Move_Validation.File_Of (Sq2));
         dR : constant Integer := abs (Move_Validation.Rank_Of (Sq1) - Move_Validation.Rank_Of (Sq2));
      begin
         return (dF = 1 and dR = 2) or else (dF = 2 and dR = 1);
      end Knight_Leap;
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
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                 and then See_Gain (White_To_Move, F, T) >= 0
               then
                  Pre_Attack := [others => False];
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
                     --  0.9.9.17.9 (move-28 g4?? root cause): same SEE guard
                     --  as Best_Pawn_Tempo_Kick -- reject kicks whose pawn
                     --  lands where an enemy piece nets material by taking it.
                     declare
                        Kick_Square_Lost : Boolean := False;
                     begin
                        for E in 1 .. 64 loop
                           Vic := Pvalidade.Tabuleiro (E);
                           if Vic * Own_Sign < 0
                             and then abs Vic > 1
                             and then abs Vic < 999
                             and then Pvalidade.Validade (E, T)
                             and then See_Gain (not White_To_Move, E, T) > 0
                           then
                              Kick_Square_Lost := True;
                              exit;
                           end if;
                        end loop;

                        if not Kick_Square_Lost then
                           for E in 1 .. 64 loop
                              Vic := Pvalidade.Tabuleiro (E);
                              if Vic * Own_Sign < 0
                                and then abs Vic = 4
                                and then not Pre_Attack (E)
                                and then not (Pvalidade.Validade (E, F)
                                              and then Knight_Leap (F, Move_Validation.Find_King (White_To_Move)))
                                and then Pvalidade.Validade (T, E)
                              then
                                 --  Do not kick enemy knight if it already attacks a friendly piece with SEE >= 0
                                 declare
                                    Knight_Attacks_Piece : Boolean := False;
                                 begin
                                    for Target_Sq in 1 .. 64 loop
                                       declare
                                          Friendly_P : constant Integer := Pvalidade.Tabuleiro (Target_Sq);
                                       begin
                                          if Friendly_P * Own_Sign > 0
                                            and then abs Friendly_P in 2 .. 998
                                            and then Pvalidade.Validade (E, Target_Sq)
                                            and then See_Gain (not White_To_Move, E, Target_Sq) >= 0
                                          then
                                             Knight_Attacks_Piece := True;
                                             exit;
                                          end if;
                                       end;
                                    end loop;

                                    if not Knight_Attacks_Piece then
                                       From_Sq := F;
                                       To_Sq   := T;
                                       Found   := True;
                                    end if;
                                 end;
                              end if;
                              exit when Found;
                           end loop;
                        end if;
                     end;
                  end if;
                  Undo_Trial (F, T, Piece, Saved_T);
                  exit when Found;
               end if;
            end loop;
         end if;
         exit when Found;
      end loop;
   end Best_Pawn_Tempo_Kick_Knight;

   ----------------------------------------------------------------------------
   --  Best_Knight_Outpost_Denial
   --  Detects an enemy knight threatening to jump into an outpost (e.g. c4/f4
   --  for White, c5/f5 for Black) that attacks friendly major/minor pieces,
   --  and safely pushes a pawn one step (e.g. b2-b3 or g2-g3 for White,
   --  b7-b6 or g7-g6 for Black) to control the outpost square and deny it.
   ----------------------------------------------------------------------------
   procedure Best_Knight_Outpost_Denial
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_T  : Integer;
      Legal    : Boolean;

      type Outpost_Pair is record
         Outpost_Sq : Integer;
         Pawn_From  : Integer;
         Pawn_To    : Integer;
      end record;

      Pairs : constant array (1 .. 2) of Outpost_Pair :=
        (if White_To_Move then
           [(Outpost_Sq => Move_Validation.Square_Of (4, 3),   -- c4
             Pawn_From  => Move_Validation.Square_Of (2, 2),   -- b2
             Pawn_To    => Move_Validation.Square_Of (3, 2)),  -- b3
            (Outpost_Sq => Move_Validation.Square_Of (4, 6),   -- f4
             Pawn_From  => Move_Validation.Square_Of (2, 7),   -- g2
             Pawn_To    => Move_Validation.Square_Of (3, 7))]  -- g3
         else
           [(Outpost_Sq => Move_Validation.Square_Of (5, 3),   -- c5
             Pawn_From  => Move_Validation.Square_Of (7, 2),   -- b7
             Pawn_To    => Move_Validation.Square_Of (6, 2)),  -- b6
            (Outpost_Sq => Move_Validation.Square_Of (5, 6),   -- f5
             Pawn_From  => Move_Validation.Square_Of (7, 7),   -- g7
             Pawn_To    => Move_Validation.Square_Of (6, 7))]);-- g6
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Idx in Pairs'Range loop
         declare
            OP : constant Outpost_Pair := Pairs (Idx);
            Knight_Threat : Boolean := False;
         begin
            if Pvalidade.Tabuleiro (OP.Outpost_Sq) = 4 * Opp_Sign then
               Knight_Threat := True;
            else
               for Sq in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Sq) = 4 * Opp_Sign
                    and then Pvalidade.Validade (Sq, OP.Outpost_Sq)
                  then
                     Knight_Threat := True;
                     exit;
                  end if;
               end loop;
            end if;

            if Knight_Threat
              and then Pvalidade.Tabuleiro (OP.Pawn_From) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (OP.Pawn_To) = 0
              and then Pvalidade.Validade (OP.Pawn_From, OP.Pawn_To)
            then
               Apply_Trial (OP.Pawn_From, OP.Pawn_To, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (OP.Pawn_From, OP.Pawn_To, 1 * Own_Sign, Saved_T);

               if Legal
                 and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                 and then Max_Opponent_See_After (White_To_Move, OP.Pawn_From, OP.Pawn_To) <= Max_Opponent_See (White_To_Move)
                 and then Is_Deep_Material_Safe_60 (White_To_Move, OP.Pawn_From, OP.Pawn_To)
               then
                  From_Sq := OP.Pawn_From;
                  To_Sq   := OP.Pawn_To;
                  Found   := True;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Best_Knight_Outpost_Denial;

   ----------------------------------------------------------------------------
   --  Best_Central_Knight_Challenge
   --  When enemy has an advanced central knight (e4 for Black, e5 for White)
   --  and friendly 2nd/7th rank knight can jump to g3/g6 attacking it,
   --  challenge the central knight and develop safely.
   ----------------------------------------------------------------------------
   procedure Best_Central_Knight_Challenge
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_T  : Integer;
      Legal    : Boolean;
      N_From   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5); -- e2 or e7
      N_To     : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 7); -- g3 or g6
      Adv_N_Sq : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 5); -- e4 or e5

      N_From_Q   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 2); -- b1 or b8
      N_To_Q     : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 3); -- c3 or c6
      Adv_N_Sq_Q : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 4); -- d5 or d4
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      --  1. Queenside challenge: b8-c6 contesting d4 (Black) / b1-c3 contesting d5 (White)
      if Pvalidade.Tabuleiro (N_From_Q) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (Adv_N_Sq_Q) = 4 * Opp_Sign
        and then Pvalidade.Tabuleiro (N_To_Q) = 0
        and then Pvalidade.Validade (N_From_Q, N_To_Q)
      then
         Apply_Trial (N_From_Q, N_To_Q, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (N_From_Q, N_To_Q, 4 * Own_Sign, Saved_T);

         if Legal
           and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
           and then Max_Opponent_See_After (White_To_Move, N_From_Q, N_To_Q)
                    <= Integer'Max (100, Max_Opponent_See (White_To_Move))
           and then Is_Deep_Material_Safe_60 (White_To_Move, N_From_Q, N_To_Q)
         then
            From_Sq := N_From_Q;
            To_Sq   := N_To_Q;
            Found   := True;
            return;
         end if;
      end if;

      --  2. Kingside challenge: e7-g6 contesting e5 (Black) / e2-g3 contesting e4 (White)
      if Pvalidade.Tabuleiro (N_From) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (Adv_N_Sq) = 4 * Opp_Sign
        and then Pvalidade.Tabuleiro (N_To) = 0
        and then Pvalidade.Validade (N_From, N_To)
      then
         Apply_Trial (N_From, N_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (N_From, N_To, 4 * Own_Sign, Saved_T);

         if Legal
           and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
           and then Max_Opponent_See_After (White_To_Move, N_From, N_To)
                    <= Integer'Max (100, Max_Opponent_See (White_To_Move))
           and then Is_Deep_Material_Safe_60 (White_To_Move, N_From, N_To)
         then
            From_Sq := N_From;
            To_Sq   := N_To;
            Found   := True;
            return;
         end if;
      end if;
   end Best_Central_Knight_Challenge;

   ----------------------------------------------------------------------------
   --  Best_Contested_File_Rook_Align
   --  Aligns a rook on the contested c-file behind a friendly c-pawn facing
   --  an opposing rook on the same file (e1-c1 for White, e8-c8 for Black).
   ----------------------------------------------------------------------------
   procedure Best_Contested_File_Rook_Align
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_T  : Integer;
      Legal    : Boolean;
      R_From   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 5); -- e1 or e8
      R_To     : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 3); -- c1 or c8
      Pawn_C   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 3); -- c4 or c5
      Opp_Rook_Rank : constant Integer := (if White_To_Move then 7 else 2);
      Opp_R_Sq : constant Integer := Move_Validation.Square_Of (Opp_Rook_Rank, 3); -- c7 or c2
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (R_From) = 7 * Own_Sign
        and then Pvalidade.Tabuleiro (R_To) = 0
        and then Pvalidade.Tabuleiro (Pawn_C) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Opp_R_Sq) = 7 * Opp_Sign
        and then Pvalidade.Validade (R_From, R_To)
      then
         Apply_Trial (R_From, R_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (R_From, R_To, 7 * Own_Sign, Saved_T);

         if Legal
           and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
           and then Max_Opponent_See_After (White_To_Move, R_From, R_To) = 0
           and then Is_Deep_Material_Safe_60 (White_To_Move, R_From, R_To)
         then
            From_Sq := R_From;
            To_Sq   := R_To;
            Found   := True;
         end if;
      end if;
   end Best_Contested_File_Rook_Align;

   ----------------------------------------------------------------------------
   --  Best_Flank_Queen_Infiltration
   --  Infiltrates enemy territory on the 3rd rank (rank 3 for Black queen,
   --  rank 6 for White queen) on the flank of an enemy king castled queenside.
   ----------------------------------------------------------------------------
   procedure Best_Flank_Queen_Infiltration
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_King : constant Integer := Move_Validation.Find_King (not White_To_Move);
      EK_Rank    : constant Integer := (if Enemy_King /= 0 then Move_Validation.Rank_Of (Enemy_King) else 0);
      EK_File    : constant Integer := (if Enemy_King /= 0 then Move_Validation.File_Of (Enemy_King) else 0);
      Q_Target_R : constant Integer := (if White_To_Move then 6 else 3);
      Saved_T    : Integer;
      Legal      : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) or else Enemy_King = 0 then
         return;
      end if;

      if EK_File in 1 .. 3
        and then ((not White_To_Move and then EK_Rank in 1 .. 2)
                  or else (White_To_Move and then EK_Rank in 7 .. 8))
      then
         for F in 1 .. 64 loop
            if Pvalidade.Tabuleiro (F) = 20 * Own_Sign
              and then Move_Validation.File_Of (F) in 1 .. 3
            then
               for File_T in 1 .. 2 loop
                  declare
                     T : constant Integer := Move_Validation.Square_Of (Q_Target_R, File_T);
                  begin
                     if Pvalidade.Tabuleiro (T) = 0
                       and then Pvalidade.Validade (F, T)
                     then
                        Apply_Trial (F, T, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        Undo_Trial (F, T, 20 * Own_Sign, Saved_T);

                        if Legal
                          and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                          and then See_Gain (White_To_Move, F, T) >= 0
                          and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                          and then Max_Opponent_See_After (White_To_Move, F, T) <= 100
                          and then Is_Deep_Material_Safe_60 (White_To_Move, F, T)
                        then
                           From_Sq := F;
                           To_Sq   := T;
                           Found   := True;
                           return;
                        end if;
                     end if;
                  end;
               end loop;
            end if;
         end loop;
      end if;
   end Best_Flank_Queen_Infiltration;

   ----------------------------------------------------------------------------
   --  Best_Cramped_Central_Pawn_Break
   --  Breaks enemy advanced central pawn cramp (e5/d5 for White, e4/d4 for Black)
   --  by advancing adjacent friendly pawn (d7-d6 / e7-e6 for Black, d2-d3 / e2-e3 for White),
   --  activating blocked minor pieces.
   ----------------------------------------------------------------------------
   procedure Best_Cramped_Central_Pawn_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_T  : Integer;
      Legal    : Boolean;

      type Break_Pair is record
         Cramper_Sq : Integer;
         Pawn_From  : Integer;
         Pawn_To    : Integer;
         Back_Piece : Integer;
      end record;

      Pairs : constant array (1 .. 2) of Break_Pair :=
        (if White_To_Move then
           [(Cramper_Sq => Move_Validation.Square_Of (4, 5),   -- e4
             Pawn_From  => Move_Validation.Square_Of (2, 4),   -- d2
             Pawn_To    => Move_Validation.Square_Of (3, 4),   -- d3
             Back_Piece => Move_Validation.Square_Of (1, 3)),  -- c1
            (Cramper_Sq => Move_Validation.Square_Of (4, 4),   -- d4
             Pawn_From  => Move_Validation.Square_Of (2, 5),   -- e2
             Pawn_To    => Move_Validation.Square_Of (3, 5),   -- e3
             Back_Piece => Move_Validation.Square_Of (1, 6))]  -- f1
         else
           [(Cramper_Sq => Move_Validation.Square_Of (5, 5),   -- e5
             Pawn_From  => Move_Validation.Square_Of (7, 4),   -- d7
             Pawn_To    => Move_Validation.Square_Of (6, 4),   -- d6
             Back_Piece => Move_Validation.Square_Of (8, 3)),  -- c8
            (Cramper_Sq => Move_Validation.Square_Of (5, 4),   -- d5
             Pawn_From  => Move_Validation.Square_Of (7, 5),   -- e7
             Pawn_To    => Move_Validation.Square_Of (6, 5),   -- e6
             Back_Piece => Move_Validation.Square_Of (8, 6))]);-- f8
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Idx in Pairs'Range loop
         declare
            BP : constant Break_Pair := Pairs (Idx);
         begin
            if Pvalidade.Tabuleiro (BP.Cramper_Sq) = 1 * Opp_Sign
              and then Pvalidade.Tabuleiro (BP.Pawn_From) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (BP.Pawn_To) = 0
              and then abs Pvalidade.Tabuleiro (BP.Back_Piece) in 3 .. 4
              and then Pvalidade.Validade (BP.Pawn_From, BP.Pawn_To)
            then
               Apply_Trial (BP.Pawn_From, BP.Pawn_To, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (BP.Pawn_From, BP.Pawn_To, 1 * Own_Sign, Saved_T);

               if Legal
                 and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                 and then Is_Deep_Material_Safe_60 (White_To_Move, BP.Pawn_From, BP.Pawn_To)
               then
                  From_Sq := BP.Pawn_From;
                  To_Sq   := BP.Pawn_To;
                  Found   := True;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Best_Cramped_Central_Pawn_Break;

   ----------------------------------------------------------------------------
   --  Best_Knight_Fork_Parry_Reposition
   --  Reposition friendly knight (Nf6-d7 for Black, Nf3-d2 for White) to parry
   --  incoming enemy knight forks on c6/c3 and activate counter-play.
   ----------------------------------------------------------------------------
   procedure Best_Knight_Fork_Parry_Reposition
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Saved_T  : Integer;
      Legal    : Boolean;

      type Fork_Def is record
         Fork_Sq    : Integer;
         Cover_From : Integer;
         Cover_To   : Integer;
      end record;

      Defs : constant array (1 .. 2) of Fork_Def :=
        (if White_To_Move then
           [(Fork_Sq    => Move_Validation.Square_Of (3, 3),   -- c3
             Cover_From => Move_Validation.Square_Of (3, 6),   -- f3
             Cover_To   => Move_Validation.Square_Of (2, 4)),  -- d2
            (Fork_Sq    => Move_Validation.Square_Of (3, 6),   -- f3
             Cover_From => Move_Validation.Square_Of (3, 3),   -- c3
             Cover_To   => Move_Validation.Square_Of (2, 5))]  -- e2
         else
           [(Fork_Sq    => Move_Validation.Square_Of (6, 3),   -- c6
             Cover_From => Move_Validation.Square_Of (6, 6),   -- f6
             Cover_To   => Move_Validation.Square_Of (7, 4)),  -- d7
            (Fork_Sq    => Move_Validation.Square_Of (6, 6),   -- f6
             Cover_From => Move_Validation.Square_Of (6, 3),   -- c6
             Cover_To   => Move_Validation.Square_Of (7, 5))]);-- e7
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Idx in Defs'Range loop
         declare
            FD : constant Fork_Def := Defs (Idx);
            Fork_Threat : Boolean := False;
         begin
            for Sq in 1 .. 64 loop
               if Pvalidade.Tabuleiro (Sq) = 4 * Opp_Sign
                 and then Pvalidade.Validade (Sq, FD.Fork_Sq)
               then
                  Fork_Threat := True;
                  exit;
               end if;
            end loop;

            if Fork_Threat
              and then Pvalidade.Tabuleiro (FD.Cover_From) = 4 * Own_Sign
              and then Pvalidade.Tabuleiro (FD.Cover_To) = 0
              and then Pvalidade.Validade (FD.Cover_From, FD.Cover_To)
            then
               Apply_Trial (FD.Cover_From, FD.Cover_To, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (FD.Cover_From, FD.Cover_To, 4 * Own_Sign, Saved_T);

               if Legal
                 and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
                 and then See_Gain (White_To_Move, FD.Cover_From, FD.Cover_To) >= 0
                 and then Is_Deep_Material_Safe_60 (White_To_Move, FD.Cover_From, FD.Cover_To)
               then
                  From_Sq := FD.Cover_From;
                  To_Sq   := FD.Cover_To;
                  Found   := True;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Best_Knight_Fork_Parry_Reposition;

   ----------------------------------------------------------------------------
   --  Best_Sicilian_Najdorf_Queen_Develop
   --  Connects rooks and develops Queen to c7 (Black) or c2 (White) in
   --  Sicilian/asymmetric central structures, avoiding passive cramp.
   ----------------------------------------------------------------------------
   procedure Best_Sicilian_Najdorf_Queen_Develop
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Q_Home   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4); -- d1 or d8
      Q_Dest   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 3); -- c2 or c7
      R_A      : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 1); -- a1 or a8
      R_F      : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 6); -- f1 or f8
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (Q_Home) = 20 * Own_Sign
        and then Pvalidade.Tabuleiro (Q_Dest) = 0
        and then Pvalidade.Tabuleiro (R_A) = 7 * Own_Sign
        and then Pvalidade.Tabuleiro (R_F) = 7 * Own_Sign
        and then Pvalidade.Validade (Q_Home, Q_Dest)
      then
         Apply_Trial (Q_Home, Q_Dest, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Q_Home, Q_Dest, 20 * Own_Sign, Saved_T);

         if Legal
           and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
           and then See_Gain (White_To_Move, Q_Home, Q_Dest) >= 0
           and then Max_Opponent_See_After (White_To_Move, Q_Home, Q_Dest) = 0
           and then Is_Deep_Material_Safe_60 (White_To_Move, Q_Home, Q_Dest)
         then
            From_Sq := Q_Home;
            To_Sq   := Q_Dest;
            Found   := True;
         end if;
      end if;
   end Best_Sicilian_Najdorf_Queen_Develop;

   ----------------------------------------------------------------------------
   --  Best_Pinning_Bishop_Kick
   --  Kicks an enemy bishop that is pinning a friendly knight on d7/c6
   --  (e.g. Bb5 vs Nd7 in French/Nimzo) using a flank pawn push (a7-a6! / a2-a3!).
   ----------------------------------------------------------------------------
   procedure Best_Pinning_Bishop_Kick
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Enemy_Bishop : constant Integer := (if White_To_Move then -3 else 3);
      Own_Pawn     : constant Integer := (if White_To_Move then 1 else -1);
      Own_Knight   : constant Integer := (if White_To_Move then 4 else -4);
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if not White_To_Move then
         declare
            Bb5 : constant Integer := Move_Validation.Square_Of (5, 2);
            Nd7 : constant Integer := Move_Validation.Square_Of (7, 4);
            Nc6 : constant Integer := Move_Validation.Square_Of (6, 3);
            Pa7 : constant Integer := Move_Validation.Square_Of (7, 1);
            Pa6 : constant Integer := Move_Validation.Square_Of (6, 1);
            Bg5 : constant Integer := Move_Validation.Square_Of (5, 7);
            Pf7 : constant Integer := Move_Validation.Square_Of (7, 6);
            Pf6 : constant Integer := Move_Validation.Square_Of (6, 6);
         begin
            --  Kicking pinning/infiltrating Bishop on g5 with f7-f6!
            if Pvalidade.Tabuleiro (Bg5) = Enemy_Bishop
              and then Pvalidade.Tabuleiro (Pf7) = Own_Pawn
              and then Pvalidade.Tabuleiro (Pf6) = 0
              and then Pvalidade.Validade (Pf7, Pf6)
              and then See_Gain (White_To_Move, Pf7, Pf6) >= 0
            then
               Found   := True;
               From_Sq := Pf7;
               To_Sq   := Pf6;
               return;
            end if;

            if Pvalidade.Tabuleiro (Bb5) = Enemy_Bishop
              and then (Pvalidade.Tabuleiro (Nd7) = Own_Knight or else Pvalidade.Tabuleiro (Nc6) = Own_Knight)
              and then Pvalidade.Tabuleiro (Pa7) = Own_Pawn
              and then Pvalidade.Tabuleiro (Pa6) = 0
              and then Pvalidade.Validade (Pa7, Pa6)
              and then See_Gain (White_To_Move, Pa7, Pa6) >= 0
            then
               Found   := True;
               From_Sq := Pa7;
               To_Sq   := Pa6;
               return;
            end if;
         end;
      else
         declare
            Bb4 : constant Integer := Move_Validation.Square_Of (4, 2);
            Nd2 : constant Integer := Move_Validation.Square_Of (2, 4);
            Nc3 : constant Integer := Move_Validation.Square_Of (3, 3);
            Pa2 : constant Integer := Move_Validation.Square_Of (2, 1);
            Pa3 : constant Integer := Move_Validation.Square_Of (3, 1);
            Bg4 : constant Integer := Move_Validation.Square_Of (4, 7);
            Pf2 : constant Integer := Move_Validation.Square_Of (2, 6);
            Pf3 : constant Integer := Move_Validation.Square_Of (3, 6);
         begin
            --  Kicking pinning/infiltrating Bishop on g4 with f2-f3!
            if Pvalidade.Tabuleiro (Bg4) = Enemy_Bishop
              and then Pvalidade.Tabuleiro (Pf2) = Own_Pawn
              and then Pvalidade.Tabuleiro (Pf3) = 0
              and then Pvalidade.Validade (Pf2, Pf3)
              and then See_Gain (White_To_Move, Pf2, Pf3) >= 0
            then
               Found   := True;
               From_Sq := Pf2;
               To_Sq   := Pf3;
               return;
            end if;

            if Pvalidade.Tabuleiro (Bb4) = Enemy_Bishop
              and then (Pvalidade.Tabuleiro (Nd2) = Own_Knight or else Pvalidade.Tabuleiro (Nc3) = Own_Knight)
              and then Pvalidade.Tabuleiro (Pa2) = Own_Pawn
              and then Pvalidade.Tabuleiro (Pa3) = 0
              and then Pvalidade.Validade (Pa2, Pa3)
              and then See_Gain (White_To_Move, Pa2, Pa3) >= 0
            then
               Found   := True;
               From_Sq := Pa2;
               To_Sq   := Pa3;
               return;
            end if;
         end;
      end if;
   end Best_Pinning_Bishop_Kick;

   ----------------------------------------------------------------------------
   --  Best_Queen_Fork_Counter_Attack
   --  Executes active counter-attacking queen battery Qb6! (Black) / Qb3! (White)
   --  attacking b2/b7 and f2/f7 with unstoppable mating threats on uncastled king.
   ----------------------------------------------------------------------------
   procedure Best_Queen_Fork_Counter_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign        : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_Sign      : constant Integer := -Own_Sign;
      Q_Sq            : constant Integer := (if White_To_Move then Move_Validation.Square_Of (1, 4)
                                             else Move_Validation.Square_Of (8, 4)); -- d1 or d8
      Target_B_Sq     : constant Integer := (if White_To_Move then Move_Validation.Square_Of (3, 2)
                                             else Move_Validation.Square_Of (6, 2)); -- b3 or b6
      Enemy_B_Pawn    : constant Integer := (if White_To_Move then Move_Validation.Square_Of (7, 2)
                                             else Move_Validation.Square_Of (2, 2)); -- b7 or b2
      Enemy_F_Pawn    : constant Integer := (if White_To_Move then Move_Validation.Square_Of (7, 6)
                                             else Move_Validation.Square_Of (2, 6)); -- f7 or f2
      Enemy_King_Sq   : constant Integer := (if White_To_Move then 61 else 5);       -- e8 or e1
      Saved_T         : Integer;
      Legal           : Boolean;
      Diagonal_Clear  : Boolean;
      File_Clear      : Boolean;
      Partner_Attacks : Boolean := False;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      --  Friendly Queen on d1 (White) or d8 (Black)
      if Pvalidade.Tabuleiro (Q_Sq) /= 20 * Own_Sign then
         return;
      end if;

      --  Target square b3 (White) or b6 (Black) is empty and reachable
      if Pvalidade.Tabuleiro (Target_B_Sq) /= 0
        or else not Pvalidade.Validade (Q_Sq, Target_B_Sq)
      then
         return;
      end if;

      --  Enemy King on uncastled home square e8 (White) or e1 (Black)
      if Pvalidade.Tabuleiro (Enemy_King_Sq) /= 999 * Enemy_Sign then
         return;
      end if;

      --  Enemy b-pawn on b7 (White) or b2 (Black)
      if Pvalidade.Tabuleiro (Enemy_B_Pawn) /= Enemy_Sign then
         return;
      end if;

      --  Check that b-file is clear between Target_B_Sq and Enemy_B_Pawn
      File_Clear := True;
      if White_To_Move then
         for R in 4 .. 6 loop
            if Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 2)) /= 0 then
               File_Clear := False;
               exit;
            end if;
         end loop;
      else
         for R in 3 .. 5 loop
            if Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 2)) /= 0 then
               File_Clear := False;
               exit;
            end if;
         end loop;
      end if;

      if not File_Clear then
         return;
      end if;

      --  Check diagonal between Target_B_Sq and Enemy_F_Pawn:
      --  For White: b3 -> c4, d5, e6 -> f7
      --  For Black: b6 -> c5, d4, e3 -> f2
      Diagonal_Clear := True;
      if White_To_Move then
         for Step in 1 .. 3 loop
            if Pvalidade.Tabuleiro (Move_Validation.Square_Of (3 + Step, 2 + Step)) /= 0 then
               Diagonal_Clear := False;
               exit;
            end if;
         end loop;
      else
         for Step in 1 .. 3 loop
            if Pvalidade.Tabuleiro (Move_Validation.Square_Of (6 - Step, 2 + Step)) /= 0 then
               Diagonal_Clear := False;
               exit;
            end if;
         end loop;
      end if;

      if not Diagonal_Clear then
         return;
      end if;

      --  Check if a friendly minor piece also attacks f7 (White) or f2 (Black)
      for F in 1 .. 64 loop
         declare
            P : constant Integer := Pvalidade.Tabuleiro (F);
         begin
            if abs P in 3 .. 4
              and then P * Own_Sign > 0
              and then Pvalidade.Validade (F, Enemy_F_Pawn)
            then
               Partner_Attacks := True;
               exit;
            end if;
         end;
      end loop;

      if not Partner_Attacks then
         return;
      end if;

      --  Verify move safety
      Apply_Trial (Q_Sq, Target_B_Sq, Saved_T);
      Legal := not Move_Validation.Is_In_Check (White_To_Move);
      Undo_Trial (Q_Sq, Target_B_Sq, 20 * Own_Sign, Saved_T);

      if Legal
        and then not Has_Forced_Mate_Within_Two (Attacker_White => not White_To_Move)
        and then See_Gain (White_To_Move, Q_Sq, Target_B_Sq) >= 0
      then
         Found   := True;
         From_Sq := Q_Sq;
         To_Sq   := Target_B_Sq;
      end if;
   end Best_Queen_Fork_Counter_Attack;

   ----------------------------------------------------------------------------
   --  Best_Attacked_Queen_Zwischenzug_Push
   --  When friendly Queen is attacked by an enemy minor piece, executes an
   --  intermediate pawn advance that attacks the enemy Queen with tempo (c5-c4!).
   ----------------------------------------------------------------------------
   procedure Best_Attacked_Queen_Zwischenzug_Push
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Queen_Code : constant Integer := (if White_To_Move then 20 else -20);
      Opp_Queen_Code : constant Integer := -Own_Queen_Code;
      Own_Pawn_Code  : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign       : constant Integer := (if White_To_Move then -1 else 1);
      Pawn_Dir       : constant Integer := (if White_To_Move then 1 else -1);
      Q_Sq           : Integer := 0;
      Opp_Q_Sq       : Integer := 0;
      Q_Attacked     : Boolean := False;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = Own_Queen_Code then
            Q_Sq := Sq;
         elsif Pvalidade.Tabuleiro (Sq) = Opp_Queen_Code then
            Opp_Q_Sq := Sq;
         end if;
      end loop;

      if Q_Sq = 0 or else Opp_Q_Sq = 0 then
         return;
      end if;

      for Opp_Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Opp_Sq) * Opp_Sign > 0
           and then Pvalidade.Validade (Opp_Sq, Q_Sq)
         then
            Q_Attacked := True;
            exit;
         end if;
      end loop;

      if not Q_Attacked then
         return;
      end if;

      for P_Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (P_Sq) = Own_Pawn_Code then
            declare
               P_R : constant Integer := Move_Validation.Rank_Of (P_Sq);
               P_F : constant Integer := Move_Validation.File_Of (P_Sq);
               Adv_R : constant Integer := P_R + Pawn_Dir;
            begin
               if Adv_R in 1 .. 8 then
                  declare
                     Adv_Sq : constant Integer := Move_Validation.Square_Of (Adv_R, P_F);
                  begin
                     if Pvalidade.Tabuleiro (Adv_Sq) = 0
                       and then Pvalidade.Validade (P_Sq, Adv_Sq)
                     then
                        declare
                           Opp_Q_R : constant Integer := Move_Validation.Rank_Of (Opp_Q_Sq);
                           Opp_Q_F : constant Integer := Move_Validation.File_Of (Opp_Q_Sq);
                        begin
                           if Opp_Q_R = Adv_R + Pawn_Dir
                             and then abs (Opp_Q_F - P_F) = 1
                           then
                              if See_Gain (White_To_Move, P_Sq, Adv_Sq) >= 0
                                and then (not Pvalidade.Validade (Opp_Q_Sq, Adv_Sq)
                                          or else See_Gain (not White_To_Move, Opp_Q_Sq, Adv_Sq) <= 0)
                              then
                                 Found   := True;
                                 From_Sq := P_Sq;
                                 To_Sq   := Adv_Sq;
                                 return;
                              end if;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Best_Attacked_Queen_Zwischenzug_Push;

   ----------------------------------------------------------------------------
   --  Best_Rook_Cramping_Pawn_Pressure
   --  In middlegame/endgame, positions rook on 5th rank (b6-b5 / b3-b4) to
   --  horizontally attack an enemy advanced cramping central pawn (e5/d5).
   ----------------------------------------------------------------------------
   procedure Best_Rook_Cramping_Pawn_Pressure
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Rook_Code : constant Integer := (if White_To_Move then 7 else -7);
      Opp_Pawn_Code : constant Integer := (if White_To_Move then -1 else 1);
      Target_Rank   : constant Integer := (if White_To_Move then 4 else 5);
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Central_File in 4 .. 5 loop
         declare
            Cen_Pawn_Sq : constant Integer := Move_Validation.Square_Of (Target_Rank, Central_File);
         begin
            if Pvalidade.Tabuleiro (Cen_Pawn_Sq) = Opp_Pawn_Code then
               for R_Sq in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (R_Sq) = Own_Rook_Code then
                     for F in 1 .. 8 loop
                        if F /= Central_File then
                           declare
                              T_Sq : constant Integer := Move_Validation.Square_Of (Target_Rank, F);
                           begin
                              if Pvalidade.Tabuleiro (T_Sq) = 0
                                and then Pvalidade.Validade (R_Sq, T_Sq)
                                and then not Is_Square_Attacked_By_Pawn (White_To_Move, T_Sq)
                                and then See_Gain (White_To_Move, R_Sq, T_Sq) >= 0
                              then
                                 Found   := True;
                                 From_Sq := R_Sq;
                                 To_Sq   := T_Sq;
                                 return;
                              end if;
                           end;
                        end if;
                     end loop;
                  end if;
               end loop;
            end if;
         end;
      end loop;
   end Best_Rook_Cramping_Pawn_Pressure;

   ----------------------------------------------------------------------------
   --  Best_King_Unpin_Step
   --  Unpins friendly king from an open or semi-open file where an enemy rook
   --  faces the king, stepping to a safe adjacent square (e.g. g7-f7!).
   ----------------------------------------------------------------------------
   procedure Best_King_Unpin_Step
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_King_Code : constant Integer := (if White_To_Move then 999 else -999);
      Opp_Rook_Code : constant Integer := (if White_To_Move then -7 else 7);
      King_Sq       : Integer := 0;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = Own_King_Code then
            King_Sq := Sq;
            exit;
         end if;
      end loop;

      if King_Sq = 0 then
         return;
      end if;

      --  An uncastled king on its original home square (e1 for White, e8 for Black)
      --  must never make a quiet unpin step; doing so surrenders castling rights.
      if King_Sq = (if White_To_Move then 5 else 61) then
         return;
      end if;

      declare
         K_Rank : constant Integer := Move_Validation.Rank_Of (King_Sq);
         K_File : constant Integer := Move_Validation.File_Of (King_Sq);
         Rook_Facing : Boolean := False;
      begin
         for R in 1 .. 8 loop
            declare
               Sq : constant Integer := Move_Validation.Square_Of (R, K_File);
            begin
               if Pvalidade.Tabuleiro (Sq) = Opp_Rook_Code then
                  Rook_Facing := True;
                  exit;
               end if;
            end;
         end loop;

         if Rook_Facing then
            declare
               Pawn_R         : constant Integer := (if White_To_Move then 2 else 7);
               Shield_Pawn_Sq : constant Integer := Move_Validation.Square_Of (Pawn_R, K_File);
            begin
               if Pvalidade.Tabuleiro (Shield_Pawn_Sq) = (if White_To_Move then 1 else -1) then
                  return; -- King is safely behind its home pawn shield
               end if;
            end;

            for DF in -1 .. 1 loop
               if DF /= 0 and then K_File + DF in 1 .. 8 then
                  declare
                     T_Sq : constant Integer := Move_Validation.Square_Of (K_Rank, K_File + DF);
                  begin
                     if Pvalidade.Tabuleiro (T_Sq) = 0
                       and then Pvalidade.Validade (King_Sq, T_Sq)
                       and then not Move_Validation.Is_Square_Attacked (T_Sq, By_White => not White_To_Move)
                       and then not Is_Square_Attacked_By_Pawn (White_To_Move, T_Sq)
                       and then Max_Opponent_See_After (White_To_Move, King_Sq, T_Sq) <=
                                Max_Opponent_See (White_To_Move, Except_Sq => 0)
                     then
                        Found   := True;
                        From_Sq := King_Sq;
                        To_Sq   := T_Sq;
                        return;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end;
   end Best_King_Unpin_Step;

   procedure Best_Defend_Knight_C_Pawn_Fork
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Target_C_Sq : constant Integer := (if White_To_Move then 11 else 51); -- c2 or c7
      King_Sq     : constant Integer := (if White_To_Move then 5 else 61);   -- e1 or e8
      Rook_Sq     : constant Integer := (if White_To_Move then 1 else 57);   -- a1 or a8
      Attacking_Knight_Found : Boolean := False;
      Knight_Sq : Integer := 0;
      Piece, Saved_T : Integer;
      Legal : Boolean;

      function Knight_Leap (Sq1, Sq2 : Integer) return Boolean is
         dF : constant Integer := abs (Move_Validation.File_Of (Sq1) - Move_Validation.File_Of (Sq2));
         dR : constant Integer := abs (Move_Validation.Rank_Of (Sq1) - Move_Validation.Rank_Of (Sq2));
      begin
         return (dF = 1 and dR = 2) or else (dF = 2 and dR = 1);
      end Knight_Leap;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (King_Sq) /= 999 * Own_Sign
        or else Pvalidade.Tabuleiro (Rook_Sq) /= 7 * Own_Sign
      then
         return;
      end if;

      for Sq in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (Sq);
         if Piece * Own_Sign < 0
           and then abs Piece = 4
           and then Pvalidade.Validade (Sq, Target_C_Sq)
         then
            Attacking_Knight_Found := True;
            Knight_Sq := Sq;
            exit;
         end if;
      end loop;

      if not Attacking_Knight_Found then
         return;
      end if;

      if not (Knight_Leap (Target_C_Sq, King_Sq) and then Knight_Leap (Target_C_Sq, Rook_Sq)) then
         return;
      end if;

      if Move_Validation.Is_Square_Attacked (Target_C_Sq, By_White => White_To_Move) then
         return;
      end if;

      for F in 1 .. 64 loop
         Piece := Pvalidade.Tabuleiro (F);
         if Piece * Own_Sign > 0 and then abs Piece /= 999 then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
               then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);

                  if Legal then
                     if T = Knight_Sq
                       or else Move_Validation.Is_Square_Attacked (Target_C_Sq, By_White => White_To_Move)
                     then
                        From_Sq := F;
                        To_Sq := T;
                        Found := True;
                     end if;
                  end if;

                  Undo_Trial (F, T, Piece, Saved_T);
                  exit when Found and then abs Piece = 4;
               end if;
            end loop;
         end if;
         exit when Found and then abs Piece = 4;
      end loop;
   end Best_Defend_Knight_C_Pawn_Fork;

   procedure Best_Check_Evasion
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign     : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq      : Integer;
      Checker_Sq   : Integer := 0;
      Num_Checkers : Integer := 0;
      Cand_List    : Root_Candidate_List;
      Best_Score   : Integer := -999999;
      Score        : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if not Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      Best_Passed_Pawn_Blockade_King_Step (White_To_Move, Found, From_Sq, To_Sq);
      if Found then
         return;
      end if;

      King_Sq := Move_Validation.Find_King (White_To_Move);
      if King_Sq = 0 then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) * Own_Sign < 0
           and then Pvalidade.Validade (Sq, King_Sq)
         then
            Num_Checkers := Num_Checkers + 1;
            Checker_Sq   := Sq;
         end if;
      end loop;

      Snapshot_Legal_Root_Candidates (White_To_Move, Cand_List);
      if Cand_List.Count = 0 then
         return;
      end if;

      for I in 1 .. Cand_List.Count loop
         declare
            C : Root_Candidate renames Cand_List.Candidates (I);
            F : constant Integer := C.From_Sq;
            T : constant Integer := C.To_Sq;
            Piece : constant Integer := Pvalidade.Tabuleiro (F);
            Saved_T : constant Integer := Pvalidade.Tabuleiro (T);
            Fork : Boolean;
            Attacks_Checker : Boolean := False;
            Gain : Integer;
         begin
            Gain := See_Gain (White_To_Move, F, T);
            Score := Gain;

            Pvalidade.Tabuleiro (F) := 0;
            Pvalidade.Tabuleiro (T) := Piece;

            Fork := Has_Opponent_Checking_Fork (White_To_Move, T);
            if Checker_Sq /= 0 and Num_Checkers = 1 then
               Attacks_Checker := Pvalidade.Validade (T, Checker_Sq);
            end if;

            declare
               Eval_Val : constant Integer := Evaluate;
               Eval_Oriented : constant Integer := (if White_To_Move then Eval_Val else -Eval_Val);
               Rank_T : constant Integer := Move_Validation.Rank_Of (T);
            begin
               Score := Score + Eval_Oriented;

               if Fork then
                  Score := Score - 10000;
               end if;

               if Saved_T /= 0
                 and then abs Piece > abs Saved_T
                 and then Move_Validation.Is_Square_Attacked (T, By_White => not White_To_Move)
               then
                  Score := Score - 2000;
               end if;

               if abs Piece = 999 then
                  if Attacks_Checker then
                     Score := Score + 120;
                  end if;
                  if Rank_T in 3 .. 6 then
                     Score := Score - 200;
                  end if;
                  if (White_To_Move and Rank_T = 1) or (not White_To_Move and Rank_T = 8) then
                     Score := Score + 30;
                  end if;
               else
                  --  Interposing piece that counter-attacks the checker (e.g. Bd2 attacking Qc3)
                  --  develops with tempo, defends the king, and preserves castling rights.
                  if Attacks_Checker then
                     Score := Score + 150;
                  end if;
               end if;
            end;

            Pvalidade.Tabuleiro (F) := Piece;
            Pvalidade.Tabuleiro (T) := Saved_T;

            if Score > Best_Score then
               Best_Score := Score;
               From_Sq := F;
               To_Sq := T;
               Found := True;
            end if;
         end;
      end loop;
   end Best_Check_Evasion;

   procedure Best_Central_King_Safety_Tuck
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign      : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq       : constant Integer := Move_Validation.Find_King (White_To_Move);
      KR, KF        : Integer;
      Queen_Found   : Boolean := False;
      Target_Rank   : constant Integer := (if White_To_Move then 2 else 7);
      B_Pawn_Sq     : constant Integer := (if White_To_Move then 10 else 50); -- b2 or b7
      B_Pawn_Pushed : Boolean;
      Dest_C_Sq, Dest_E_Sq : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if King_Sq = 0 then
         return;
      end if;

      KR := Move_Validation.Rank_Of (King_Sq);
      KF := Move_Validation.File_Of (King_Sq);

      --  0.9.9.17.29: King displaced to f1 / f8 (file 6, home rank), unable to castle.
      --  Tuck King to g2 / g7 to connect rooks and secure the king behind pawns.
      if KR = (if White_To_Move then 1 else 8) and then KF = 6 then
         declare
            Dest_G_Sq : constant Integer := Move_Validation.Square_Of (Target_Rank, 7);
            G_Pawn_Sq : constant Integer :=
              Move_Validation.Square_Of (Target_Rank + (if White_To_Move then 1 else -1), 7);
         begin
            if Pvalidade.Tabuleiro (Dest_G_Sq) = 0
              and then Pvalidade.Validade (King_Sq, Dest_G_Sq)
              and then not Move_Validation.Is_Square_Attacked (Dest_G_Sq, By_White => not White_To_Move)
              and then Pvalidade.Tabuleiro (G_Pawn_Sq) = 1 * Own_Sign
            then
               From_Sq := King_Sq;
               To_Sq   := Dest_G_Sq;
               Found   := True;
               return;
            end if;
         end;
      end if;

      if (White_To_Move and KR /= 3) or else (not White_To_Move and KR /= 6) then
         return;
      end if;
      if KF /= 4 then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = -20 * Own_Sign then
            Queen_Found := True;
            exit;
         end if;
      end loop;
      if not Queen_Found then
         return;
      end if;

      B_Pawn_Pushed := (Pvalidade.Tabuleiro (B_Pawn_Sq) /= 1 * Own_Sign);
      Dest_C_Sq     := Move_Validation.Square_Of (Target_Rank, 3);
      Dest_E_Sq     := Move_Validation.Square_Of (Target_Rank, 5);

      if not B_Pawn_Pushed then
         if Pvalidade.Validade (King_Sq, Dest_C_Sq)
           and then not Move_Validation.Is_Square_Attacked (Dest_C_Sq, By_White => not White_To_Move)
         then
            From_Sq := King_Sq;
            To_Sq   := Dest_C_Sq;
            Found   := True;
            return;
         end if;
      else
         if Pvalidade.Validade (King_Sq, Dest_E_Sq)
           and then not Move_Validation.Is_Square_Attacked (Dest_E_Sq, By_White => not White_To_Move)
         then
            From_Sq := King_Sq;
            To_Sq   := Dest_E_Sq;
            Found   := True;
            return;
         end if;
      end if;

      if Pvalidade.Validade (King_Sq, Dest_C_Sq)
        and then not Move_Validation.Is_Square_Attacked (Dest_C_Sq, By_White => not White_To_Move)
      then
         From_Sq := King_Sq;
         To_Sq   := Dest_C_Sq;
         Found   := True;
      elsif Pvalidade.Validade (King_Sq, Dest_E_Sq)
        and then not Move_Validation.Is_Square_Attacked (Dest_E_Sq, By_White => not White_To_Move)
      then
         From_Sq := King_Sq;
         To_Sq   := Dest_E_Sq;
         Found   := True;
      end if;
   end Best_Central_King_Safety_Tuck;

   procedure Best_Queen_Skewer_Escape
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Opp            : constant Boolean := not White_To_Move;
      Own_Sign       : constant Integer := (if White_To_Move then 1 else -1);
      Queen_Sq       : Integer := 0;
      Threat_T       : Integer := 0;
      Saved_T        : Integer;
      Attacker_Found : Boolean := False;

      function Destination_Hangs (Target : Integer) return Boolean is
      begin
         for S in 1 .. 64 loop
            if Side_Piece (Pvalidade.Tabuleiro (S), White_To_Move) then
               if Pvalidade.Validade (S, Target)
                 and then See_Gain (White_To_Move, S, Target) > 100
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Destination_Hangs;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = 20 * Own_Sign then
            Queen_Sq := Sq;
            exit;
         end if;
      end loop;
      if Queen_Sq = 0 then
         return;
      end if;

      Enemy_Search:
      for F in 1 .. 64 loop
         if Side_Piece (Pvalidade.Tabuleiro (F), Opp)
           and then abs Pvalidade.Tabuleiro (F) in 3 .. 20
           and then abs Pvalidade.Tabuleiro (F) /= 4
         then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) and then See_Gain (Opp, F, T) >= 0 then
                  Apply_Trial (F, T, Saved_T);
                  if not Move_Validation.Is_In_Check (Opp)
                    and then not Destination_Hangs (T)
                    and then Pvalidade.Validade (T, Queen_Sq)
                  then
                     declare
                        Saved_Q : constant Integer := Pvalidade.Tabuleiro (Queen_Sq);
                        Skewer_Target : Integer := 0;
                     begin
                        Pvalidade.Tabuleiro (Queen_Sq) := 0;
                        for Rear_Sq in 1 .. 64 loop
                           if Rear_Sq /= Queen_Sq
                             and then Pvalidade.Tabuleiro (Rear_Sq) * Own_Sign > 0
                             and then abs Pvalidade.Tabuleiro (Rear_Sq) in 3 .. 999
                             and then Pvalidade.Validade (T, Rear_Sq)
                           then
                              Skewer_Target := Rear_Sq;
                              exit;
                           end if;
                        end loop;
                        Pvalidade.Tabuleiro (Queen_Sq) := Saved_Q;

                        if Skewer_Target /= 0 then
                           Threat_T       := T;
                           Attacker_Found := True;
                           Undo_Trial (F, T, Pvalidade.Tabuleiro (T), Saved_T);
                           exit Enemy_Search;
                        end if;
                     end;
                  end if;
                  Undo_Trial (F, T, Pvalidade.Tabuleiro (T), Saved_T);
               end if;
            end loop;
         end if;
      end loop Enemy_Search;

      if not Attacker_Found then
         return;
      end if;

      declare
         Best_Score      : Integer := -10000;
         Candidate_Score : Integer;
         Q_Saved         : Integer;
      begin
         for Dest in 1 .. 64 loop
            if Pvalidade.Tabuleiro (Dest) * Own_Sign <= 0
              and then Pvalidade.Validade (Queen_Sq, Dest)
              and then See_Gain (White_To_Move, Queen_Sq, Dest) >= 0
            then
               Apply_Trial (Queen_Sq, Dest, Q_Saved);
               if not Move_Validation.Is_In_Check (White_To_Move)
                 and then Max_Opponent_See (White_To_Move) <= 0
                 and then not Has_Opponent_Double_Attack (White_To_Move, Target_Sq => Dest)
               then
                  Candidate_Score := 0;
                  if Pvalidade.Validade (Dest, Threat_T) then
                     Candidate_Score := Candidate_Score + 200;
                  end if;
                  declare
                     R : constant Integer := Move_Validation.Rank_Of (Dest);
                     F : constant Integer := Move_Validation.File_Of (Dest);
                  begin
                     if R in 3 .. 6 and then F in 3 .. 6 then
                        Candidate_Score := Candidate_Score + 50;
                     end if;
                     if (White_To_Move and then R = 3) or else (not White_To_Move and then R = 6) then
                        Candidate_Score := Candidate_Score + 100;
                     end if;
                     if (White_To_Move and then Dest = Move_Validation.Square_Of (3, 6))
                       or else (not White_To_Move and then Dest = Move_Validation.Square_Of (6, 6))
                     then
                        Candidate_Score := Candidate_Score + 250;
                     end if;
                  end;
                  if Candidate_Score > Best_Score then
                     Best_Score := Candidate_Score;
                     From_Sq    := Queen_Sq;
                     To_Sq      := Dest;
                     Found      := True;
                  end if;
               end if;
               Undo_Trial (Queen_Sq, Dest, 20 * Own_Sign, Q_Saved);
            end if;
         end loop;
      end;
   end Best_Queen_Skewer_Escape;

   procedure Best_King_Pin_Shield
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq  : constant Integer := Move_Validation.Find_King (White_To_Move);
      Saved_T  : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if King_Sq = 0 then
         return;
      end if;

      for Opp_F in 1 .. 64 loop
         declare
            Att_Piece : constant Integer := Pvalidade.Tabuleiro (Opp_F);
         begin
            if Att_Piece * Own_Sign < 0 and then abs Att_Piece in 5 .. 20 then
               declare
                  DR : constant Integer :=
                    Move_Validation.Rank_Of (King_Sq) - Move_Validation.Rank_Of (Opp_F);
                  DF : constant Integer :=
                    Move_Validation.File_Of (King_Sq) - Move_Validation.File_Of (Opp_F);
                  Step_R, Step_F : Integer := 0;
                  Dist : Integer := 0;
               begin
                  if DR = 0 and then DF /= 0 then
                     Step_F := (if DF > 0 then 1 else -1);
                     Dist   := abs DF;
                  elsif DF = 0 and then DR /= 0 then
                     Step_R := (if DR > 0 then 1 else -1);
                     Dist   := abs DR;
                  elsif abs DR = abs DF and then DR /= 0 then
                     Step_R := (if DR > 0 then 1 else -1);
                     Step_F := (if DF > 0 then 1 else -1);
                     Dist   := abs DR;
                  end if;

                  if Dist > 1 then
                     declare
                        Pinned_Count : Natural := 0;
                        Pinned_Sq    : Integer := 0;
                        Intervene_Sq : Integer;
                        Cur_R        : Integer := Move_Validation.Rank_Of (Opp_F);
                        Cur_F        : Integer := Move_Validation.File_Of (Opp_F);
                     begin
                        for Step in 1 .. Dist - 1 loop
                           Cur_R := Cur_R + Step_R;
                           Cur_F := Cur_F + Step_F;
                           Intervene_Sq := Move_Validation.Square_Of (Cur_R, Cur_F);
                           if Pvalidade.Tabuleiro (Intervene_Sq) /= 0 then
                              if Pvalidade.Tabuleiro (Intervene_Sq) * Own_Sign > 0 then
                                 Pinned_Count := Pinned_Count + 1;
                                 Pinned_Sq    := Intervene_Sq;
                              else
                                 Pinned_Count := 99;
                              end if;
                           end if;
                        end loop;

                        if Pinned_Count = 1 then
                           Cur_R := Move_Validation.Rank_Of (Opp_F);
                           Cur_F := Move_Validation.File_Of (Opp_F);
                           for Step in 1 .. Dist - 1 loop
                              Cur_R := Cur_R + Step_R;
                              Cur_F := Cur_F + Step_F;
                              Intervene_Sq := Move_Validation.Square_Of (Cur_R, Cur_F);
                              if Pvalidade.Tabuleiro (Intervene_Sq) = 0 then
                                 for Pawn_Sq in 1 .. 64 loop
                                    if Pawn_Sq /= Pinned_Sq
                                      and then Pvalidade.Tabuleiro (Pawn_Sq) = 1 * Own_Sign
                                      and then Pvalidade.Validade (Pawn_Sq, Intervene_Sq)
                                      and then See_Gain (White_To_Move, Pawn_Sq, Intervene_Sq) >= 0
                                    then
                                       Apply_Trial (Pawn_Sq, Intervene_Sq, Saved_T);
                                       if not Move_Validation.Is_In_Check (White_To_Move)
                                         and then Max_Opponent_See (White_To_Move) <= 0
                                       then
                                          From_Sq := Pawn_Sq;
                                          To_Sq   := Intervene_Sq;
                                          Found   := True;
                                          Undo_Trial (Pawn_Sq, Intervene_Sq, 1 * Own_Sign, Saved_T);
                                          return;
                                       end if;
                                       Undo_Trial (Pawn_Sq, Intervene_Sq, 1 * Own_Sign, Saved_T);
                                    end if;
                                 end loop;
                              end if;
                           end loop;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Best_King_Pin_Shield;

   procedure Best_Rook_Open_File_Facing_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign         : constant Integer := (if White_To_Move then 1 else -1);
      Home_R           : constant Integer := (if White_To_Move then 1 else 8);
      Enemy_Queen_Sq   : Integer := 0;
      QF               : Integer := 0;
      Target_Sq        : Integer;
      Has_Pawn_Between : Boolean := False;
      Min_R, Max_R     : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = -20 * Own_Sign then
            Enemy_Queen_Sq := Sq;
            QF := Move_Validation.File_Of (Sq);
            exit;
         end if;
      end loop;

      if QF in 4 .. 5 then
         Target_Sq := Move_Validation.Square_Of (Home_R, QF);
         if Pvalidade.Tabuleiro (Target_Sq) = 0 then
            Min_R := Integer'Min (Home_R, Move_Validation.Rank_Of (Enemy_Queen_Sq));
            Max_R := Integer'Max (Home_R, Move_Validation.Rank_Of (Enemy_Queen_Sq));
            for R in Min_R + 1 .. Max_R - 1 loop
               if abs Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, QF)) = 1 then
                  Has_Pawn_Between := True;
                  exit;
               end if;
            end loop;

            if not Has_Pawn_Between then
               for Sq in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Sq) = 7 * Own_Sign
                    and then Move_Validation.Rank_Of (Sq) = Home_R
                    and then Pvalidade.Validade (Sq, Target_Sq)
                  then
                     From_Sq := Sq;
                     To_Sq   := Target_Sq;
                     Found   := True;
                     exit;
                  end if;
               end loop;
            end if;
         end if;
      end if;
   end Best_Rook_Open_File_Facing_Queen;

   procedure Best_Defend_Central_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_White : constant Boolean := not White_To_Move;
      Central_P1  : constant Integer := (if White_To_Move then 29 else 37); -- e4 / e5
      Central_P2  : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
      Central_P3  : constant Integer := (if White_To_Move then 36 else 28); -- d5 / d4
      Central_P4  : constant Integer := (if White_To_Move then 37 else 29); -- e5 / e4
      Candidate_P : Integer := 0;
      Best_Score  : Integer := -9999;
      Score       : Integer;

      function Is_Central_Pawn_Hanging (P_Sq : Integer) return Boolean is
      begin
         if Pvalidade.Tabuleiro (P_Sq) /= 1 * Own_Sign then
            return False;
         end if;
         for Att_Sq in 1 .. 64 loop
            if Pvalidade.Tabuleiro (Att_Sq) /= 0
              and then (Pvalidade.Tabuleiro (Att_Sq) > 0) = Enemy_White
              and then Pvalidade.Validade (Att_Sq, P_Sq)
            then
               if See_Gain (White_Captures => Enemy_White, From_Sq => Att_Sq, To_Sq => P_Sq) > 0 then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Is_Central_Pawn_Hanging;

      Saved_T, Moved_Piece : Integer;
      Legal : Boolean;
      Still_Hangs : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;

      if Is_Central_Pawn_Hanging (Central_P1) then
         Candidate_P := Central_P1;
      elsif Is_Central_Pawn_Hanging (Central_P2) then
         Candidate_P := Central_P2;
      elsif Is_Central_Pawn_Hanging (Central_P3) then
         Candidate_P := Central_P3;
      elsif Is_Central_Pawn_Hanging (Central_P4) then
         Candidate_P := Central_P4;
      else
         return;
      end if;

      for F in 1 .. 64 loop
         Moved_Piece := Pvalidade.Tabuleiro (F);
         if Moved_Piece /= 0 and then (Moved_Piece > 0) = White_To_Move and then F /= Candidate_P then
            for T in 1 .. 64 loop
               if Pvalidade.Tabuleiro (T) = 0 and then Pvalidade.Validade (F, T) then
                  Apply_Trial (F, T, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move);
                  Still_Hangs := False;

                  if Legal then
                     for Att_Sq in 1 .. 64 loop
                        if Pvalidade.Tabuleiro (Att_Sq) /= 0
                          and then (Pvalidade.Tabuleiro (Att_Sq) > 0) = Enemy_White
                          and then Pvalidade.Validade (Att_Sq, Candidate_P)
                        then
                           if See_Gain (White_Captures => Enemy_White, From_Sq => Att_Sq, To_Sq => Candidate_P) > 0 then
                              Still_Hangs := True;
                              exit;
                           end if;
                        end if;
                     end loop;

                     declare
                        T_Hangs : Boolean := False;
                     begin
                        for Att_Sq in 1 .. 64 loop
                           if Pvalidade.Tabuleiro (Att_Sq) /= 0
                             and then (Pvalidade.Tabuleiro (Att_Sq) > 0) = Enemy_White
                             and then Pvalidade.Validade (Att_Sq, T)
                           then
                              if See_Gain (White_Captures => Enemy_White, From_Sq => Att_Sq, To_Sq => T) > 0 then
                                 T_Hangs := True;
                                 exit;
                              end if;
                           end if;
                        end loop;

                        if not Still_Hangs and then not T_Hangs then
                           if not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                             and then not Has_Opponent_Checking_Fork (White_To_Move, T)
                           then
                              Score := 0;
                           declare
                              Home_R : constant Integer := (if White_To_Move then 1 else 8);
                              Pawn_R : constant Integer := (if White_To_Move then 2 else 7);
                              FR : constant Integer := Move_Validation.Rank_Of (F);
                              TF : constant Integer := Move_Validation.File_Of (T);
                           begin
                              if abs Moved_Piece = 20 and then TF = 4 then
                                 Score := 220; -- Qd2 / Qd7 defending central pawn
                              elsif abs Moved_Piece = 4 and then FR = Home_R and then (TF = 3 or else TF = 6) then
                                 Score := 200; -- Nc3 / Nc6 / Nf3 / Nf6
                              elsif abs Moved_Piece = 4 then
                                 Score := 150;
                              elsif abs Moved_Piece = 3 then
                                 Score := 170;
                              elsif abs Moved_Piece = 1 and then FR = Pawn_R then
                                 declare
                                    King_Sq : constant Integer := Move_Validation.Find_King (White_To_Move);
                                 begin
                                    if Move_Validation.File_Of (F) = 3
                                      and then (King_Sq = Move_Validation.Square_Of (Home_R, 3)
                                                or else King_Sq = Move_Validation.Square_Of (Home_R, 2))
                                    then
                                       Score := 0; -- Do not strip castled king's pawn shield
                                    else
                                       Score := 160; -- d3 / d6 / c4 / c5
                                    end if;
                                 end;
                              else
                                 Score := 100;
                              end if;
                           end;

                           if Score > Best_Score then
                              Best_Score := Score;
                              From_Sq := F;
                              To_Sq := T;
                              Found := True;
                           end if;
                        end if;
                     end if;
                     end;
                  end if;

                  Undo_Trial (F, T, Moved_Piece, Saved_T);
               end if;
            end loop;
         end if;
      end loop;
   end Best_Defend_Central_Pawn;

   function Allows_Major_Pin
     (White_To_Move : Boolean;
      Target_Sq     : Integer;
      Attacker_Sq   : Integer := 0) return Boolean
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq  : constant Integer := Move_Validation.Find_King (White_To_Move);

      function Check_Pin (Att_Sq : Integer) return Boolean is
         Att_P : constant Integer := (if Att_Sq in 1 .. 64 then Pvalidade.Tabuleiro (Att_Sq) else 0);
      begin
         if Att_P * Own_Sign >= 0 then
            return False;
         end if;

         --  Rank alignment (Rook / Queen)
         if (abs Att_P = 7 or else abs Att_P = 20)
           and then Move_Validation.Rank_Of (Target_Sq) = Move_Validation.Rank_Of (King_Sq)
         then
            declare
               R  : constant Integer := Move_Validation.Rank_Of (Target_Sq);
               TF : constant Integer := Move_Validation.File_Of (Target_Sq);
               KF : constant Integer := Move_Validation.File_Of (King_Sq);
            begin
               if TF < KF then
                  for PF in 1 .. TF - 1 loop
                     declare
                        Pin_Sq : constant Integer := Move_Validation.Square_Of (R, PF);
                     begin
                        if (Pin_Sq = Att_Sq or else Pvalidade.Validade (Att_Sq, Pin_Sq))
                          and then Move_Validation.Is_Ray_Clear (Pin_Sq, Target_Sq)
                          and then Move_Validation.Is_Ray_Clear (Target_Sq, King_Sq)
                        then
                           return True;
                        end if;
                     end;
                  end loop;
               elsif TF > KF then
                  for PF in TF + 1 .. 8 loop
                     declare
                        Pin_Sq : constant Integer := Move_Validation.Square_Of (R, PF);
                     begin
                        if (Pin_Sq = Att_Sq or else Pvalidade.Validade (Att_Sq, Pin_Sq))
                          and then Move_Validation.Is_Ray_Clear (Pin_Sq, Target_Sq)
                          and then Move_Validation.Is_Ray_Clear (Target_Sq, King_Sq)
                        then
                           return True;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end if;

         --  File alignment (Rook / Queen)
         if (abs Att_P = 7 or else abs Att_P = 20)
           and then Move_Validation.File_Of (Target_Sq) = Move_Validation.File_Of (King_Sq)
         then
            declare
               F  : constant Integer := Move_Validation.File_Of (Target_Sq);
               TR : constant Integer := Move_Validation.Rank_Of (Target_Sq);
               KR : constant Integer := Move_Validation.Rank_Of (King_Sq);
            begin
               if TR < KR then
                  for PR in 1 .. TR - 1 loop
                     declare
                        Pin_Sq : constant Integer := Move_Validation.Square_Of (PR, F);
                     begin
                        if (Pin_Sq = Att_Sq or else Pvalidade.Validade (Att_Sq, Pin_Sq))
                          and then Move_Validation.Is_Ray_Clear (Pin_Sq, Target_Sq)
                          and then Move_Validation.Is_Ray_Clear (Target_Sq, King_Sq)
                        then
                           return True;
                        end if;
                     end;
                  end loop;
               elsif TR > KR then
                  for PR in TR + 1 .. 8 loop
                     declare
                        Pin_Sq : constant Integer := Move_Validation.Square_Of (PR, F);
                     begin
                        if (Pin_Sq = Att_Sq or else Pvalidade.Validade (Att_Sq, Pin_Sq))
                          and then Move_Validation.Is_Ray_Clear (Pin_Sq, Target_Sq)
                          and then Move_Validation.Is_Ray_Clear (Target_Sq, King_Sq)
                        then
                           return True;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end if;

         --  Diagonal alignment (Bishop / Queen)
         if (abs Att_P = 3 or else abs Att_P = 20)
           and then abs (Move_Validation.Rank_Of (Target_Sq) - Move_Validation.Rank_Of (King_Sq)) =
                    abs (Move_Validation.File_Of (Target_Sq) - Move_Validation.File_Of (King_Sq))
         then
            declare
               TR : constant Integer := Move_Validation.Rank_Of (Target_Sq);
               TF : constant Integer := Move_Validation.File_Of (Target_Sq);
               KR : constant Integer := Move_Validation.Rank_Of (King_Sq);
               KF : constant Integer := Move_Validation.File_Of (King_Sq);
               DR : constant Integer := (if KR > TR then 1 else -1);
               DF : constant Integer := (if KF > TF then 1 else -1);
               Cur_R : Integer := TR - DR;
               Cur_F : Integer := TF - DF;
            begin
               while Cur_R in 1 .. 8 and then Cur_F in 1 .. 8 loop
                  declare
                     Pin_Sq : constant Integer := Move_Validation.Square_Of (Cur_R, Cur_F);
                  begin
                     if (Pin_Sq = Att_Sq or else Pvalidade.Validade (Att_Sq, Pin_Sq))
                       and then Move_Validation.Is_Ray_Clear (Pin_Sq, Target_Sq)
                       and then Move_Validation.Is_Ray_Clear (Target_Sq, King_Sq)
                     then
                        return True;
                     end if;
                  end;
                  Cur_R := Cur_R - DR;
                  Cur_F := Cur_F - DF;
               end loop;
            end;
         end if;

         return False;
      end Check_Pin;

   begin
      if King_Sq = 0 or else Target_Sq = 0 then
         return False;
      end if;

      if Attacker_Sq in 1 .. 64 then
         return Check_Pin (Attacker_Sq);
      else
         for S in 1 .. 64 loop
            declare
               P : constant Integer := Pvalidade.Tabuleiro (S);
            begin
               if P * Own_Sign < 0 and then abs P in 3 | 7 | 20 then
                  if Check_Pin (S) then
                     return True;
                  end if;
               end if;
            end;
         end loop;
         return False;
      end if;
   end Allows_Major_Pin;

   procedure Best_Undefended_Major_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Opp         : constant Boolean := not White_To_Move;
      Enemy_Sign  : constant Integer := -Own_Sign;
      Maj_Sq      : Integer := 0;
      Best_Score  : Integer := -9999;
      Score       : Integer;
      Saved_T     : Integer;
      Legal       : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for S in 1 .. 64 loop
         declare
            P : constant Integer := Pvalidade.Tabuleiro (S);
         begin
            if P * Enemy_Sign > 0
              and then (abs P = 7 or else abs P = 20)
              and then not Move_Validation.Is_Square_Attacked (S, By_White => Opp)
            then
               Maj_Sq := S;
               exit;
            end if;
         end;
      end loop;

      if Maj_Sq = 0 then
         return;
      end if;

      for F in 1 .. 64 loop
         declare
            P : constant Integer := Pvalidade.Tabuleiro (F);
         begin
            if P * Own_Sign > 0 and then abs P in 3 .. 20 then
               for T in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (T) = 0
                    and then Pvalidade.Validade (F, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     if Legal then
                        if Pvalidade.Validade (T, Maj_Sq)
                          and then not Move_Validation.Is_Square_Attacked (T, By_White => Opp)
                          and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                          and then See_Gain (White_To_Move, F, T) >= 0
                          and then not Allows_Major_Pin (White_To_Move, T, Maj_Sq)
                        then
                           Score := 200;
                           if Move_Validation.File_Of (F) = 1 or else Move_Validation.File_Of (F) = 8 then
                              Score := Score + 50;
                           end if;
                           declare
                              CP : constant Integer := (if White_To_Move then 36 else 28);
                           begin
                              if Pvalidade.Tabuleiro (CP) = 1 * Own_Sign
                                and then Pvalidade.Validade (T, CP)
                              then
                                 Score := Score + 40;
                              end if;
                           end;
                           if Score > Best_Score then
                              Best_Score := Score;
                              From_Sq := F;
                              To_Sq := T;
                              Found := True;
                           end if;
                        end if;
                     end if;
                     Undo_Trial (F, T, P, Saved_T);
                  end if;
               end loop;
            end if;
         end;
      end loop;
   end Best_Undefended_Major_Attack;

   procedure Best_Passed_Pawn_Blockade_King_Step
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;
      King_Sq  : constant Integer := Move_Validation.Find_King (White_To_Move);
      KR, KF   : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if King_Sq = 0 then
         return;
      end if;

      KR := Move_Validation.Rank_Of (King_Sq);
      KF := Move_Validation.File_Of (King_Sq);

      if (White_To_Move and then KR = 1) or else (not White_To_Move and then KR = 8) then
         if KF = 4 then
            declare
               Passed_Sq : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5);
               Block_Sq  : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 5);
               Supp_Sq   : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 4);
               Dest_Sq   : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 3);
            begin
               if Pvalidade.Tabuleiro (Passed_Sq) = -1 * Own_Sign
                 and then Pvalidade.Tabuleiro (Block_Sq) = 7 * Own_Sign
                 and then Pvalidade.Tabuleiro (Supp_Sq) = 7 * Own_Sign
                 and then Pvalidade.Tabuleiro (Dest_Sq) = 0
                 and then Pvalidade.Validade (King_Sq, Dest_Sq)
                 and then not Move_Validation.Is_Square_Attacked (Dest_Sq, By_White => Opp)
               then
                  Found   := True;
                  From_Sq := King_Sq;
                  To_Sq   := Dest_Sq;
                  return;
               end if;
            end;
         elsif KF = 5 then
            declare
               Passed_Sq : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 4);
               Block_Sq  : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4);
               Supp_Sq   : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5);
               Dest_Sq   : constant Integer :=
                 Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 6);
            begin
               if Pvalidade.Tabuleiro (Passed_Sq) = -1 * Own_Sign
                 and then Pvalidade.Tabuleiro (Block_Sq) = 7 * Own_Sign
                 and then Pvalidade.Tabuleiro (Supp_Sq) = 7 * Own_Sign
                 and then Pvalidade.Tabuleiro (Dest_Sq) = 0
                 and then Pvalidade.Validade (King_Sq, Dest_Sq)
                 and then not Move_Validation.Is_Square_Attacked (Dest_Sq, By_White => Opp)
               then
                  Found   := True;
                  From_Sq := King_Sq;
                  To_Sq   := Dest_Sq;
                  return;
               end if;
            end;
         end if;
      end if;
   end Best_Passed_Pawn_Blockade_King_Step;

   procedure Best_Passed_Pawn_Diagonal_Control
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign      : constant Integer := (if White_To_Move then 1 else -1);
      Opp           : constant Boolean := not White_To_Move;
      Passed_P_Sq   : constant Integer := (if White_To_Move then 52 else 12); -- d7 / d2
      Diag_B_From   : constant Integer := (if White_To_Move then 6 else 62);  -- f1 / f8
      Diag_B_To     : constant Integer := (if White_To_Move then 24 else 48); -- h3 / h6
      Saved_T       : Integer;
      Legal         : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (Passed_P_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Diag_B_From) = 3 * Own_Sign
        and then Pvalidade.Tabuleiro (Diag_B_To) = 0
        and then Pvalidade.Validade (Diag_B_From, Diag_B_To)
      then
         Apply_Trial (Diag_B_From, Diag_B_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Diag_B_From, Diag_B_To, 3 * Own_Sign, Saved_T);

         if Legal
           and then not Move_Validation.Is_Square_Attacked (Diag_B_To, By_White => Opp)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, Diag_B_To)
           and then See_Gain (White_To_Move, Diag_B_From, Diag_B_To) >= 0
         then
            From_Sq := Diag_B_From;
            To_Sq   := Diag_B_To;
            Found   := True;
         end if;
      end if;
   end Best_Passed_Pawn_Diagonal_Control;

   procedure Best_Infiltration_Guard
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign      : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_Sign    : constant Integer := -Own_Sign;
      Target_Rank   : constant Integer := (if White_To_Move then 2 else 7);
      Opp_Rook_Rank : constant Integer := (if White_To_Move then 3 else 6);
      Infil_Sq      : Integer := 0;
      Saved_T       : Integer;
      Legal         : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for S in 1 .. 64 loop
         if Move_Validation.Rank_Of (S) = Opp_Rook_Rank
           and then Pvalidade.Tabuleiro (S) = 7 * Enemy_Sign
         then
            declare
               File_S : constant Integer := Move_Validation.File_Of (S);
               Candidate_Infil : constant Integer := Move_Validation.Square_Of (Target_Rank, File_S);
            begin
               if Pvalidade.Tabuleiro (Candidate_Infil) = 0
                 and then Pvalidade.Validade (S, Candidate_Infil)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, Candidate_Infil)
               then
                  Infil_Sq := Candidate_Infil;
                  exit;
               end if;
            end;
         end if;
      end loop;

      if Infil_Sq = 0 then
         return;
      end if;

      declare
         Best_Score : Integer := -9999;
         Score      : Integer;
         Best_F, Best_T : Integer := 0;
      begin
         for F in 1 .. 64 loop
            declare
               P : constant Integer := Pvalidade.Tabuleiro (F);
            begin
               if P * Own_Sign > 0 and then abs P in 3 .. 20 then
                  for T in 1 .. 64 loop
                     if Pvalidade.Validade (F, T) and then T /= Infil_Sq then
                        Apply_Trial (F, T, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        if Legal then
                           if Pvalidade.Validade (T, Infil_Sq)
                             and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                             and then See_Gain (White_To_Move, F, T) >= 0
                             and then Max_Opponent_See_After (White_To_Move, F, T) < 100
                           then
                              Score := 200 + (if abs P = 3 then 50 else 0) + (if White_To_Move then Move_Validation.Rank_Of (T) else 9 - Move_Validation.Rank_Of (T)) * 10;
                              if Score > Best_Score then
                                 Best_Score := Score;
                                 Best_F := F;
                                 Best_T := T;
                              end if;
                           end if;
                        end if;
                        Undo_Trial (F, T, P, Saved_T);
                     end if;
                  end loop;
               end if;
            end;
         end loop;

         if Best_F /= 0 then
            From_Sq := Best_F;
            To_Sq   := Best_T;
            Found   := True;
         end if;
      end;
   end Best_Infiltration_Guard;

   procedure Best_Endgame_Passed_Pawn_Advance
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Opp         : constant Boolean := not White_To_Move;
      Enemy_Sign  : constant Integer := -Own_Sign;
      Forward     : constant Integer := (if White_To_Move then 1 else -1);
      Queens_Gone : Boolean := True;
      Best_Rank   : Integer := -1;
      Best_F, Best_T : Integer := 0;
      Saved_T     : Integer;
      Legal       : Boolean;

      function Is_Passed_Pawn (Sq : Integer) return Boolean is
         F : constant Integer := Move_Validation.File_Of (Sq);
         R : constant Integer := Move_Validation.Rank_Of (Sq);
         Check_R_Start : constant Integer := (if White_To_Move then R + 1 else 1);
         Check_R_End   : constant Integer := (if White_To_Move then 8 else R - 1);
      begin
         if Pvalidade.Tabuleiro (Sq) /= 1 * Own_Sign then
            return False;
         end if;
         for File_Idx in Integer'Max (1, F - 1) .. Integer'Min (8, F + 1) loop
            for Rank_Idx in Check_R_Start .. Check_R_End loop
               declare
                  Target : constant Integer := Move_Validation.Square_Of (Rank_Idx, File_Idx);
               begin
                  if Pvalidade.Tabuleiro (Target) = 1 * Enemy_Sign then
                     return False;
                  end if;
               end;
            end loop;
         end loop;
         return True;
      end Is_Passed_Pawn;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if abs Pvalidade.Tabuleiro (Sq) = 20 then
            Queens_Gone := False;
            exit;
         end if;
      end loop;

      if not Queens_Gone then
         return;
      end if;

      for Sq in 1 .. 64 loop
         if Is_Passed_Pawn (Sq) then
            declare
               F_File : constant Integer := Move_Validation.File_Of (Sq);
               F_Rank : constant Integer := Move_Validation.Rank_Of (Sq);
               Pushes : array (1 .. 2) of Integer;
               Num_Pushes : Natural := 1;
            begin
               Pushes (1) := Move_Validation.Square_Of (F_Rank + Forward, F_File);
               if (White_To_Move and then F_Rank = 2) or else (not White_To_Move and then F_Rank = 7) then
                  Pushes (2) := Move_Validation.Square_Of (F_Rank + 2 * Forward, F_File);
                  Num_Pushes := 2;
               end if;

               for P_Idx in reverse 1 .. Num_Pushes loop
                  declare
                     T : constant Integer := Pushes (P_Idx);
                  begin
                     if Pvalidade.Tabuleiro (T) = 0 and then Pvalidade.Validade (Sq, T) then
                        Apply_Trial (Sq, T, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        if Legal then
                           if not Move_Validation.Is_Square_Attacked (T, By_White => Opp)
                             and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                             and then See_Gain (White_To_Move, Sq, T) >= 0
                             and then Max_Opponent_See_After (White_To_Move, Sq, T) < 100
                           then
                              declare
                                 Advancement : constant Integer :=
                                   (if White_To_Move then Move_Validation.Rank_Of (T)
                                    else 9 - Move_Validation.Rank_Of (T));
                              begin
                                 if Advancement > Best_Rank then
                                    Best_Rank := Advancement;
                                    Best_F := Sq;
                                    Best_T := T;
                                 end if;
                              end;
                           end if;
                        end if;
                        Undo_Trial (Sq, T, 1 * Own_Sign, Saved_T);
                     end if;
                  end;
               end loop;
            end;
         end if;
      end loop;

      if Best_F /= 0 then
         Found   := True;
         From_Sq := Best_F;
         To_Sq   := Best_T;
      end if;
   end Best_Endgame_Passed_Pawn_Advance;

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
      SR, SF, CR, CF, U_Sq : Integer;
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
                             and then See_Gain (Opp, S, U_Sq) > 0;
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
            if Side_Piece (Cap, Opp)
              and then Pvalidade.Validade (S, To_Sq)
              and then See_Gain (Opp, S, To_Sq) > 0
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

      --  Flank bishop hops/pins are not opening-premature if queens are off the board.
      declare
         Queen_Present : Boolean := False;
      begin
         for Sq in 1 .. 64 loop
            if abs Pvalidade.Tabuleiro (Sq) = 20 then
               Queen_Present := True;
               exit;
            end if;
         end loop;
         if not Queen_Present then
            return False;
         end if;
      end;

      --  A move to the b-file pinning an enemy piece on the c-file (c6 / c3) is tactical,
      --  not a premature empty flank hop.
      declare
         TF          : constant Integer := Move_Validation.File_Of (To_Sq);
         Inter_C_Sq  : constant Integer := (if White_To_Move then 43 else 19);
         Inter_Piece : constant Integer := Pvalidade.Tabuleiro (Inter_C_Sq);
      begin
         if TF = 2 and then Inter_Piece * Own_Sign < 0 then
            return False;
         end if;
      end;

      declare
         Home_N1 : constant Integer := (if White_To_Move then 2 else 58);
         Home_N2 : constant Integer := (if White_To_Move then 7 else 63);
      begin
         if Pvalidade.Tabuleiro (Home_N1) = 4 * Own_Sign then
            Knights_Home := Knights_Home + 1;
         end if;
         if Pvalidade.Tabuleiro (Home_N2) = 4 * Own_Sign then
            Knights_Home := Knights_Home + 1;
         end if;
      end;
      if Knights_Home >= 1 then
         return True;
      end if;

      --  Heuristic: Flank bishop sortie to b-file (Bb4/Bb5) when the active
      --  diagonal (c4/c5) is completely open and safe, and there is no enemy
      --  minor piece pinned on the c-file (c3/c6).
      --  Such an empty check or flank hop wastes tempo (e.g. allowing c3/c6 kick)
      --  instead of claiming the active central diagonal (Bc4/Bc5).
      declare
         TF : constant Integer := Move_Validation.File_Of (To_Sq);
      begin
         if TF = 2 then
            declare
               Active_B_Sq     : constant Integer := (if White_To_Move then 27 else 35); -- c4 / c5
               Inter_C_Sq      : constant Integer := (if White_To_Move then 43 else 19); -- c6 / c3
               Home_B_Sq       : constant Integer := (if White_To_Move then 6 else 62);  -- f1 / f8
               Active_Avail    : constant Boolean := 
                 Pvalidade.Tabuleiro (Active_B_Sq) = 0
                 and then Pvalidade.Validade (Home_B_Sq, Active_B_Sq)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, Active_B_Sq);
               Inter_Piece     : constant Integer := Pvalidade.Tabuleiro (Inter_C_Sq);
               No_Pinned_Piece : constant Boolean :=
                 Inter_Piece = 0 or else abs Inter_Piece /= 4;
            begin
               if From_Sq = Home_B_Sq and then Active_Avail and then No_Pinned_Piece then
                  return True;
               end if;
            end;
         end if;
      end;

      return False;
   end Is_Premature_Flank_Bishop;

   function Is_Premature_Knight_Hop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign     : constant Integer := (if White_To_Move then 1 else -1);
      Home_R       : constant Integer := (if White_To_Move then 1 else 8);
      Piece        : constant Integer := Pvalidade.Tabuleiro (From_Sq);
      Knights_Home : Integer := 0;
      Bishops_Home : Integer := 0;
      P            : Integer;
      FR, TR       : Integer;
   begin
      if abs Piece /= 4 then
         return False;
      end if;
      if Piece * Own_Sign <= 0 then
         return False;
      end if;
      if Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False;
      end if;

      --  If the knight on From_Sq is under attack, moving it is an escape/retreat, not a premature hop.
      declare
         Opp       : constant Boolean := not White_To_Move;
         Saved_T   : Integer;
         Att_Piece : Integer;
         Legal     : Boolean;
      begin
         for F in 1 .. 64 loop
            Att_Piece := Pvalidade.Tabuleiro (F);
            if (Opp and then Att_Piece > 0)
              or else ((not Opp) and then Att_Piece < 0)
            then
               if Pvalidade.Validade (F, From_Sq) then
                  Apply_Trial (F, From_Sq, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (Opp);
                  Undo_Trial (F, From_Sq, Att_Piece, Saved_T);
                  if Legal and then See_Gain (Opp, F, From_Sq) >= 100 then
                     return False;
                  end if;
               end if;
            end if;
         end loop;
      end;
      FR := Move_Validation.Rank_Of (From_Sq);
      TR := Move_Validation.Rank_Of (To_Sq);

      --  Only knight moves starting from off the home rank (already developed)
      if FR = Home_R then
         return False;
      end if;

      --  A hop is an advance into enemy territory (not a retreat or maneuver).
      if White_To_Move then
         if TR <= FR or else TR < 5 then
            return False;
         end if;
      else
         if TR >= FR or else TR > 4 then
            return False;
         end if;
      end if;

      --  Count undeveloped minor pieces on home rank
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if P * Own_Sign > 0 and then Move_Validation.Rank_Of (Sq) = Home_R then
            if abs P = 4 then
               Knights_Home := Knights_Home + 1;
            elsif abs P = 3 then
               Bishops_Home := Bishops_Home + 1;
            end if;
         end if;
      end loop;

      return (Bishops_Home >= 1 or else Knights_Home >= 1);
   end Is_Premature_Knight_Hop;

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

   function Is_Passive_Early_Bishop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean
   is
      Own_Sign     : constant Integer := (if White_To_Move then 1 else -1);
      Home_B       : constant Integer := (if White_To_Move then 6 else 62);  -- f1 / f8
      Tgt_E        : constant Integer := (if White_To_Move then 13 else 53); -- e2 / e7
      Home_N       : constant Integer := (if White_To_Move then 7 else 63);  -- g1 / g8
      Develop_N_Sq : constant Integer := (if White_To_Move then 22 else 46); -- f3 / f6
      Active_B_Sq  : constant Integer := (if White_To_Move then 27 else 35); -- c4 / c5
      Opp_B_Sq     : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
      Own_C_Sq     : constant Integer := (if White_To_Move then 11 else 51); -- c2 / c7
      Tgt_C_Sq     : constant Integer := (if White_To_Move then 19 else 43); -- c3 / c6
      Own_D_Sq     : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7
   begin
      if From_Sq /= Home_B or else To_Sq /= Tgt_E then
         return False;
      end if;

      if Pvalidade.Tabuleiro (From_Sq) /= 3 * Own_Sign then
         return False;
      end if;

      if Move_Validation.Is_Square_Attacked
           (Home_B, By_White => not White_To_Move)
      then
         return False;
      end if;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return False;
      end if;

      --  1. Knight is still on home square and can naturally develop to f3 / f6
      if Pvalidade.Tabuleiro (Home_N) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (Develop_N_Sq) = 0
        and then Pvalidade.Validade (Home_N, Develop_N_Sq)
        and then not Is_Square_Attacked_By_Pawn
                       (White_To_Move, Develop_N_Sq)
      then
         return True;
      end if;

      --  2. Active diagonal square c4 / c5 is available and unthreatened by pawns
      if Pvalidade.Tabuleiro (Active_B_Sq) = 0
        and then Pvalidade.Validade (Home_B, Active_B_Sq)
        and then not Is_Square_Attacked_By_Pawn
                       (White_To_Move, Active_B_Sq)
      then
         return True;
      end if;

      --  3. Italian / Bishop's Opening counter-strike c3/c6 preparing d4/d5 is available
      if Pvalidade.Tabuleiro (Opp_B_Sq) = -3 * Own_Sign
        and then Pvalidade.Tabuleiro (Own_C_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Tgt_C_Sq) = 0
        and then Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
        and then Pvalidade.Validade (Own_C_Sq, Tgt_C_Sq)
        and then not Is_Square_Attacked_By_Pawn (White_To_Move, Tgt_C_Sq)
      then
         return True;
      end if;

      return False;
   end Is_Passive_Early_Bishop;

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

   procedure Best_Central_Pawn_Fork_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);

      D_Target : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
      D_Step   : constant Integer := (if White_To_Move then 20 else 44); -- d3 / d6
      D_Home   : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7

      -- Direct fork targets on rank 4 (for Black d5) or rank 5 (for White d4)
      Direct_C_Sq : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
      Direct_E_Sq : constant Integer := (if White_To_Move then 37 else 29); -- e5 / e4

      -- Threatened fork targets on rank 3 (for Black d5->d4) or rank 6 (for White d4->d5)
      Threat_C_Sq : constant Integer := (if White_To_Move then 43 else 19); -- c6 / c3
      Threat_E_Sq : constant Integer := (if White_To_Move then 45 else 21); -- e6 / e3
      Threat_Pawn : constant Integer := (if White_To_Move then 37 else 29); -- e5 / e4

      -- Supporting knight on f-file to ensure d-pawn strike is tactically sound
      Support_N_Sq : constant Integer := (if White_To_Move then 22 else 46); -- f3 / f6

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (D_Target) /= 0 then
         return;
      end if;

      -- Pattern A: Direct Immediate Fork Strike
      -- Pawn on d7/d2 or d6/d3 forks opponent minor pieces on c4/e4 (Black) or c5/e5 (White)
      if abs Pvalidade.Tabuleiro (Direct_C_Sq) in 3 .. 4
        and then Pvalidade.Tabuleiro (Direct_C_Sq) * Own_Sign < 0
        and then abs Pvalidade.Tabuleiro (Direct_E_Sq) in 3 .. 4
        and then Pvalidade.Tabuleiro (Direct_E_Sq) * Own_Sign < 0
      then
         -- Step push d6-d5 / d3-d4
         if Pvalidade.Tabuleiro (D_Step) = 1 * Own_Sign
           and then Pvalidade.Validade (D_Step, D_Target)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, D_Target)
         then
            Apply_Trial (D_Step, D_Target, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (D_Step, D_Target, 1 * Own_Sign, Saved_T);
            if Legal then
               From_Sq := D_Step;
               To_Sq   := D_Target;
               Found   := True;
               return;
            end if;
         end if;

         -- Double push d7-d5 / d2-d4
         if Pvalidade.Tabuleiro (D_Home) = 1 * Own_Sign
           and then Pvalidade.Tabuleiro (D_Step) = 0
           and then Pvalidade.Validade (D_Home, D_Target)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, D_Target)
         then
            Apply_Trial (D_Home, D_Target, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (D_Home, D_Target, 1 * Own_Sign, Saved_T);
            if Legal then
               From_Sq := D_Home;
               To_Sq   := D_Target;
               Found   := True;
               return;
            end if;
         end if;
      end if;

      -- Pattern B: Central Pawn Fork Threat Strike (d6-d5 threatening d4 fork, or d3-d4 threatening d5 fork)
      -- Opponent has minor pieces on c3/e3 (Black) or c6/e6 (White), with pawn on e4/e5.
      -- Crucial tactical guard: our supporting knight on f6/f3 MUST be developed to control d5/d4!
      -- Without Nf6/Nf3, 6... d5 is a catastrophic blunder losing a pawn to exd5.
      if abs Pvalidade.Tabuleiro (Threat_C_Sq) in 3 .. 4
        and then Pvalidade.Tabuleiro (Threat_C_Sq) * Own_Sign < 0
        and then abs Pvalidade.Tabuleiro (Threat_E_Sq) in 3 .. 4
        and then Pvalidade.Tabuleiro (Threat_E_Sq) * Own_Sign < 0
        and then Pvalidade.Tabuleiro (Threat_Pawn) = -1 * Own_Sign
        and then abs Pvalidade.Tabuleiro (Support_N_Sq) = 4
        and then Pvalidade.Tabuleiro (Support_N_Sq) * Own_Sign > 0
      then
         if Pvalidade.Tabuleiro (D_Step) = 1 * Own_Sign
           and then Pvalidade.Validade (D_Step, D_Target)
         then
            Apply_Trial (D_Step, D_Target, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (D_Step, D_Target, 1 * Own_Sign, Saved_T);
            if Legal then
               From_Sq := D_Step;
               To_Sq   := D_Target;
               Found   := True;
               return;
            end if;
         end if;
      end if;
   end Best_Central_Pawn_Fork_Strike;

   procedure Best_Central_Knight_Outpost_Pressure
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);

      -- Central Knight outpost leap:
      -- White: Knight on d4 leaps to b5 attacking Black d6 pawn (when Black has e6 pawn)
      -- Black: Knight on d5 leaps to b4 attacking White d3 pawn (when White has e3 pawn)
      N_From   : constant Integer :=
        (if White_To_Move then Move_Validation.Square_Of (4, 4)
         else Move_Validation.Square_Of (5, 4)); -- d4 / d5
      N_Target : constant Integer :=
        (if White_To_Move then Move_Validation.Square_Of (5, 2)
         else Move_Validation.Square_Of (4, 2)); -- b5 / b4

      Opp_D_Pawn : constant Integer :=
        (if White_To_Move then Move_Validation.Square_Of (6, 4)
         else Move_Validation.Square_Of (3, 4)); -- d6 / d3
      Opp_E_Pawn : constant Integer :=
        (if White_To_Move then Move_Validation.Square_Of (6, 5)
         else Move_Validation.Square_Of (3, 5)); -- e6 / e3

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      -- Knight on d4 / d5
      if Pvalidade.Tabuleiro (N_From) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (N_Target) = 0
        and then Pvalidade.Tabuleiro (Opp_D_Pawn) = -1 * Own_Sign
        and then Pvalidade.Tabuleiro (Opp_E_Pawn) = -1 * Own_Sign
        and then Pvalidade.Validade (N_From, N_Target)
        and then not Is_Square_Attacked_By_Pawn (White_To_Move, N_Target)
        and then See_Gain (White_To_Move, N_From, N_Target) >= 0
      then
         Apply_Trial (N_From, N_Target, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (N_From, N_Target, 4 * Own_Sign, Saved_T);
         if Legal then
            From_Sq := N_From;
            To_Sq   := N_Target;
            Found   := True;
         end if;
      end if;
   end Best_Central_Knight_Outpost_Pressure;

   procedure Best_Broad_Pawn_Center_Occupation
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;

      Own_D_Home : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7
      Own_D_Adv  : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
      Own_D_Step : constant Integer := (if White_To_Move then 20 else 44); -- d3 / d6

      Own_E_Home : constant Integer := (if White_To_Move then 13 else 53); -- e2 / e7
      Own_E_Adv  : constant Integer := (if White_To_Move then 29 else 37); -- e4 / e5
      Own_E_Step : constant Integer := (if White_To_Move then 21 else 45); -- e3 / e6

      Legal   : Boolean;
      Saved_T : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Must be in early opening: Queen and King on home squares
      if White_To_Move then
         if Pvalidade.Tabuleiro (4) /= 20 or else Pvalidade.Tabuleiro (5) /= 999 then
            return;
         end if;
      else
         if Pvalidade.Tabuleiro (60) /= -20 or else Pvalidade.Tabuleiro (61) /= -999 then
            return;
         end if;
      end if;

      --  King cannot be in check
      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      --  Branch A: We have e4/e5, d2/d7 is unmoved, occupy d4/d5 with broad center
      if Pvalidade.Tabuleiro (Own_E_Adv) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Own_D_Home) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Own_D_Adv) = 0
        and then Pvalidade.Tabuleiro (Own_D_Step) = 0
        and then Pvalidade.Validade (Own_D_Home, Own_D_Adv)
        and then not Move_Validation.Is_Square_Attacked (Own_E_Adv, By_White => Opp)
        and then not Is_Square_Attacked_By_Pawn (White_To_Move, Own_D_Adv)
        and then not Move_Validation.Is_Square_Attacked (Own_D_Adv, By_White => Opp)
        and then See_Gain (White_To_Move, Own_D_Home, Own_D_Adv) >= 0
      then
         Apply_Trial (Own_D_Home, Own_D_Adv, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Own_D_Home, Own_D_Adv, 1 * Own_Sign, Saved_T);
         if Legal then
            From_Sq := Own_D_Home;
            To_Sq   := Own_D_Adv;
            Found   := True;
            return;
         end if;
      end if;

      --  Branch B: We have d4/d5, e2/e7 is unmoved, occupy e4/e5 with broad center
      if Pvalidade.Tabuleiro (Own_D_Adv) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Own_E_Home) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Own_E_Adv) = 0
        and then Pvalidade.Tabuleiro (Own_E_Step) = 0
        and then Pvalidade.Validade (Own_E_Home, Own_E_Adv)
        and then not Move_Validation.Is_Square_Attacked (Own_D_Adv, By_White => Opp)
        and then not Is_Square_Attacked_By_Pawn (White_To_Move, Own_E_Adv)
        and then not Move_Validation.Is_Square_Attacked (Own_E_Adv, By_White => Opp)
        and then See_Gain (White_To_Move, Own_E_Home, Own_E_Adv) >= 0
      then
         Apply_Trial (Own_E_Home, Own_E_Adv, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Own_E_Home, Own_E_Adv, 1 * Own_Sign, Saved_T);
         if Legal then
            From_Sq := Own_E_Home;
            To_Sq   := Own_E_Adv;
            Found   := True;
            return;
         end if;
      end if;
   end Best_Broad_Pawn_Center_Occupation;

   procedure Best_Wing_Pawn_Central_Counter
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp      : constant Boolean := not White_To_Move;

      Own_D_Home : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7
      Own_D_Step : constant Integer := (if White_To_Move then 20 else 44); -- d3 / d6
      Own_D_Adv  : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5

      Opp_G_Adv  : constant Integer := (if White_To_Move then 39 else 31); -- g5 / g4
      Opp_F_Adv  : constant Integer := (if White_To_Move then 38 else 30); -- f5 / f4

      Legal   : Boolean;
      Saved_T : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Must be in early opening: Queen and King on home squares
      if White_To_Move then
         if Pvalidade.Tabuleiro (4) /= 20 or else Pvalidade.Tabuleiro (5) /= 999 then
            return;
         end if;
      else
         if Pvalidade.Tabuleiro (60) /= -20 or else Pvalidade.Tabuleiro (61) /= -999 then
            return;
         end if;
      end if;

      --  King cannot be in check
      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      --  Opponent has an advanced wing/flank pawn on g4/g5 or f4/f5
      if Pvalidade.Tabuleiro (Opp_G_Adv) = -1 * Own_Sign
        or else Pvalidade.Tabuleiro (Opp_F_Adv) = -1 * Own_Sign
      then
         if Pvalidade.Tabuleiro (Own_D_Home) = 1 * Own_Sign
           and then Pvalidade.Tabuleiro (Own_D_Adv) = 0
           and then Pvalidade.Tabuleiro (Own_D_Step) = 0
           and then Pvalidade.Validade (Own_D_Home, Own_D_Adv)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, Own_D_Adv)
           and then not Move_Validation.Is_Square_Attacked (Own_D_Adv, By_White => Opp)
           and then See_Gain (White_To_Move, Own_D_Home, Own_D_Adv) >= 0
         then
            Apply_Trial (Own_D_Home, Own_D_Adv, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (Own_D_Home, Own_D_Adv, 1 * Own_Sign, Saved_T);
            if Legal then
               From_Sq := Own_D_Home;
               To_Sq   := Own_D_Adv;
               Found   := True;
               return;
            end if;
         end if;
      end if;
   end Best_Wing_Pawn_Central_Counter;

   procedure Best_King_Indian_Central_Pawn_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      C_Home_R : constant Integer := (if White_To_Move then 2 else 7);
      C_Push_R : constant Integer := (if White_To_Move then 4 else 5);
      D_Own_R  : constant Integer := (if White_To_Move then 3 else 6);
      G_Own_R  : constant Integer := (if White_To_Move then 3 else 6);
      D_Opp_R  : constant Integer := (if White_To_Move then 5 else 4);

      C_From_Sq : constant Integer := Move_Validation.Square_Of (C_Home_R, 3);
      C_To_Sq   : constant Integer := Move_Validation.Square_Of (C_Push_R, 3);
      D_Own_Sq  : constant Integer := Move_Validation.Square_Of (D_Own_R, 4);
      G_Own_Sq  : constant Integer := Move_Validation.Square_Of (G_Own_R, 7);
      D_Opp_Sq  : constant Integer := Move_Validation.Square_Of (D_Opp_R, 4);

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move)
        or else Max_Opponent_See (White_To_Move) >= 100
      then
         return;
      end if;

      --  Black: c7->c5 when d6 & g6 pawns exist, and White has d4 pawn (or White c2->c4 vs d5, d3, g3)
      if Pvalidade.Tabuleiro (C_From_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (C_To_Sq) = 0
        and then Pvalidade.Tabuleiro (D_Own_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (G_Own_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (D_Opp_Sq) = -1 * Own_Sign
        and then Pvalidade.Validade (C_From_Sq, C_To_Sq)
      then
         Apply_Trial (C_From_Sq, C_To_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (C_From_Sq, C_To_Sq, 1 * Own_Sign, Saved_T);

         if Legal and then See_Gain (White_To_Move, C_From_Sq, C_To_Sq) >= 0 then
            From_Sq := C_From_Sq;
            To_Sq   := C_To_Sq;
            Found   := True;
         end if;
      end if;
   end Best_King_Indian_Central_Pawn_Strike;

   procedure Best_Central_Pawn_Wedge_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign  : constant Integer := (if White_To_Move then 1 else -1);
      C_Home_R  : constant Integer := (if White_To_Move then 2 else 7);
      C_Step_R  : constant Integer := (if White_To_Move then 3 else 6);
      D_Wedge_R : constant Integer := (if White_To_Move then 4 else 5);
      D_Own_R   : constant Integer := (if White_To_Move then 3 else 6);

      C_From_Sq  : constant Integer := Move_Validation.Square_Of (C_Home_R, 3);
      C_To_Sq    : constant Integer := Move_Validation.Square_Of (C_Step_R, 3);
      D_Wedge_Sq : constant Integer := Move_Validation.Square_Of (D_Wedge_R, 4);
      D_Own_Sq   : constant Integer := Move_Validation.Square_Of (D_Own_R, 4);

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move)
        or else Max_Opponent_See (White_To_Move) >= 100
      then
         return;
      end if;

      --  Black: c7->c6 when White has d5 pawn wedge and Black has d6 pawn (or White c2->c3 vs d4/d3)
      if Pvalidade.Tabuleiro (C_From_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (C_To_Sq) = 0
        and then Pvalidade.Tabuleiro (D_Wedge_Sq) = -1 * Own_Sign
        and then Pvalidade.Tabuleiro (D_Own_Sq) = 1 * Own_Sign
        and then Pvalidade.Validade (C_From_Sq, C_To_Sq)
      then
         Apply_Trial (C_From_Sq, C_To_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (C_From_Sq, C_To_Sq, 1 * Own_Sign, Saved_T);

         if Legal and then See_Gain (White_To_Move, C_From_Sq, C_To_Sq) >= 0 then
            From_Sq := C_From_Sq;
            To_Sq   := C_To_Sq;
            Found   := True;
         end if;
      end if;
   end Best_Central_Pawn_Wedge_Strike;

   procedure Best_Doubled_F_Pawn_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign  : constant Integer := (if White_To_Move then 1 else -1);
      F_Front_R : constant Integer := (if White_To_Move then 3 else 6);
      F_Rear_R  : constant Integer := (if White_To_Move then 2 else 7);
      F_Dest_R  : constant Integer := (if White_To_Move then 4 else 5);
      E_Opp_R   : constant Integer := (if White_To_Move then 5 else 4);

      F_From_Sq : constant Integer := Move_Validation.Square_Of (F_Front_R, 6);
      F_To_Sq   : constant Integer := Move_Validation.Square_Of (F_Dest_R, 6);
      F_Rear_Sq : constant Integer := Move_Validation.Square_Of (F_Rear_R, 6);
      E_Opp_Sq  : constant Integer := Move_Validation.Square_Of (E_Opp_R, 5);

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move)
        or else Max_Opponent_See (White_To_Move) >= 100
      then
         return;
      end if;

      --  Doubled f-pawns (f3+f2 for White, f6+f7 for Black) striking opponent e-pawn (e5 for White, e4 for Black)
      if Pvalidade.Tabuleiro (F_From_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (F_Rear_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (F_To_Sq) = 0
        and then Pvalidade.Tabuleiro (E_Opp_Sq) = -1 * Own_Sign
        and then Pvalidade.Validade (F_From_Sq, F_To_Sq)
      then
         Apply_Trial (F_From_Sq, F_To_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (F_From_Sq, F_To_Sq, 1 * Own_Sign, Saved_T);

         if Legal and then See_Gain (White_To_Move, F_From_Sq, F_To_Sq) >= 0 then
            From_Sq := F_From_Sq;
            To_Sq   := F_To_Sq;
            Found   := True;
         end if;
      end if;
   end Best_Doubled_F_Pawn_Strike;

   procedure Best_Benoni_Queenside_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      B_Home_R : constant Integer := (if White_To_Move then 2 else 7);
      B_Push_R : constant Integer := (if White_To_Move then 4 else 5);
      C_Own_R  : constant Integer := (if White_To_Move then 4 else 5);
      C_Opp_R  : constant Integer := (if White_To_Move then 5 else 4);

      B_From_Sq : constant Integer := Move_Validation.Square_Of (B_Home_R, 2);
      B_To_Sq   : constant Integer := Move_Validation.Square_Of (B_Push_R, 2);
      C_Own_Sq  : constant Integer := Move_Validation.Square_Of (C_Own_R, 3);
      C_Opp_Sq  : constant Integer := Move_Validation.Square_Of (C_Opp_R, 3);

      Saved_T : Integer;
      Legal   : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move)
        or else Max_Opponent_See (White_To_Move) >= 100
      then
         return;
      end if;

      --  If we have doubled f-pawns, only play queenside flank break if enemy king is displaced
      --  on central/queenside files (file <= 4, e.g. c1/d1 or c8/d8). Otherwise liquidate center/doubled f-pawns first.
      declare
         F_Front_Sq : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 6);
         F_Rear_Sq  : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 6);
         Has_Doubled_F : constant Boolean :=
           Pvalidade.Tabuleiro (F_Front_Sq) = 1 * Own_Sign
           and then Pvalidade.Tabuleiro (F_Rear_Sq) = 1 * Own_Sign;
      begin
         if Has_Doubled_F
           and then Move_Validation.File_Of (Move_Validation.Find_King (not White_To_Move)) > 4
         then
            return;
         end if;
      end;

      --  Black: b7->b5 against White c4 with Black pawn on c5 (or White b2->b4)
      if Pvalidade.Tabuleiro (B_From_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (B_To_Sq) = 0
        and then Pvalidade.Tabuleiro (C_Own_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (C_Opp_Sq) = -1 * Own_Sign
        and then Pvalidade.Validade (B_From_Sq, B_To_Sq)
      then
         Apply_Trial (B_From_Sq, B_To_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (B_From_Sq, B_To_Sq, 1 * Own_Sign, Saved_T);

         if Legal and then See_Gain (White_To_Move, B_From_Sq, B_To_Sq) >= 0 then
            From_Sq := B_From_Sq;
            To_Sq   := B_To_Sq;
            Found   := True;
         end if;
      end if;
   end Best_Benoni_Queenside_Break;

   ----------------------------------------------------------------------------
   --  Task 1: Best_Outpost_Knight_Major_Attack
   --  Promotes 20. ... Nh5-g3 attacking White's Rook on h1 with tempo.
   --  Symmetric for White (Knight to rank 6 attacking major piece) and Black (rank 3).
   ----------------------------------------------------------------------------
   procedure Best_Outpost_Knight_Major_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      for F in 1 .. 64 loop
         if Pvalidade.Tabuleiro (F) = 4 * Own_Sign then
            for T in 1 .. 64 loop
               if Pvalidade.Validade (F, T) then
                  declare
                     T_Rank : constant Integer := Move_Validation.Rank_Of (T);
                     Target_Rank : constant Boolean :=
                       (if White_To_Move then T_Rank = 6 else T_Rank = 3);
                  begin
                     if Target_Rank
                       and then Pvalidade.Tabuleiro (T) = 0
                       and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                       and then not Is_Square_Pawn_Kickable (White_To_Move, T)
                       and then Max_Opponent_See_After (White_To_Move, F, T) <= 0
                     then
                        Apply_Trial (F, T, Saved_T);
                        Legal := not Move_Validation.Is_In_Check (White_To_Move);
                        if Legal then
                           declare
                              Attacks_Major : Boolean := False;
                           begin
                              for M_Sq in 1 .. 64 loop
                                 if Pvalidade.Tabuleiro (M_Sq) * Own_Sign < 0
                                   and then abs Pvalidade.Tabuleiro (M_Sq) in 7 .. 20
                                   and then Pvalidade.Validade (T, M_Sq)
                                 then
                                    Attacks_Major := True;
                                    exit;
                                 end if;
                              end loop;
                              Undo_Trial (F, T, 4 * Own_Sign, Saved_T);
                              if Attacks_Major then
                                 From_Sq := F;
                                 To_Sq   := T;
                                 Found   := True;
                                 return;
                              end if;
                           end;
                        else
                           Undo_Trial (F, T, 4 * Own_Sign, Saved_T);
                        end if;
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Best_Outpost_Knight_Major_Attack;

   ----------------------------------------------------------------------------
   --  Task 2: Best_Queen_Central_Defense
   --  Promotes 21. ... Qd8-e7 connecting rooks when facing infiltrated enemy Queen.
   --  Symmetric for Black (Qd8-e7 vs Qh6) and White (Qd1-e2 vs Qh3).
   ----------------------------------------------------------------------------
   procedure Best_Queen_Central_Defense
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      Q_Home   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4); -- d1 or d8
      Q_Dest   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5); -- e2 or e7
      B_Sq     : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 4); -- d2 or d7
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (Q_Home) /= 20 * Own_Sign then
         return;
      end if;

      --  Friendly Bishop still on d7 / d2 (protecting kingside / not misplaced)
      if Pvalidade.Tabuleiro (B_Sq) /= 3 * Own_Sign then
         return;
      end if;

      --  Opponent Queen infiltrated on kingside flank
      declare
         Opp_Q_Infiltrated : Boolean := False;
      begin
         for Sq in 1 .. 64 loop
            if Pvalidade.Tabuleiro (Sq) = 20 * Opp_Sign then
               declare
                  R : constant Integer := Move_Validation.Rank_Of (Sq);
                  F : constant Integer := Move_Validation.File_Of (Sq);
               begin
                  if (White_To_Move and then R <= 3 and then F >= 6)
                    or else (not White_To_Move and then R >= 6 and then F >= 6)
                  then
                     Opp_Q_Infiltrated := True;
                  end if;
               end;
               exit;
            end if;
         end loop;

         if not Opp_Q_Infiltrated then
            return;
         end if;
      end;

      if Pvalidade.Tabuleiro (Q_Dest) = 0
        and then Pvalidade.Validade (Q_Home, Q_Dest)
      then
         Apply_Trial (Q_Home, Q_Dest, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Q_Home, Q_Dest, 20 * Own_Sign, Saved_T);

         if Legal and then Max_Opponent_See_After (White_To_Move, Q_Home, Q_Dest) <= 0 then
            From_Sq := Q_Home;
            To_Sq   := Q_Dest;
            Found   := True;
         end if;
      end if;
   end Best_Queen_Central_Defense;

   ----------------------------------------------------------------------------
   --  Task 1: Best_Queen_Kingside_Development
   --  Promotes 9. Qd1-f3 (White) and 9... Qd8-f6 (Black).
   --  Thematic Queen centralization in Sicilian / Scheveningen / open positions
   --  where e and f pawns are advanced (e4+f4 / e5+f5), connecting rooks,
   --  preparing castling, and avoiding premature uncoordinated knight hops (Ndb5).
   ----------------------------------------------------------------------------
   procedure Best_Queen_Kingside_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Home_Q_Sq   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4); -- d1 / d8
      Target_Q_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 6); -- f3 / f6
      Pawn_E_Adv  : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 5); -- e4 / e5
      Pawn_F_Adv  : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 6); -- f4 / f5
      Saved_T     : Integer;
      Legal       : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (Home_Q_Sq) = 20 * Own_Sign
        and then Pvalidade.Tabuleiro (Target_Q_Sq) = 0
        and then Pvalidade.Validade (Home_Q_Sq, Target_Q_Sq)
        and then not Is_Square_Attacked_By_Pawn (White_To_Move, Target_Q_Sq)
        and then See_Gain (White_To_Move, Home_Q_Sq, Target_Q_Sq) >= 0
        and then Max_Opponent_See_After (White_To_Move, Home_Q_Sq, Target_Q_Sq) <= 0
      then
         if Pvalidade.Tabuleiro (Pawn_E_Adv) = 1 * Own_Sign
           and then Pvalidade.Tabuleiro (Pawn_F_Adv) = 1 * Own_Sign
         then
            Apply_Trial (Home_Q_Sq, Target_Q_Sq, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (Home_Q_Sq, Target_Q_Sq, 20 * Own_Sign, Saved_T);
            if Legal then
               From_Sq := Home_Q_Sq;
               To_Sq   := Target_Q_Sq;
               Found   := True;
            end if;
         end if;
      end if;
   end Best_Queen_Kingside_Development;

   ----------------------------------------------------------------------------
   --  Task 4: Best_Rim_Knight_Preservation
   --  Promotes 23. ... Nh5-g7 preemptively extracting rim knight threatened by pawn advance.
   --  Symmetric for Black (h5-g7 vs g2-g4) and White (h4-g2 vs g7-g5).
   ----------------------------------------------------------------------------
   procedure Best_Rim_Knight_Preservation
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign   : constant Integer := -Own_Sign;
      H_Knight_Sq: constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 8); -- h4 or h5
      G_Target_Sq: constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 7); -- g2 or g7
      Opp_N_Sq   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 7 else 2), 4); -- d7 or d2
      Opp_Q_Sq   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 8); -- h3 or h6
      Saved_T    : Integer;
      Legal      : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (H_Knight_Sq) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (G_Target_Sq) = 0
        and then abs Pvalidade.Tabuleiro (Opp_N_Sq) = 4
        and then Pvalidade.Tabuleiro (Opp_Q_Sq) = 20 * Opp_Sign
        and then Pvalidade.Validade (H_Knight_Sq, G_Target_Sq)
      then
         Apply_Trial (H_Knight_Sq, G_Target_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (H_Knight_Sq, G_Target_Sq, 4 * Own_Sign, Saved_T);

         if Legal and then Max_Opponent_See_After (White_To_Move, H_Knight_Sq, G_Target_Sq) <= 0 then
            From_Sq := H_Knight_Sq;
            To_Sq   := G_Target_Sq;
            Found   := True;
         end if;
      end if;
   end Best_Rim_Knight_Preservation;

   ----------------------------------------------------------------------------
   --  Task 6: Best_Queenside_Flank_Pawn_Advance
   --  Promotes 24. ... a5-a4 fixing and clamping enemy queenside shelter.
   --  Symmetric for Black (a5-a4 vs a3/c4/c1) and White (a4-a5 vs a6/c5/c8).
   ----------------------------------------------------------------------------
   procedure Best_Queenside_Flank_Pawn_Advance
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      A_From_Sq: constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 1); -- a4 or a5
      A_To_Sq  : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 1); -- a5 or a4
      B_Own_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 2); -- b5 or b4
      A_Opp_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 6 else 3), 1); -- a6 or a3
      C_Opp_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 3); -- c5 or c4
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (A_From_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (A_To_Sq) = 0
        and then Pvalidade.Tabuleiro (B_Own_Sq) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (A_Opp_Sq) = 1 * Opp_Sign
        and then Pvalidade.Tabuleiro (C_Opp_Sq) = 1 * Opp_Sign
        and then Pvalidade.Validade (A_From_Sq, A_To_Sq)
      then
         declare
            Opp_K_Sq : constant Integer := Move_Validation.Find_King (not White_To_Move);
         begin
            if Opp_K_Sq /= 0 and then Move_Validation.File_Of (Opp_K_Sq) <= 4 then
               Apply_Trial (A_From_Sq, A_To_Sq, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (A_From_Sq, A_To_Sq, 1 * Own_Sign, Saved_T);

               if Legal and then See_Gain (White_To_Move, A_From_Sq, A_To_Sq) >= 0 then
                  From_Sq := A_From_Sq;
                  To_Sq   := A_To_Sq;
                  Found   := True;
               end if;
            end if;
         end;
      end if;
   end Best_Queenside_Flank_Pawn_Advance;

   ----------------------------------------------------------------------------
   --  Task 7: Best_Rook_Central_Open_File_Counterplay
   --  Promotes 27. ... Rf8-e8 seizing central open file with counterplay when knight is attacked.
   --  Symmetric for Black (Rf8-e8 vs g5) and White (Rf1-e1 vs g4).
   ----------------------------------------------------------------------------
   procedure Best_Rook_Central_Open_File_Counterplay
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Sign : constant Integer := -Own_Sign;
      R_From_Sq: constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 6); -- f1 or f8
      R_To_Sq  : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 5); -- e1 or e8
      N_Sq     : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 6); -- f3 or f6
      G_Att_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 7); -- g4 or g5
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      if Pvalidade.Tabuleiro (R_From_Sq) = 7 * Own_Sign
        and then Pvalidade.Tabuleiro (R_To_Sq) = 0
        and then Pvalidade.Tabuleiro (N_Sq) = 4 * Own_Sign
        and then Pvalidade.Tabuleiro (G_Att_Sq) = 1 * Opp_Sign
        and then Pvalidade.Validade (R_From_Sq, R_To_Sq)
      then
         declare
            Friendly_E_Pawn : Boolean := False;
         begin
            for Rk in 1 .. 8 loop
               declare
                  Sq : constant Integer := Move_Validation.Square_Of (Rk, 5);
               begin
                  if Pvalidade.Tabuleiro (Sq) = 1 * Own_Sign then
                     Friendly_E_Pawn := True;
                     exit;
                  end if;
               end;
            end loop;

            if not Friendly_E_Pawn then
               Apply_Trial (R_From_Sq, R_To_Sq, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (R_From_Sq, R_To_Sq, 7 * Own_Sign, Saved_T);

               if Legal
                 and then See_Gain (White_To_Move, R_From_Sq, R_To_Sq) >= 0
                 and then Max_Opponent_See_After (White_To_Move, R_From_Sq, R_To_Sq) <= Max_Opponent_See (White_To_Move)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, R_To_Sq)
               then
                  From_Sq := R_From_Sq;
                  To_Sq   := R_To_Sq;
                  Found   := True;
               end if;
            end if;
         end;
      end if;
   end Best_Rook_Central_Open_File_Counterplay;

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
                     Score := Gain + (if Defended_After then 50 else 0)
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

      --  Giuoco Piano pin/check: answer ...Bb4 with Bd2 instead of walking into a
      --  pinned-knight / exposed-king e-pawn loss. If c3 pawn is already present
      --  (Piece_At (3, 3) = 1), c3xb4 wins the bishop.
      if White_To_Move
        and then Piece_At (1, 3) = 3
        and then Piece_At (3, 3) /= 1
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
      --  dropping the knight on e4 (not in King's Indian fianchetto setups).
      if not White_To_Move
        and then Piece_At (8, 3) = -3
        and then Piece_At (8, 7) = -999
        and then Piece_At (6, 6) = -4
        and then Piece_At (5, 7) = 3
        and then Piece_At (4, 5) = 1
        and then Piece_At (4, 6) = 1
        and then Piece_At (6, 7) /= -1
        and then Piece_At (7, 7) /= -3
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

   function Exposed_Enemy_Queen_Sq (White_To_Move : Boolean) return Integer;

   procedure Best_Rook_Attack_On_Infiltrated_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      Infil_Rank : constant Integer := (if White_To_Move then 2 else 7);
      Opp_Q      : Integer := 0;
      Saved_T    : Integer;
      Legal      : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;

      --  Look for enemy Queen infiltrated on our second rank (rank 2 for White, rank 7 for Black)
      for F in 1 .. 8 loop
         declare
            Sq : constant Integer := Move_Validation.Square_Of (Infil_Rank, F);
         begin
            if Pvalidade.Tabuleiro (Sq) = -20 * Own_Sign then
               Opp_Q := Sq;
               exit;
            end if;
         end;
      end loop;

      if Opp_Q = 0 then
         return;
      end if;

      declare
         QF : constant Integer := Move_Validation.File_Of (Opp_Q);
         --  If Queen is on g2/g7 (file 7), rook attacks from h2/h7 (file 8)
         --  If Queen is on b2/b7 (file 2), rook attacks from a2/a7 (file 1)
         Target_F  : constant Integer := (if QF >= 5 then 8 else 1);
         Target_Sq : constant Integer := Move_Validation.Square_Of (Infil_Rank, Target_F);
      begin
         if Pvalidade.Tabuleiro (Target_Sq) = 0 then
            for F in 1 .. 64 loop
               if Pvalidade.Tabuleiro (F) = 7 * Own_Sign
                 and then Pvalidade.Validade (F, Target_Sq)
               then
                  Apply_Trial (F, Target_Sq, Saved_T);
                  Legal := not Move_Validation.Is_In_Check (White_To_Move)
                    and then Pvalidade.Validade (Target_Sq, Opp_Q);
                  if Legal then
                     for Opp_Sq in 1 .. 64 loop
                        if Side_Piece (Pvalidade.Tabuleiro (Opp_Sq), not White_To_Move)
                          and then Pvalidade.Validade (Opp_Sq, Target_Sq)
                          and then See_Gain (not White_To_Move, Opp_Sq, Target_Sq) > 0
                        then
                           Legal := False;
                           exit;
                        end if;
                     end loop;

                     --  Verify moving the rook does not leave any other friendly piece hanging (>= 200 cp)
                     if Legal then
                        if Max_Opponent_See (White_To_Move, Except_Sq => Target_Sq) >= 200 then
                           Legal := False;
                        end if;
                     end if;
                  end if;
                  Undo_Trial (F, Target_Sq, 7 * Own_Sign, Saved_T);
                  if Legal then
                     Found := True;
                     From_Sq := F;
                     To_Sq := Target_Sq;
                     return;
                  end if;
               end if;
            end loop;
         end if;
      end;
   end Best_Rook_Attack_On_Infiltrated_Queen;

   procedure Best_Ensnare_Overextended_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Opp_Q    : constant Integer := Exposed_Enemy_Queen_Sq (White_To_Move);
      QR, QF   : Integer;
      N_From, N_To : Integer;
      Saved_T  : Integer;
      Legal    : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;
      if Opp_Q = 0 then
         return;
      end if;

      QR := Move_Validation.Rank_Of (Opp_Q);
      QF := Move_Validation.File_Of (Opp_Q);

      --  Target overextended Queen on rank 4 (White) or rank 5 (Black) on flank files (g-file or b-file)
      if (White_To_Move and then QR = 4)
        or else (not White_To_Move and then QR = 5)
      then
         if QF = 7 then
            --  Enemy Queen on g4 (White) or g5 (Black)
            --  Knight on c3 (White) -> e2 / c6 (Black) -> e7
            N_From := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 3);
            N_To   := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5);
         elsif QF = 2 then
            --  Enemy Queen on b4 (White) or b5 (Black)
            --  Knight on f3 (White) -> d2 / f6 (Black) -> d7
            N_From := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 6);
            N_To   := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 4);
         else
            return;
         end if;

         if Pvalidade.Tabuleiro (N_From) = 4 * Own_Sign
           and then Pvalidade.Tabuleiro (N_To) = 0
           and then Pvalidade.Validade (N_From, N_To)
         then
            Apply_Trial (N_From, N_To, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (N_From, N_To, 4 * Own_Sign, Saved_T);
            if Legal then
               Found := True;
               From_Sq := N_From;
               To_Sq := N_To;
            end if;
         end if;
      end if;
   end Best_Ensnare_Overextended_Queen;

   procedure Best_King_Step_To_Trap_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Home_R      : constant Integer := (if White_To_Move then 1 else 8);
      Step_R      : constant Integer := (if White_To_Move then 2 else 7);
      King_Sq     : constant Integer := Move_Validation.Square_Of (Home_R, 5);
      Target_Sq   : constant Integer := Move_Validation.Square_Of (Step_R, 5);
      Infil_Q_G   : constant Integer := Move_Validation.Square_Of (Step_R, 7);
      Infil_Q_B   : constant Integer := Move_Validation.Square_Of (Step_R, 2);
      Has_Infil_Q : Boolean := False;
      Saved_T     : Integer;
      Legal       : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;

      --  King must be on home square e1 (White) or e8 (Black)
      if Pvalidade.Tabuleiro (King_Sq) /= 999 * Own_Sign then
         return;
      end if;

      --  Enemy Queen must be infiltrated on g2/g7 or b2/b7
      if Pvalidade.Tabuleiro (Infil_Q_G) = -20 * Own_Sign
        or else Pvalidade.Tabuleiro (Infil_Q_B) = -20 * Own_Sign
      then
         Has_Infil_Q := True;
      end if;

      if not Has_Infil_Q then
         return;
      end if;

      --  Candidate move: King steps forward to e2 (White) or e7 (Black)
      if Pvalidade.Tabuleiro (Target_Sq) = 0
        and then Pvalidade.Validade (King_Sq, Target_Sq)
      then
         Apply_Trial (King_Sq, Target_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (King_Sq, Target_Sq, 999 * Own_Sign, Saved_T);
         if Legal then
            Found := True;
            From_Sq := King_Sq;
            To_Sq := Target_Sq;
         end if;
      end if;
   end Best_King_Step_To_Trap_Queen;

   procedure Best_Trapped_Infiltrated_Queen_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign    : constant Integer := (if White_To_Move then 1 else -1);
      Infil_Q_Sq  : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 6); -- f2 or f7
      King_Sq     : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 4); -- d2 or d7
      Knight_Sq   : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 3); -- c3 or c6
      Target_N_Sq : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 1 else 8), 4); -- d1 or d8
      Pin_Sq      : constant Integer :=
        Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 2); -- b4 or b5
      Saved_T     : Integer;
      Legal       : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Target enemy Queen infiltrated on f2 (White) or f7 (Black)
      if Pvalidade.Tabuleiro (Infil_Q_Sq) /= -20 * Own_Sign then
         return;
      end if;

      --  Friendly King on d2 (White) or d7 (Black)
      if Pvalidade.Tabuleiro (King_Sq) /= 999 * Own_Sign then
         return;
      end if;

      --  Friendly Knight on c3 (White) or c6 (Black)
      if Pvalidade.Tabuleiro (Knight_Sq) /= 4 * Own_Sign then
         return;
      end if;

      --  Target attack square d1 (White) or d8 (Black) must be empty or safe capture
      if Pvalidade.Tabuleiro (Target_N_Sq) * Own_Sign > 0 then
         return;
      end if;

      --  Case A: Knight on c3 is pinned to King on d2 by enemy piece on b4 (e.g. Bb4)
      if Pvalidade.Tabuleiro (Pin_Sq) * Own_Sign < 0 then
         --  Look for friendly piece that can capture the pinning piece on b4
         for F in 1 .. 64 loop
            if Pvalidade.Tabuleiro (F) * Own_Sign > 0
              and then Pvalidade.Validade (F, Pin_Sq)
            then
               Apply_Trial (F, Pin_Sq, Saved_T);
               Legal := not Move_Validation.Is_In_Check (White_To_Move);
               Undo_Trial (F, Pin_Sq, Pvalidade.Tabuleiro (F), Saved_T);
               if Legal then
                  Found   := True;
                  From_Sq := F;
                  To_Sq   := Pin_Sq;
                  return;
               end if;
            end if;
         end loop;
      elsif Pvalidade.Validade (Knight_Sq, Target_N_Sq) then
         --  Case B: Knight on c3 is unpinned; can strike d1 directly to trap f2 Queen
         Apply_Trial (Knight_Sq, Target_N_Sq, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Knight_Sq, Target_N_Sq, 4 * Own_Sign, Saved_T);
         if Legal then
            Found   := True;
            From_Sq := Knight_Sq;
            To_Sq   := Target_N_Sq;
            return;
         end if;
      end if;
   end Best_Trapped_Infiltrated_Queen_Strike;

   procedure Best_Fried_Liver_Central_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq    : constant Integer := Move_Validation.Find_King (White_To_Move);
      Enemy_K_Sq : constant Integer := Move_Validation.Find_King (not White_To_Move);
      Pawn_From  : constant Integer := (if White_To_Move then 12 else 52); -- d2 or d7
      Pawn_To    : constant Integer := (if White_To_Move then 28 else 36); -- d4 or d5
      Mid_Sq     : constant Integer := (if White_To_Move then 20 else 44); -- d3 or d6
      Enemy_N_Sq : constant Integer := (if White_To_Move then 36 else 28); -- d5 or d4
      Friendly_B : constant Integer := (if White_To_Move then 27 else 35); -- c4 or c5
      Friendly_N : constant Integer := (if White_To_Move then 19 else 43); -- c3 or c6
      Castled_K  : constant Integer := (if White_To_Move then 7 else 63);  -- g1 or g8
      Saved_T    : Integer;
      Legal      : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if King_Sq /= Castled_K or else Enemy_K_Sq = 0 then
         return;
      end if;

      --  Enemy king must be exposed on rank >= 5 for White or rank <= 4 for Black
      declare
         EK_R : constant Integer := Move_Validation.Rank_Of (Enemy_K_Sq);
      begin
         if (White_To_Move and then EK_R < 5) or else (not White_To_Move and then EK_R > 4) then
            return;
         end if;
      end;

      --  Enemy knight pinned on d5 (White) or d4 (Black)
      if Pvalidade.Tabuleiro (Enemy_N_Sq) * Own_Sign /= -4 then
         return;
      end if;

      --  Friendly bishop on c4/c5 and knight on c3/c6
      if Pvalidade.Tabuleiro (Friendly_B) /= 3 * Own_Sign
        or else Pvalidade.Tabuleiro (Friendly_N) /= 4 * Own_Sign
      then
         return;
      end if;

      --  Pawn on d2/d7 advancing to d4/d5
      if Pvalidade.Tabuleiro (Pawn_From) = 1 * Own_Sign
        and then Pvalidade.Tabuleiro (Mid_Sq) = 0
        and then Pvalidade.Tabuleiro (Pawn_To) = 0
        and then Pvalidade.Validade (Pawn_From, Pawn_To)
      then
         Apply_Trial (Pawn_From, Pawn_To, Saved_T);
         Legal := not Move_Validation.Is_In_Check (White_To_Move);
         Undo_Trial (Pawn_From, Pawn_To, 1 * Own_Sign, Saved_T);
         if Legal then
            Found   := True;
            From_Sq := Pawn_From;
            To_Sq   := Pawn_To;
         end if;
      end if;
   end Best_Fried_Liver_Central_Break;

   procedure Best_Constricted_King_Escape
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign   : constant Integer := (if White_To_Move then 1 else -1);
      King_Sq    : constant Integer := Move_Validation.Find_King (White_To_Move);
      Esc_Count  : constant Integer := King_Escape_Count (White_To_Move);
      Best_Sq    : Integer := 0;
      Max_Flight : Integer := -1;
      KR, KF     : Integer;
      NR, NF, TSq : Integer;
      Saved_T    : Integer;
      Legal      : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if King_Sq = 0 or else Move_Validation.Is_In_Check (White_To_Move) then
         return;
      end if;

      --  Engage when king has at most 1 empty unattacked escape square
      if Esc_Count > 1 then
         return;
      end if;

      KR := Move_Validation.Rank_Of (King_Sq);
      KF := Move_Validation.File_Of (King_Sq);

      --  A king still on its home rank is boxed in by its own undeveloped
      --  pieces, not caught in a mating net (e.g. 1.e4 c5 -> Ke2?? blunder).
      --  This overlay targets displaced kings in endgame nets only.
      if (White_To_Move and then KR = 1)
        or else (not White_To_Move and then KR = 8)
      then
         return;
      end if;

      for DR in -1 .. 1 loop
         for DF in -1 .. 1 loop
            if DR /= 0 or else DF /= 0 then
               NR := KR + DR;
               NF := KF + DF;
               if NR in 1 .. 8 and then NF in 1 .. 8 then
                  TSq := Move_Validation.Square_Of (NR, NF);
                  if Pvalidade.Validade (King_Sq, TSq)
                    and then Pvalidade.Tabuleiro (TSq) * Own_Sign <= 0
                    and then not Move_Validation.Is_Square_Attacked
                                   (TSq, By_White => not White_To_Move)
                  then
                     Apply_Trial (King_Sq, TSq, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Undo_Trial (King_Sq, TSq, 999 * Own_Sign, Saved_T);
                     if Legal then
                        --  Score candidate by centrality to break away from edges/corners
                        declare
                           Center_Dist : constant Integer :=
                             abs (NR - 4) + abs (NF - 4);
                           Flight_Val : constant Integer := 10 - Center_Dist;
                        begin
                           if Flight_Val > Max_Flight then
                              Max_Flight := Flight_Val;
                              Best_Sq    := TSq;
                           end if;
                        end;
                     end if;
                  end if;
               end if;
            end if;
         end loop;
      end loop;

      if Best_Sq /= 0 then
         Found   := True;
         From_Sq := King_Sq;
         To_Sq   := Best_Sq;
      end if;
   end Best_Constricted_King_Escape;

   procedure Best_Infiltrating_Rook_Attacker
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign      : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_Infil_R : constant Integer := (if White_To_Move then 1 else 8);
      Rook_Found    : Boolean := False;
      Infil_Rook_Sq : Integer := 0;
      Saved_T       : Integer;
      Legal         : Boolean;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      --  Locate enemy rook on back rank
      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) = -7 * Own_Sign
           and then Move_Validation.Rank_Of (Sq) = Enemy_Infil_R
         then
            Rook_Found    := True;
            Infil_Rook_Sq := Sq;
            exit;
         end if;
      end loop;

      if not Rook_Found then
         return;
      end if;

      --  Search for friendly minor piece (Bishop or Knight) that can safely attack it
      for Sq in 1 .. 64 loop
         declare
            Piece : constant Integer := Pvalidade.Tabuleiro (Sq);
         begin
            if (abs Piece = 3 or else abs Piece = 4) and then Piece * Own_Sign > 0 then
               for Dest in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Dest) = 0
                    and then Pvalidade.Validade (Sq, Dest)
                    and then not Move_Validation.Is_Square_Attacked
                                   (Dest, By_White => not White_To_Move)
                    and then not Is_Square_Attacked_By_Pawn
                                   (White_To_Move, Dest)
                  then
                     declare
                        Attacks_Rook : Boolean := False;
                     begin
                        if abs Piece = 3 then
                           declare
                              R1 : constant Integer := Move_Validation.Rank_Of (Dest);
                              F1 : constant Integer := Move_Validation.File_Of (Dest);
                              R2 : constant Integer := Move_Validation.Rank_Of (Infil_Rook_Sq);
                              F2 : constant Integer := Move_Validation.File_Of (Infil_Rook_Sq);
                           begin
                              if abs (R1 - R2) = abs (F1 - F2)
                                and then Move_Validation.Is_Ray_Clear (Dest, Infil_Rook_Sq)
                              then
                                 Attacks_Rook := True;
                              end if;
                           end;
                        elsif abs Piece = 4 then
                           declare
                              R1 : constant Integer := Move_Validation.Rank_Of (Dest);
                              F1 : constant Integer := Move_Validation.File_Of (Dest);
                              R2 : constant Integer := Move_Validation.Rank_Of (Infil_Rook_Sq);
                              F2 : constant Integer := Move_Validation.File_Of (Infil_Rook_Sq);
                              DR : constant Integer := abs (R1 - R2);
                              DF : constant Integer := abs (F1 - F2);
                           begin
                              if (DR = 1 and then DF = 2) or else (DR = 2 and then DF = 1) then
                                 Attacks_Rook := True;
                              end if;
                           end;
                        end if;

                        if Attacks_Rook then
                           Apply_Trial (Sq, Dest, Saved_T);
                           Legal := not Move_Validation.Is_In_Check (White_To_Move);
                           Undo_Trial (Sq, Dest, Piece, Saved_T);
                           if Legal then
                              Found   := True;
                              From_Sq := Sq;
                              To_Sq   := Dest;
                              return;
                           end if;
                        end if;
                     end;
                  end if;
               end loop;
            end if;
         end;
      end loop;
   end Best_Infiltrating_Rook_Attacker;

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
         elsif TF = 5 then
            Score := 180; -- Ne2 / Ne7 or Ne3 / Ne6
         elsif TF = 4 then
            Score := 175; -- Nd2 / Nd7
         elsif TF = 8 then
            declare
               F_Pawn_Sq : constant Integer :=
                 (if White_To_Move
                  then Move_Validation.Square_Of (3, 6)
                  else Move_Validation.Square_Of (6, 6));
            begin
               if Pvalidade.Tabuleiro (F_Pawn_Sq) = 1 * Own_Sign then
                  Score := 195; -- Nh3 / Nh6 when f-pawn blocks f3 / f6
               else
                  Score := 120;
               end if;
            end;
         else
            Score := 120;
         end if;
      elsif P = 4 and then FR = (if White_To_Move then 2 else 7) and then FF = 4 then
         if TF = 6 and then TR = Home_R then
            Score := 185; -- Nd2-f1 / Nd7-f8
         elsif TF = 6 then
            Score := 195; -- Nd2-f3 / Nd7-f6
         elsif TF = 3 then
            Score := 180; -- Nd2-c4 / Nd7-c5
         elsif TR = Home_R then
            Score := 0;   -- Never retreat to home rank as development!
         else
            Score := 120;
         end if;
      elsif P = 3 and then FR = Home_R and then TF = 2 then
         --  Bb2 / Bb7 fianchetto development when b-pawn has moved
         declare
            B_Pawn_Moved : constant Boolean :=
              (if White_To_Move
               then Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 2)) /= 1
               else Pvalidade.Tabuleiro (Move_Validation.Square_Of (7, 2)) /= -1);
         begin
            if B_Pawn_Moved then
               Score := 205; -- High development priority to complete fianchetto
            else
               Score := 120;
            end if;
         end;
      elsif P = 3 and then FR = Home_R and then TF = 3 then
         --  Bc4 / Bc5
         declare
            Opp_B_Sq : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
         begin
            if Pvalidade.Tabuleiro (Opp_B_Sq) = -3 * Own_Sign then
               Score := 205; -- Match active bishop post (Stockfish #2 option)
            else
               Score := 190;
            end if;
         end;
      elsif P = 3 and then FR = Home_R and then TF = 4 then
         --  Bd3 / Bd6
         declare
            D_Pawn_Home : constant Boolean :=
              (if White_To_Move
               then Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 4)) = 1
               else Pvalidade.Tabuleiro (Move_Validation.Square_Of (7, 4)) = -1);
         begin
            if D_Pawn_Home then
               Score := 120; -- Deprioritize blocking the central d-pawn
            else
               Score := 195;
            end if;
         end;
      elsif P = 3 and then FR = Home_R and then TF = 5 then
         --  Be2 / Be7
         declare
            Active_Sq : constant Integer := (if White_To_Move then 27 else 35); -- c4 / c5
         begin
            if Pvalidade.Tabuleiro (Active_Sq) = 0
              and then Pvalidade.Validade (F, Active_Sq)
              and then not Is_Square_Attacked_By_Pawn (White_To_Move, Active_Sq)
              and then not Has_Opponent_Checking_Fork (White_To_Move, Active_Sq)
            then
               Score := 130; -- Deprioritize passive Be2 / Be7 when Bc4 / Bc5 is safe and open
            else
               Score := 195;
            end if;
         end;
      elsif P = 3 and then FR = Home_R and then TF = 6 then
         Score := 185; -- Bf4 / Bf5
      elsif P = 3 and then FR = (if White_To_Move then 2 else 7) and then FF = 5 and then TF = 4 then
         Score := 195; -- Be2-d3 / Be7-d6
      elsif P = 3 and then FR = Home_R and then TF = 7 then
         if TR = (if White_To_Move then 5 else 4) then
            Score := 210; -- Bg5 / Bg4 queen-tempo development
         else
            Score := 185; -- Bg5 / Bg4
         end if;
      elsif P = 20 and then TF = 5 and then TR = Pawn_R then
         Score := 175; -- Qe2 / Qe7
      elsif P = 20 and then TF = 4 and then TR = Pawn_R then
         Score := 170; -- Qd2 / Qd7
      elsif P = 1 and then FR = Pawn_R and then FF = 4
        and then TF = 4 and then TR = FR + 2 * Forward
      then
         --  d4 / d5
         declare
            Own_E_Sq : constant Integer := (if White_To_Move then 29 else 37); -- e4 / e5
            Opp_G_Sq : constant Integer := (if White_To_Move then 39 else 31); -- g5 / g4
            Opp_F_Sq : constant Integer := (if White_To_Move then 38 else 30); -- f5 / f4
         begin
            if Pvalidade.Tabuleiro (Own_E_Sq) = 1 * Own_Sign then
               Score := 220; -- Broad pawn center: d4 alongside e4
            elsif Pvalidade.Tabuleiro (Opp_G_Sq) = -1 * Own_Sign
              or else Pvalidade.Tabuleiro (Opp_F_Sq) = -1 * Own_Sign
            then
               Score := 215; -- Central counter-strike against overextended flank pawn (g4/g5 or f4/f5)
            else
               Score := 190;
            end if;
         end;
      elsif P = 1 and then FR = Pawn_R and then FF = 5
        and then TF = 5 and then TR = FR + 2 * Forward
      then
         --  e4 / e5
         declare
            Own_D_Sq : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
         begin
            if Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign then
               Score := 220; -- Broad pawn center: e4 alongside d4
            else
               Score := 190;
            end if;
         end;
      elsif P = 1 and then FR = Pawn_R and then FF = 3
        and then TF = 3 and then TR = FR + 2 * Forward
      then
         declare
            Own_D_Sq   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 4);
            Own_G_Sq   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 7);
            Opp_D_Sq   : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 5 else 4), 4);
            King_On_C1 : constant Boolean :=
              (if White_To_Move
               then Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 3)) = 999
               else Pvalidade.Tabuleiro (Move_Validation.Square_Of (8, 3)) = -999);
         begin
            if King_On_C1 then
               Score := 0; -- Never advance c-pawn directly in front of castled King on c1/c8!
            elsif Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (Own_G_Sq) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (Opp_D_Sq) = -1 * Own_Sign
            then
               Score := 225; -- King's Indian / Modern central pawn break c7-c5 / c2-c4
            else
               Score := 180; -- c4 / c5
            end if;
         end;
      elsif P = 1 and then FR = Pawn_R and then FF = 5
        and then TF = 5 and then TR = FR + Forward
      then
         declare
            Own_D_Sq : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
            Opp_C_Sq : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
         begin
            if Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (Opp_C_Sq) = -1 * Own_Sign
            then
               Score := 215; -- Queen's Gambit Declined
            else
               Score := 170; -- e3 / e6
            end if;
         end;
      elsif P = 1 and then FR = Pawn_R and then FF = 3
        and then TF = 3 and then TR = FR + Forward
      then
         declare
            Opp_B_Sq     : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
            Own_D_Sq     : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7
            Own_E_Sq     : constant Integer := (if White_To_Move then 29 else 37); -- e4 / e5
            Opp_Wedge_Sq : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 4 else 5), 4);
         begin
            if Pvalidade.Tabuleiro (Opp_B_Sq) = -3 * Own_Sign
              and then Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
              and then Pvalidade.Tabuleiro (Own_E_Sq) = 1 * Own_Sign
            then
               Score := 210; -- Italian/Bishop c3/c6 preparing central strike d4/d5 against Bc4/Bc5
            elsif Pvalidade.Tabuleiro (Opp_Wedge_Sq) = -1 * Own_Sign then
               Score := 215; -- Undermine opponent central pawn wedge with c3/c6
            else
               Score := 165; -- c3 / c6
            end if;
         end;
      elsif P = 1 and then FF = 4
        and then TF = 4 and then TR = FR + Forward
      then
         declare
            Opp_E_Sq  : constant Integer := (if White_To_Move then 37 else 29); -- e5 / e4
            Opp_C_Min : constant Integer := (if White_To_Move then 43 else 19); -- c6 / c3
            Opp_E_Min : constant Integer := (if White_To_Move then 45 else 21); -- e6 / e3
         begin
            if (if White_To_Move then FR = 3 else FR = 6)
              and then Pvalidade.Tabuleiro (Opp_E_Sq) = -1 * Own_Sign
              and then abs Pvalidade.Tabuleiro (Opp_C_Min) in 3 .. 4
              and then abs Pvalidade.Tabuleiro (Opp_E_Min) in 3 .. 4
            then
               Score := 230; -- Central fork strike d3-d4 / d6-d5 threatening fork on enemy minor pieces
            elsif FR = Pawn_R then
               Score := 160; -- d3 / d6
            else
               Score := 150;
            end if;
         end;
      elsif P = 4 and then FF = 4 and then (if White_To_Move then FR = 4 else FR = 5)
        and then TF = 2 and then (if White_To_Move then TR = 5 else TR = 4)
      then
         --  Nd4-b5 / Nd5-b4 outpost pressure against backward central pawn (d6/d3)
         declare
            Opp_D_Pawn : constant Integer := (if White_To_Move then 44 else 20); -- d6 / d3
            Opp_E_Pawn : constant Integer := (if White_To_Move then 45 else 21); -- e6 / e3
         begin
            if Pvalidade.Tabuleiro (Opp_D_Pawn) = -1 * Own_Sign
              and then Pvalidade.Tabuleiro (Opp_E_Pawn) = -1 * Own_Sign
            then
               Score := 225; -- Active knight outpost pressure on d6/d3 + a7/a2 + c7/c2
            else
               Score := 0;
            end if;
         end;
      end if;
   end Score_Dev_Move;

   function Is_Square_Attacked_By_Pawn
     (Defender_White : Boolean; Sq : Integer) return Boolean
   is
      R : constant Integer := Move_Validation.Rank_Of (Sq);
      F : constant Integer := Move_Validation.File_Of (Sq);
      Enemy_Pawn : constant Integer := (if Defender_White then -1 else 1);
   begin
      if Defender_White then
         if R < 8 then
            if F > 1 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R + 1, F - 1)) = Enemy_Pawn then
               return True;
            end if;
            if F < 8 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R + 1, F + 1)) = Enemy_Pawn then
               return True;
            end if;
         end if;
      else
         if R > 1 then
            if F > 1 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R - 1, F - 1)) = Enemy_Pawn then
               return True;
            end if;
            if F < 8 and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (R - 1, F + 1)) = Enemy_Pawn then
               return True;
            end if;
         end if;
      end if;
      return False;
   end Is_Square_Attacked_By_Pawn;

   function Has_Trapped_Piece_Threat
     (Defender_White : Boolean;
      Victim_Sq      : out Integer;
      Attacking_Pawn : out Integer;
      Push_Sq        : out Integer) return Boolean
   is
      Enemy_Pawn_Code : constant Integer := (if Defender_White then -1 else 1);
      Own_Sign        : constant Integer := (if Defender_White then 1 else -1);
      Pawn_Dir        : constant Integer := (if Defender_White then -1 else 1);
   begin
      Victim_Sq      := 0;
      Attacking_Pawn := 0;
      Push_Sq        := 0;

      for P_Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (P_Sq) = Enemy_Pawn_Code then
            declare
               P_Rank : constant Integer := Move_Validation.Rank_Of (P_Sq);
               P_File : constant Integer := Move_Validation.File_Of (P_Sq);
               Adv1_R : constant Integer := P_Rank + Pawn_Dir;
            begin
               if Adv1_R in 1 .. 8 then
                  declare
                     Adv1_Sq : constant Integer :=
                       Move_Validation.Square_Of (Adv1_R, P_File);
                  begin
                     if Pvalidade.Tabuleiro (Adv1_Sq) = 0
                       and then Pvalidade.Validade (P_Sq, Adv1_Sq)
                     then
                        for D_File in -1 .. 1 loop
                           if D_File /= 0 and then P_File + D_File in 1 .. 8 then
                              declare
                                 Att_Rank : constant Integer := Adv1_R + Pawn_Dir;
                              begin
                                 if Att_Rank in 1 .. 8 then
                                    declare
                                       Att_Sq : constant Integer :=
                                         Move_Validation.Square_Of (Att_Rank, P_File + D_File);
                                       Victim_Piece : constant Integer :=
                                         Pvalidade.Tabuleiro (Att_Sq);
                                    begin
                                       if Victim_Piece * Own_Sign > 0
                                         and then abs Victim_Piece in 3 .. 20
                                       then
                                          declare
                                             Saved_Adv1 : constant Integer :=
                                               Pvalidade.Tabuleiro (Adv1_Sq);
                                             Can_Capture_Safely : Boolean := False;
                                             Safe_Squares_Count : Natural := 0;
                                          begin
                                             Pvalidade.Tabuleiro (P_Sq)    := 0;
                                             Pvalidade.Tabuleiro (Adv1_Sq) := Enemy_Pawn_Code;

                                             if Pvalidade.Validade (Att_Sq, Adv1_Sq) then
                                                if See_Gain (Defender_White, Att_Sq, Adv1_Sq) >= 0 then
                                                   Can_Capture_Safely := True;
                                                end if;
                                             end if;

                                             if not Can_Capture_Safely then
                                                for Dest in 1 .. 64 loop
                                                   if Dest /= Adv1_Sq
                                                     and then Pvalidade.Validade (Att_Sq, Dest)
                                                   then
                                                      if not Is_Square_Attacked_By_Pawn (Defender_White, Dest) then
                                                         declare
                                                            Saved_Dest : Integer;
                                                            After_See  : Integer;
                                                            In_Check   : Boolean;
                                                         begin
                                                            Apply_Trial (Att_Sq, Dest, Saved_Dest);
                                                            In_Check := Move_Validation.Is_In_Check (Defender_White);
                                                            declare
                                                               Max_See_Dest : Integer := 0;
                                                               Opp_Piece    : Integer;
                                                            begin
                                                               for Opp_Sq in 1 .. 64 loop
                                                                  Opp_Piece := Pvalidade.Tabuleiro (Opp_Sq);
                                                                  if (if Defender_White then Opp_Piece < 0 else Opp_Piece > 0)
                                                                    and then Pvalidade.Validade (Opp_Sq, Dest)
                                                                  then
                                                                     declare
                                                                        G : constant Integer :=
                                                                          See_Gain (not Defender_White, Opp_Sq, Dest);
                                                                     begin
                                                                        if G > Max_See_Dest then
                                                                           Max_See_Dest := G;
                                                                        end if;
                                                                     end;
                                                                  end if;
                                                               end loop;
                                                               After_See := Max_See_Dest;
                                                            end;
                                                            Undo_Trial (Att_Sq, Dest, Victim_Piece, Saved_Dest);

                                                            if not In_Check and then After_See < Raw_Piece_Value_Cp (abs Victim_Piece) then
                                                               Safe_Squares_Count := Safe_Squares_Count + 1;
                                                            end if;
                                                         end;
                                                      end if;
                                                   end if;
                                                end loop;
                                             end if;

                                             Pvalidade.Tabuleiro (Adv1_Sq) := Saved_Adv1;
                                             Pvalidade.Tabuleiro (P_Sq)    := Enemy_Pawn_Code;

                                             if not Can_Capture_Safely and then Safe_Squares_Count = 0 then
                                                Victim_Sq      := Att_Sq;
                                                Attacking_Pawn := P_Sq;
                                                Push_Sq        := Adv1_Sq;
                                                return True;
                                             end if;
                                          end;
                                       end if;
                                    end;
                                 end if;
                              end;
                           end if;
                        end loop;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;

      return False;
   end Has_Trapped_Piece_Threat;

   function Has_Trapped_Piece_Threat
     (Defender_White : Boolean) return Boolean
   is
      V, A, P : Integer;
   begin
      return Has_Trapped_Piece_Threat (Defender_White, V, A, P);
   end Has_Trapped_Piece_Threat;

   procedure Best_Trapped_Piece_Rescue
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Victim_Sq      : Integer;
      Attacking_Pawn : Integer;
      Push_Sq        : Integer;
   begin
      Found   := False;
      From_Sq := 0;
      To_Sq   := 0;

      if not Has_Trapped_Piece_Threat
               (White_To_Move, Victim_Sq, Attacking_Pawn, Push_Sq)
      then
         return;
      end if;

      declare
         V_File   : constant Integer := Move_Validation.File_Of (Victim_Sq);
         Att_File : constant Integer := Move_Validation.File_Of (Attacking_Pawn);
         Pocket_F : constant Integer := (if V_File in 1 .. 3 then 1 elsif V_File in 6 .. 8 then 8 else Att_File);
         Pocket_R : constant Integer := (if White_To_Move then 2 else 7);
         Step_Dir : constant Integer := (if White_To_Move then 1 else -1);
         Own_Sign : constant Integer := (if White_To_Move then 1 else -1);

         function Move_Resolves_Threat (F, T : Integer) return Boolean is
            Saved_F  : constant Integer := Pvalidade.Tabuleiro (F);
            Saved_T  : constant Integer := Pvalidade.Tabuleiro (T);
            Saved_Ep : constant Integer := Move_Validation.En_Passant_Sq;
            Resolves : Boolean := False;
            use Move_Validation;
         begin
            Pvalidade.Tabuleiro (F) := 0;
            Pvalidade.Tabuleiro (T) := Saved_F;
            if abs Saved_F = 1
              and then abs (Rank_Of (T) - Rank_Of (F)) = 2
              and then File_Of (F) = File_Of (T)
            then
               En_Passant_Sq := Square_Of ((Rank_Of (F) + Rank_Of (T)) / 2, File_Of (F));
            else
               En_Passant_Sq := 0;
            end if;
            Resolves := not Has_Trapped_Piece_Threat (White_To_Move);
            En_Passant_Sq := Saved_Ep;
            Pvalidade.Tabuleiro (T) := Saved_T;
            Pvalidade.Tabuleiro (F) := Saved_F;
            return Resolves;
         exception
            when others =>
               Move_Validation.En_Passant_Sq := Saved_Ep;
               Pvalidade.Tabuleiro (T) := Saved_T;
               Pvalidade.Tabuleiro (F) := Saved_F;
               raise;
         end Move_Resolves_Threat;
      begin
         --  Priority 0: Direct capture of the attacking pawn threatening to advance
         if Attacking_Pawn /= 0 then
            for F in 1 .. 64 loop
               if Pvalidade.Tabuleiro (F) * Own_Sign > 0
                 and then Pvalidade.Validade (F, Attacking_Pawn)
                 and then See_Gain (White_To_Move, F, Attacking_Pawn) >= 0
                 and then Move_Resolves_Threat (F, Attacking_Pawn)
               then
                  From_Sq := F;
                  To_Sq   := Attacking_Pawn;
                  Found   := True;
                  return;
               end if;
            end loop;
         end if;

         --  Priority 1: Flank escape pocket push (1 square: a7-a6 / h7-h6 / a2-a3 / h2-h3)
         if Pocket_F in 1 .. 8 and then Pocket_R in 1 .. 8 then
            declare
               Pocket_Sq : constant Integer :=
                 Move_Validation.Square_Of (Pocket_R, Pocket_F);
               Target_Sq : constant Integer :=
                 Move_Validation.Square_Of (Pocket_R + Step_Dir, Pocket_F);
            begin
               if Pvalidade.Tabuleiro (Pocket_Sq) = Own_Sign
                 and then Pvalidade.Validade (Pocket_Sq, Target_Sq)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, Target_Sq)
                 and then Move_Resolves_Threat (Pocket_Sq, Target_Sq)
               then
                  From_Sq := Pocket_Sq;
                  To_Sq   := Target_Sq;
                  Found   := True;
                  return;
               end if;
            end;
         end if;

         --  Priority 2: Flank challenge push (2 squares: a7-a5 / h7-h5 / a2-a4 / h2-h4)
         if Pocket_F in 1 .. 8 and then Pocket_R in 1 .. 8 then
            declare
               Pocket_Sq : constant Integer :=
                 Move_Validation.Square_Of (Pocket_R, Pocket_F);
               Target_Sq : constant Integer :=
                 Move_Validation.Square_Of (Pocket_R + 2 * Step_Dir, Pocket_F);
            begin
               if Pvalidade.Tabuleiro (Pocket_Sq) = Own_Sign
                 and then Pvalidade.Validade (Pocket_Sq, Target_Sq)
                 and then See_Gain (White_To_Move, Pocket_Sq, Target_Sq) >= 0
                 and then Move_Resolves_Threat (Pocket_Sq, Target_Sq)
               then
                  From_Sq := Pocket_Sq;
                  To_Sq   := Target_Sq;
                  Found   := True;
                  return;
               end if;
            end;
         end if;

         --  Priority 3: Direct safe move of the threatened piece (scored)
         declare
            Best_Dest  : Integer := 0;
            Best_Score : Integer := Integer'First;
            Piece_V    : constant Integer := Pvalidade.Tabuleiro (Victim_Sq);
            Saved_D    : Integer;
            Legal_D    : Boolean;
         begin
            for Dest in 1 .. 64 loop
               if Pvalidade.Validade (Victim_Sq, Dest)
                 and then not Is_Square_Attacked_By_Pawn (White_To_Move, Dest)
               then
                  Apply_Trial (Victim_Sq, Dest, Saved_D);
                  Legal_D := not Move_Validation.Is_In_Check (White_To_Move);
                  Undo_Trial (Victim_Sq, Dest, Piece_V, Saved_D);
                  if Legal_D
                    and then See_Gain (White_To_Move, Victim_Sq, Dest) >= 0
                    and then Move_Resolves_Threat (Victim_Sq, Dest)
                  then
                     declare
                        S   : Integer := 0;
                        Df  : constant Integer := Move_Validation.File_Of (Dest);
                        Dr  : constant Integer := Move_Validation.Rank_Of (Dest);
                     begin
                        if Dest in 1 | 8 | 57 | 64 then
                           S := S - 200;
                        elsif Df in 1 | 8 or else Dr in 1 | 8 then
                           S := S - 50;
                        elsif Df in 3 .. 6 and then Dr in 3 .. 6 then
                           S := S + 40;
                        end if;
                        if Saved_D /= 0 then
                           S := S + 100;
                        end if;
                        if Attacks_Enemy_Queen (White_To_Move, Victim_Sq, Dest) then
                           S := S + 300;
                        end if;
                        if S > Best_Score then
                           Best_Score := S;
                           Best_Dest  := Dest;
                        end if;
                     end;
                  end if;
               end if;
            end loop;
            if Best_Dest /= 0 then
               From_Sq := Victim_Sq;
               To_Sq   := Best_Dest;
               Found   := True;
               return;
            end if;
         end;

         --  Priority 4: Any legal move that resolves the threat (scored to
         --  avoid arbitrary a1/corner retreats such as Qa1)
         declare
            Best_F     : Integer := 0;
            Best_T     : Integer := 0;
            Best_Score : Integer := Integer'First;
            Saved_T    : Integer;
            Legal_M    : Boolean;
         begin
            for F in 1 .. 64 loop
               if Pvalidade.Tabuleiro (F) * Own_Sign > 0 then
                  for T in 1 .. 64 loop
                     if Pvalidade.Validade (F, T)
                       and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                     then
                        declare
                           Piece_F : constant Integer := Pvalidade.Tabuleiro (F);
                        begin
                           Apply_Trial (F, T, Saved_T);
                           Legal_M := not Move_Validation.Is_In_Check (White_To_Move);
                           Undo_Trial (F, T, Piece_F, Saved_T);
                           if Legal_M
                             and then See_Gain (White_To_Move, F, T) >= 0
                             and then Move_Resolves_Threat (F, T)
                           then
                              declare
                                 S  : Integer := 0;
                                 Tf : constant Integer := Move_Validation.File_Of (T);
                                 Tr : constant Integer := Move_Validation.Rank_Of (T);
                              begin
                                 if abs Piece_F = 20 then
                                    S := S - 300;
                                 elsif abs Piece_F = 999 then
                                    S := S - 150;
                                 end if;
                                 if T in 1 | 8 | 57 | 64 then
                                    S := S - 200;
                                 elsif Tf in 1 | 8 or else Tr in 1 | 8 then
                                    S := S - 50;
                                 elsif Tf in 3 .. 6 and then Tr in 3 .. 6 then
                                    S := S + 40;
                                 end if;
                                 if Saved_T /= 0 then
                                    S := S + 100;
                                 end if;
                                 if Attacks_Enemy_Queen (White_To_Move, F, T) then
                                    S := S + 400;
                                 end if;
                                 if S > Best_Score then
                                    Best_Score := S;
                                    Best_F     := F;
                                    Best_T     := T;
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end loop;
               end if;
            end loop;
            if Best_F /= 0 then
               From_Sq := Best_F;
               To_Sq   := Best_T;
               Found   := True;
               return;
            end if;
         end;
      end;
   end Best_Trapped_Piece_Rescue;

   function Allows_Uncontested_Checking_Fork
     (Defender_White : Boolean) return Boolean
   is
      Enemy_White : constant Boolean := not Defender_White;
      Attacker : Integer;
      Saved_Attacker, Saved_Target : Integer;
      Is_Fork : Boolean;
   begin
      for Opp_F in 1 .. 64 loop
         Attacker := Pvalidade.Tabuleiro (Opp_F);
         if abs Attacker = 4 and then (Attacker > 0) = Enemy_White then
            for Opp_T in 1 .. 64 loop
               if Pvalidade.Validade (Opp_F, Opp_T) then
                  Saved_Attacker := Attacker;
                  Saved_Target   := Pvalidade.Tabuleiro (Opp_T);
                  Pvalidade.Tabuleiro (Opp_T) := Saved_Attacker;
                  Pvalidade.Tabuleiro (Opp_F) := 0;

                  if not Move_Validation.Is_In_Check (White_King => Enemy_White)
                    and then Move_Validation.Is_In_Check (White_King => Defender_White)
                  then
                     Is_Fork := False;
                     for Sq in 1 .. 64 loop
                        if Sq /= Opp_T
                          and then Pvalidade.Tabuleiro (Sq) /= 0
                          and then (Pvalidade.Tabuleiro (Sq) > 0) = Defender_White
                          and then abs Pvalidade.Tabuleiro (Sq) >= 7
                          and then Pvalidade.Validade (Opp_T, Sq)
                        then
                           Is_Fork := True;
                           exit;
                        end if;
                     end loop;

                     if Is_Fork
                       and then not Move_Validation.Is_Square_Attacked
                                      (Opp_T, By_White => Defender_White)
                     then
                        Pvalidade.Tabuleiro (Opp_F) := Saved_Attacker;
                        Pvalidade.Tabuleiro (Opp_T) := Saved_Target;
                        return True;
                     end if;
                  end if;

                  Pvalidade.Tabuleiro (Opp_F) := Saved_Attacker;
                  Pvalidade.Tabuleiro (Opp_T) := Saved_Target;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Allows_Uncontested_Checking_Fork;

   procedure Best_Natural_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Piece, Saved_T, Score, Best_Score : Integer;
      Attacker, Gain : Integer;
      Legal, Hanging : Boolean;
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
                    and then not Is_Premature_Knight_Hop
                                  (White_To_Move, F, T)
                    and then not Is_Self_Discovery (White_To_Move, F, T)
                    and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Hanging := False;
                     if Legal then
                        if Allows_Uncontested_Checking_Fork (White_To_Move)
                          or else Has_Opponent_Checking_Fork (White_To_Move, T)
                          or else Has_Opponent_Double_Attack (White_To_Move, T)
                          or else Max_Opponent_See (White_To_Move) > 0
                        then
                           Hanging := True;
                        else
                           for Sq in 1 .. 64 loop
                              Attacker := Pvalidade.Tabuleiro (Sq);
                              if Attacker /= 0
                                and then (Attacker > 0) = (not White_To_Move)
                                and then Pvalidade.Validade (Sq, T)
                              then
                                 Gain := See_Gain (not White_To_Move, Sq, T);
                                 if Gain > 0 then
                                    Hanging := True;
                                    exit;
                                 end if;
                              end if;
                           end loop;
                        end if;
                     end if;
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal and then not Hanging then
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
      Home_R   : constant Integer := (if White_To_Move then 1 else 8);
      Pawn_R   : constant Integer := (if White_To_Move then 2 else 7);
      Forward  : constant Integer := (if White_To_Move then 1 else -1);
      FR, TR   : Integer;
      FF, TF   : Integer;
      Saved_T  : Integer;
      Hit      : Boolean := False;
      Vic      : Integer;
      Non_Pawn_Material : Integer := 0;
      Knights_On_Home_Rank : Boolean;
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

      FR := Move_Validation.Rank_Of (From_Sq);
      TR := Move_Validation.Rank_Of (To_Sq);
      FF := Move_Validation.File_Of (From_Sq);
      TF := Move_Validation.File_Of (To_Sq);
      if FF /= TF then
         return False;
      end if;

      Knights_On_Home_Rank :=
        (Pvalidade.Tabuleiro (Move_Validation.Square_Of (Home_R, 2)) = 4 * Own_Sign)
        and then (Pvalidade.Tabuleiro (Move_Validation.Square_Of (Home_R, 7)) = 4 * Own_Sign);

      if TF = 5 then
         return False;
      elsif TF = 4 then
         if not (FR = Pawn_R and then TR = Pawn_R + Forward and then Knights_On_Home_Rank) then
            return False;
         end if;
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
      Attacker, Gain : Integer;
      Legal, Hanging : Boolean;
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
                  elsif P = 4 and then FR = Home_R and then TF = 3 then
                     Score := 225; -- Nc3/Nc6
                  elsif P = 4 and then FR = Home_R and then TF = 6 then
                     Score := 220; -- Nf3/Nf6
                  elsif P = 4 and then FR = Home_R and then TF = 8 then
                     declare
                        F_Pawn_Sq : constant Integer :=
                          (if White_To_Move
                           then Move_Validation.Square_Of (3, 6)
                           else Move_Validation.Square_Of (6, 6));
                     begin
                        if Pvalidade.Tabuleiro (F_Pawn_Sq) = 1 * Own_Sign then
                           Score := 210; -- Nh3/Nh6 flank development when f3/f6 is blocked
                        end if;
                     end;
                  elsif P = 1 and then FR = Pawn_R and then FF = 4
                    and then TF = 4 and then TR = FR + 2 * Forward
                  then
                     Score := 215; -- d4/d5
                  elsif P = 3 and then FR = Home_R and then TF = 3 then
                     Score := 205; -- Bc4/Bc5
                  elsif P = 1 and then FR = Pawn_R and then FF = 3
                    and then TF = 3 and then TR = FR + 2 * Forward
                  then
                     declare
                        King_Sq : constant Integer := Move_Validation.Find_King (White_To_Move);
                     begin
                        if King_Sq = Move_Validation.Square_Of (Home_R, 3)
                          or else King_Sq = Move_Validation.Square_Of (Home_R, 2)
                        then
                           Score := 0; -- Do not strip castled king's pawn shield
                        else
                           Score := 200; -- c4/c5
                        end if;
                     end;
                  elsif P = 3 and then FR = Home_R and then TF = 2 then
                     declare
                        B_Pawn_Moved : constant Boolean :=
                          (if White_To_Move
                           then Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 2)) /= 1
                           else Pvalidade.Tabuleiro (Move_Validation.Square_Of (7, 2)) /= -1);
                     begin
                        if B_Pawn_Moved then
                           Score := 205; -- Bb2/Bb7 fianchetto
                        end if;
                     end;
                  elsif P = 3 and then FR = Home_R and then TF = 5 then
                     Score := (if Move_Validation.Rank_Of (Move_Validation.Find_King (White_To_Move)) /= Home_R
                               then 210 else 195); -- Be2/Be7
                  elsif P = 3 and then FR = Home_R and then TF = 6 then
                     Score := 195; -- Bf4/Bf5
                  elsif P = 3 and then FR = Home_R and then TF = 7 then
                     Score := 195; -- Bg5/Bg4
                  elsif P = 1 and then FR = Pawn_R and then FF = 4
                    and then TF = 4 and then TR = FR + Forward
                  then
                     Score := 190; -- d3/d6
                  elsif P = 4 and then FR = Home_R and then TF = 4 then
                     Score := 190; -- Nd2/Nd7
                  elsif P = 1 and then FR = Pawn_R and then FF = 5
                    and then TF = 5 and then TR = FR + Forward
                  then
                     declare
                        Own_D_Sq : constant Integer := (if White_To_Move then 28 else 36); -- d4 / d5
                        Opp_C_Sq : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
                     begin
                        if Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
                          and then Pvalidade.Tabuleiro (Opp_C_Sq) = -1 * Own_Sign
                        then
                           Score := 235; -- Queen's Gambit Declined (e7-e6 / e2-e3)
                        else
                           Score := 185; -- e3/e6
                        end if;
                     end;
                  elsif P = 1 and then FR = Pawn_R and then FF = 3
                    and then TF = 3 and then TR = FR + Forward
                  then
                     Score := 180; -- c3/c6
                  end if;

                  if Score > Best_Score
                    and then not Is_Bad_Queen_Sortie (White_To_Move, F, T)
                    and then not Is_Premature_Flank_Bishop (White_To_Move, F, T)
                    and then not Is_Premature_Knight_Hop (White_To_Move, F, T)
                    and then not Is_Self_Discovery (White_To_Move, F, T)
                    and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     Hanging := False;
                     if Legal then
                        if Allows_Uncontested_Checking_Fork (White_To_Move)
                          or else Has_Opponent_Checking_Fork (White_To_Move, T)
                          or else Has_Opponent_Double_Attack (White_To_Move, T)
                          or else Max_Opponent_See (White_To_Move) > 0
                        then
                           Hanging := True;
                        else
                           for Sq in 1 .. 64 loop
                              Attacker := Pvalidade.Tabuleiro (Sq);
                              if Attacker /= 0
                                and then (Attacker > 0) = (not White_To_Move)
                                and then Pvalidade.Validade (Sq, T)
                              then
                                 Gain := See_Gain (not White_To_Move, Sq, T);
                                 if Gain > 0 then
                                    Hanging := True;
                                    exit;
                                 end if;
                              end if;
                           end loop;
                        end if;
                     end if;
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal and then not Hanging then
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
      Before   : constant Integer := Max_Opponent_See (White_To_Move);
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

      declare
         Enemy_Q_Infiltrated : constant Boolean :=
           (if White_To_Move
            then Move_Validation.Rank_Of (Enemy_Q) in 1 .. 4
            else Move_Validation.Rank_Of (Enemy_Q) in 5 .. 8);
      begin
         for F in 1 .. 64 loop
            Piece := Pvalidade.Tabuleiro (F);
            if Piece = 20 * Own_Sign
              and then (Enemy_Q_Infiltrated
                        or else not (Move_Validation.Rank_Of (F) = Home_R
                                     and then Move_Validation.File_Of (F) = 4))
            then
               for T in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (T) = 0
                    and then Pvalidade.Validade (F, T)
                    and then not Is_Square_Attacked_By_Pawn (White_To_Move, T)
                  then
                     Apply_Trial (F, T, Saved_T);
                     Legal := not Move_Validation.Is_In_Check (White_To_Move)
                       and then Pvalidade.Validade (T, Enemy_Q)
                       and then Max_Opponent_See (White_To_Move) <= Before;
                     Undo_Trial (F, T, Piece, Saved_T);
                     if Legal then
                        TF := Move_Validation.File_Of (T);
                        TR := Move_Validation.Rank_Of (T);
                        FF := Move_Validation.File_Of (F);
                        FR := Move_Validation.Rank_Of (F);
                        Score := 100;
                        if Enemy_Q_Infiltrated then
                           Score := Score + 100; -- High priority: challenge infiltrated enemy queen
                        end if;
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
      end;
   end Best_Queen_Tempo_On_Queen;

   procedure Best_Development_Tempo_On_Queen
     (White_To_Move     : Boolean;
      Found             : out Boolean;
      From_Sq           : out Integer;
      To_Sq             : out Integer;
      Allow_Home_Queen  : Boolean := False)
   is
      Own_Sign : constant Integer := (if White_To_Move then 1 else -1);
      Enemy_Q  : constant Integer := Exposed_Enemy_Queen_Sq (White_To_Move);
      Home_Q   : constant Integer := (if White_To_Move then Move_Validation.Square_Of (8, 4) else Move_Validation.Square_Of (1, 4));
      Piece, Saved_T, Score, Best_Score : Integer;
      Legal     : Boolean;
      Attacks_Q : Boolean;
   begin
      Found := False;
      From_Sq := 0;
      To_Sq := 0;
      Best_Score := 0;
      if Enemy_Q = 0
        or else (Enemy_Q = Home_Q and then not Allow_Home_Queen)
        or else Max_Opponent_See (White_To_Move) >= 100
      then
         return;
      end if;

      --  If enemy Queen has invaded to h7 (Black defense) or h2 (White defense),
      --  check if our bishop on e7/e2 can reorganize to d6/d3 to control the
      --  central diagonal, guard e5/e4, and neutralize queen threats.
      declare
         Q_Sq        : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 8); -- h2 / h7
         Own_B_Sq    : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 2 else 7), 5); -- e2 / e7
         Target_B_Sq : constant Integer := Move_Validation.Square_Of ((if White_To_Move then 3 else 6), 4); -- d3 / d6
      begin
         if Enemy_Q = Q_Sq
           and then Pvalidade.Tabuleiro (Own_B_Sq) = 3 * Own_Sign
           and then Pvalidade.Tabuleiro (Target_B_Sq) = 0
           and then Pvalidade.Validade (Own_B_Sq, Target_B_Sq)
         then
            Apply_Trial (Own_B_Sq, Target_B_Sq, Saved_T);
            Legal := not Move_Validation.Is_In_Check (White_To_Move);
            Undo_Trial (Own_B_Sq, Target_B_Sq, 3 * Own_Sign, Saved_T);
            if Legal then
               Found := True;
               From_Sq := Own_B_Sq;
               To_Sq := Target_B_Sq;
               return;
            end if;
         end if;
      end;

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
                     Legal := not Move_Validation.Is_In_Check (White_To_Move);
                     if Legal then
                        Attacks_Q := Pvalidade.Validade (T, Enemy_Q);
                        if not Attacks_Q then
                           --  Discovered attack check: unblocking an attack on Enemy_Q
                           for Att_Sq in 1 .. 64 loop
                              if Pvalidade.Tabuleiro (Att_Sq) * Own_Sign > 0
                                and then Pvalidade.Validade (Att_Sq, Enemy_Q)
                              then
                                 Undo_Trial (F, T, Piece, Saved_T);
                                 if not Pvalidade.Validade (Att_Sq, Enemy_Q) then
                                    Attacks_Q := True;
                                 end if;
                                 Apply_Trial (F, T, Saved_T);
                                 if Attacks_Q then
                                    exit;
                                 end if;
                              end if;
                           end loop;
                        end if;

                        if Attacks_Q
                          and then (not Pvalidade.Validade (Enemy_Q, T)
                                    or else See_Gain (not White_To_Move, Enemy_Q, T) <= 0)
                          and then Score > Best_Score
                        then
                           Best_Score := Score;
                           From_Sq := F;
                           To_Sq := T;
                           Found := True;
                        end if;
                     end if;
                     Undo_Trial (F, T, Piece, Saved_T);
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

      --  If the king's knight is still at home and can develop naturally to
      --  f3/f6 (e.g. 3... Nf6 in the Four Knights), natural knight development
      --  is far superior to passive Be7/Be2 or pawn moves.
      declare
         Home_KN      : constant Integer := (if White_To_Move then 7 else 63);  -- g1 / g8
         Develop_N_Sq : constant Integer := (if White_To_Move then 22 else 46); -- f3 / f6
         KN_Can_Develop : constant Boolean :=
           Pvalidade.Tabuleiro (Home_KN) = 4 * Own_Sign
           and then Pvalidade.Tabuleiro (Develop_N_Sq) = 0
           and then Pvalidade.Validade (Home_KN, Develop_N_Sq)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, Develop_N_Sq);
      begin
         if KN_Can_Develop then
            return;
         end if;
      end;

      --  If an active diagonal square (c4/c5) or central pawn break preparation (c3/c6)
      --  is available, yield to natural active development rather than tucking passively to e2/e7.
      declare
         Active_B_Sq  : constant Integer := (if White_To_Move then 27 else 35); -- c4 / c5
         Opp_B_Sq     : constant Integer := (if White_To_Move then 35 else 27); -- c5 / c4
         Own_C_Sq     : constant Integer := (if White_To_Move then 11 else 51); -- c2 / c7
         Tgt_C_Sq     : constant Integer := (if White_To_Move then 19 else 43); -- c3 / c6
         Own_D_Sq     : constant Integer := (if White_To_Move then 12 else 52); -- d2 / d7
         Home_B_Sq    : constant Integer := (if White_To_Move then 6 else 62);  -- f1 / f8
         Active_Avail : constant Boolean :=
           Pvalidade.Tabuleiro (Active_B_Sq) = 0
           and then Pvalidade.Validade (Home_B_Sq, Active_B_Sq)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, Active_B_Sq);
         Break_Avail  : constant Boolean :=
           Pvalidade.Tabuleiro (Opp_B_Sq) = -3 * Own_Sign
           and then Pvalidade.Tabuleiro (Own_C_Sq) = 1 * Own_Sign
           and then Pvalidade.Tabuleiro (Tgt_C_Sq) = 0
           and then Pvalidade.Tabuleiro (Own_D_Sq) = 1 * Own_Sign
           and then Pvalidade.Validade (Own_C_Sq, Tgt_C_Sq)
           and then not Is_Square_Attacked_By_Pawn (White_To_Move, Tgt_C_Sq);
      begin
         if Active_Avail or else Break_Avail then
            return;
         end if;
      end;

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
                  --  E4: Only count empty-and-unattacked squares (Snippet A.23).
                  --  Defended enemy pieces do not count as escapes.
                  if Piece = 0
                    and then not Move_Validation.Is_Square_Attacked
                                   (NSq, By_White => not Defender_White)
                  then
                     Count := Count + 1;
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
   function Side_Endgame_Bonus_Cp
     (Attacker_White   : Boolean;
      Defender_To_Move : Boolean := False) return Integer
   is
      A_Q, A_R, A_B, A_N, A_P, A_K, A_King : Integer;
      D_Q, D_R, D_B, D_N, D_P, D_K, D_King : Integer;
      D_Other : Integer;
   begin
      Count_Side (Attacker_White, A_Q, A_R, A_B, A_N, A_P, A_K, A_King);
      Count_Side (not Attacker_White, D_Q, D_R, D_B, D_N, D_P, D_K, D_King);
      if A_K = 0 or else D_K = 0 then
         return 0;
      end if;
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
                  --  E2: Side-to-move aware opposition proxy.
                  --  When the defender is to move, the attacker has seized
                  --  the opposition (+15 cp); otherwise static proxy (+5 cp).
                  if Defender_To_Move then
                     Bonus := Bonus + 15;
                  else
                     Bonus := Bonus + 5;
                  end if;
               end if;
               return Bonus;
            end;
         end;
      end if;

      --  0.9.9.17.9 regime: overwhelming-surplus mating drive. The
      --  attacker holds at least one major (Q/R) plus one more piece; the
      --  defender has no queen/rook, at most one minor and at most one
      --  pawn (and something, so the bare-king regimes above stay
      --  authoritative). Covers R+B+N vs K+N / KQ vs KN / QR vs KP --
      --  the analysed game's completely won R+B+N endgame that was thrown
      --  away by rook shuffling into a threefold draw (moves 66-104,
      --  Stockfish mate-in-8 available from move 52). Same confinement
      --  geometry as regime 1: push the defender king to the edge and cut
      --  escapes; Best_Endgame accepts mate-in-1 unconditionally.
      if D_Q = 0 and then D_R = 0
        and then (D_B + D_N) <= 1 and then D_P <= 1
        and then (D_B + D_N + D_P) >= 1
        and then (A_Q + A_R) >= 1
        and then (A_Q + A_R + A_B + A_N) >= 2
      then
         return (4 - Edge_Dist (D_King)) * 12
                + (8 - King_Escape_Count (not Attacker_White)) * 6;
      end if;

      --  No recognized mating regime for this side.
      return 0;
   end Side_Endgame_Bonus_Cp;

   function Endgame_Bonus_Cp return Integer is
   begin
      --  WHITE-positive convention, mirroring Material_Score_Cp so the
      --  two compose directly. Each side's geometry bonus is computed
      --  against the same board, then differenced.
      return Side_Endgame_Bonus_Cp (Attacker_White => True, Defender_To_Move => False)
             - Side_Endgame_Bonus_Cp (Attacker_White => False, Defender_To_Move => False);
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

      --  Rook-pawn draw: one side has K + exactly one rook pawn
      --  (a- or h-file), the other has a lone king on the promotion
      --  corner or the adjacent promotion square of that file (Snippet A.22 / E1).
      --  The defender has reached the drawing zone and cannot be dislodged.
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
               if (P_File = 1 or else P_File = 8) then
                  declare
                     Corner   : constant Integer :=
                       Move_Validation.Square_Of (8, P_File);
                     Adjacent : constant Integer :=
                       Move_Validation.Square_Of
                         (8, (if P_File = 1 then 2 else 7));
                  begin
                     if B_King = Corner or else B_King = Adjacent then
                        return True;
                     end if;
                  end;
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
               if (P_File = 1 or else P_File = 8) then
                  declare
                     Corner   : constant Integer :=
                       Move_Validation.Square_Of (1, P_File);
                     Adjacent : constant Integer :=
                       Move_Validation.Square_Of
                         (1, (if P_File = 1 then 2 else 7));
                  begin
                     if W_King = Corner or else W_King = Adjacent then
                        return True;
                     end if;
                  end;
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
      Baseline := Side_Endgame_Bonus_Cp (White_To_Move, Defender_To_Move => False);
      if Baseline <= 0 then
         return;
      end if;
      Best_Score := Baseline;

      Outer_F :
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
                     Score_After := Side_Endgame_Bonus_Cp
                       (White_To_Move, Defender_To_Move => True);
                     Gives_Check := Move_Validation.Is_In_Check
                       (White_King => not White_To_Move);
                     Enemy_Has_Move := Has_Any_Legal_Move
                       (Defender_White => not White_To_Move);

                     if Gives_Check and then not Enemy_Has_Move then
                        --  E5: Checkmate delivered! Unconditionally accepted without
                        --  requiring strict geometry improvement.
                        Undo_Trial (F, T, Piece, Saved_T);
                        Best_F := F;
                        Best_T := T;
                        exit Outer_F;
                     elsif Enemy_Has_Move and then Score_After > Best_Score then
                        Undo_Trial (F, T, Piece, Saved_T);
                        Best_Score := Score_After;
                        Best_F := F;
                        Best_T := T;
                     else
                        Undo_Trial (F, T, Piece, Saved_T);
                     end if;
                  else
                     Undo_Trial (F, T, Piece, Saved_T);
                  end if;
               end if;
            end loop;
         end if;
      end loop Outer_F;

      if Best_F /= 0 then
         Found   := True;
         From_Sq := Best_F;
         To_Sq   := Best_T;
      end if;
   end Best_Endgame;

   ----------------------------------------------------------------------------
   --  UNIFIED LEGAL ROOT CANDIDATE SNAPSHOT & TRACE (ZOE TIER 1 - GATES P5, P6)
   ----------------------------------------------------------------------------
   procedure Snapshot_Legal_Root_Candidates
     (White_To_Move : Boolean;
      List          : out Root_Candidate_List)
   is
      Gen_List : Move_Gen.Move_List;
   begin
      List.Count := 0;
      Move_Gen.Generate_Legal_Moves (White_To_Move, Gen_List);
      List.Count := Gen_List.N;
      for I in 1 .. Gen_List.N loop
         List.Candidates (I).From_Sq   := Gen_List.V (I).From;
         List.Candidates (I).To_Sq     := Gen_List.V (I).To;
         List.Candidates (I).Promo     := Gen_List.V (I).Promo;
         List.Candidates (I).Is_Legal  := True;
         --  0.9.9.17.20: no per-candidate SEE sweep here. The sole consumer
         --  (root Net Gate) reads the memoized Cost_Of(...).Gain_Cp instead,
         --  which is the identical value on the same board.
         List.Candidates (I).See_Score := 0;
         List.Candidates (I).Stage_Tag := 0;
      end loop;
   end Snapshot_Legal_Root_Candidates;

   procedure Trace_Decision
     (Stage_Name : String;
      From_Sq    : Integer;
      To_Sq      : Integer;
      Promo      : Integer := 0;
      Reason     : String  := "")
   is
      function Move_Str return String is
        (Move_Gen.Move_To_UCI ((From => From_Sq, To => To_Sq, Promo => Promo)));
   begin
      if Trace_Root_Decisions then
         if From_Sq in 1 .. 64 and then To_Sq in 1 .. 64 then
            Ada.Text_IO.Put_Line
              ("info string [root-trace] stage=" & Stage_Name
               & " move=" & Move_Str
               & (if Reason'Length > 0 then " reason=" & Reason else ""));
         else
            Ada.Text_IO.Put_Line
              ("info string [root-trace] stage=" & Stage_Name
               & " (no move)"
               & (if Reason'Length > 0 then " reason=" & Reason else ""));
         end if;
      end if;
   end Trace_Decision;

   function Material_Value (Piece : Pprechess2.Piece_Code) return Integer is
   begin
      return Pprechess2.Material_Value (Piece);
   end Material_Value;

   function Is_Root_Correction_Exempt (Stage : String) return Boolean is
   begin
      --  Documented Step 0b exemption list:
      --  1. Check evasions (Stage 0)
      --  2. Opening traps & tactical trap responses (justified by P19, P21-P23, P25-P28, P30-P33)
      --  3. Central pawn captures/recaptures (justified by P6 orig/mirror, P15)
      --  4. Pawn tempo kick & central occupation (justified by P14, P17)
      --  5. Post-flank-bishop, queen-tempo dev & KBP attacker trade (justified by P4, P7, P8, P11)
      --  6. Stage 6 safety fallbacks (only invoked when Legacy was unsafe)
      return Stage = "Best_Check_Evasion"
        or else Stage = "Best_Opening_Trap_Response"
        or else Stage = "Stage1a_Best_Central_Pawn_Capture"
        or else Stage = "Stage2e_Central_Pawn_Capture"
        or else Stage = "Best_Advanced_Central_Pawn_Recapture"
        or else Stage = "Best_Pawn_Tempo_Kick_Knight"
        or else Stage = "Best_Broad_Pawn_Center_Occupation"
        or else Stage = "Stage2e_Natural_Dev_Post_Flank_Bishop"
        or else Stage = "Stage2e_Dev_Tempo_On_Queen"
        or else Stage = "Stage2f_KBP_Attacker_Trade"
        or else Stage = "Stage6_Safety_Quiet_Alt"
        or else Stage = "Stage6_Safety_Natural_Dev";
   end Is_Root_Correction_Exempt;

   function Should_Keep_Legacy_Over_Correction
     (Stage            : String;
      Legacy_Valid     : Boolean;
      Legacy_Hang_Cp   : Integer;
      Root_Pre_Hang_Cp : Integer;
      Legacy_Safe      : Boolean;
      Legacy_Mate      : Boolean;
      Legacy_Fork      : Boolean;
      Legacy_Threat    : Boolean;
      Legacy_Gain_Cp   : Integer;
      Cand_Is_Capture  : Boolean;
      Cand_Gain_Cp     : Integer) return Boolean
   is
   begin
      if not Legacy_Valid then
         return False;
      end if;
      if Is_Root_Correction_Exempt (Stage) then
         return False;
      end if;
      if Cand_Is_Capture
        and then Cand_Gain_Cp > 0
        and then Cand_Gain_Cp > Legacy_Gain_Cp
      then
         return False;
      end if;
      return Legacy_Safe
        and then Legacy_Hang_Cp <= Root_Pre_Hang_Cp
        and then not Legacy_Mate
        and then not Legacy_Fork
        and then not Legacy_Threat;
   end Should_Keep_Legacy_Over_Correction;

end Search_Integration;
