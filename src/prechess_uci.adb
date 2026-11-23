with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Pvalidade;
with pprechess2;
with Tactical_Search;
with TT_Table;
with TT_Types;
with Time_Management;
with Ada.Real_Time; use Ada.Real_Time;

--  UCI front end. Owns protocol parsing and I/O only: board-rule state
--  (castling/en passant/history) lives in Move_Validation and
--  Search_Integration, the legacy search lives in pprechess2, and time
--  budgeting lives in Time_Management -- this procedure just wires them
--  together the way a UCI GUI expects.
procedure Prechess_UCI is
   --  UCI "position ... moves ..." lines can carry a full game's move
   --  list (thousands of half-moves). 1024 truncated long lists and the
   --  tail was then misread as a bogus command on the next loop pass.
   --  65_536 covers any legal UCI line (a max-length game is ~35 KB).
   Line_Max : constant := 65_536;
   Line     : String (1 .. Line_Max);
   Last     : Natural;

   --  Whose move it really is, in absolute (unmirrored) terms. This is
   --  the single source of truth Search_Integration.Parse_FEN reports
   --  and Handle_Position maintains while replaying "moves".
   Is_White_To_Move : Boolean := True;

   --  0.9.9.17.9 anti-shuffle support: the quiet reversible moves actually
   --  played in the game, as replayed by "position ... moves ..." plus the
   --  engine's own emitted bestmove (appended at emit time). Captures,
   --  pawn advances, castling, promotions and en passant are irreversible
   --  and never recorded. Compute_Best_Move's Stage 6.5 uses this to demote
   --  root choices that merely undo or re-play earlier own moves -- the
   --  Ra1/Rab1 shuffle (moves 21-28) and the Rh8/Rg8 shuffle that drew a
   --  completely won endgame (moves 66-104) in the analysed game.
   type Game_Move_Rec is record
      From_Sq   : Integer;
      To_Sq     : Integer;
      Piece_Code : Integer;
      White_Move : Boolean;
   end record;

   Game_Move_Count : Natural := 0;
   Game_Moves      : array (1 .. 1024) of Game_Move_Rec;

   --  0.9.9.17.10/0.9.9.17.12: UCI option Verify_Depth. 0 = off; the
   --  default is 8 (0.9.9.17.12) -- the setting that caught every miss
   --  diagnosed in the drawn game (13. Ne2 confirmed, 28. Kf1, 42. Nh4)
   --  while respecting normal move times. When > 0, the Tactical_Search
   --  alpha-beta verifies the arbitration pipeline's final move against
   --  every legal alternative at this depth inside the remaining time
   --  replacing it only when an alternative is provably better by
   --  >= Verify_Margin_Opt (default Veto_Margin_Cp = 25 cp) at depth.
   --  The legacy cascade still produces the move in both toggle positions
   --  -- this stage is purely additive on top.
   Verify_Depth_Opt    : Integer := 8;
   Verify_Margin_Opt   : Natural := Tactical_Search.Veto_Margin_Cp;
   --  0.9.9.17.27: deepened verifier. Automatic horizon when the clock allows
   --  (>= 2 s remaining, infinite analysis, or the mate-conversion regime),
   --  and the upper bounds accepted for Verify_Depth / Verify_Margin.
   Deep_Verify_Horizon : constant := 16;
   Max_Verify_Depth    : constant := 20;
   Max_Verify_Margin   : constant := 300;

   --  0.9.9.17.28: verifier wall budget for go infinite (and other unbounded
   --  clocks). Effectively "until stop": UCI stop/quit abort through Tick.
   Unbounded_Verify_Budget_Ms : constant := 86_400_000;

   --  0.9.9.17.14: set when Stage-7 verification produced a valid result;
   --  Execute_Search then leaves reporting to Verify's iteration lines and
   --  suppresses the legacy final line and scratch-PV extension.
   Last_Verify_Used : Boolean := False with Volatile;

   --  UCI protocol state for `debug on|off`, `go searchmoves`, and `go mate`.
   Debug_Mode          : Boolean := False with Volatile;
   Pending_Searchmoves : Move_Gen.Move_List := Tactical_Search.Empty_Move_List;
   Pending_Mate_Target : Natural := 0;

   function Is_UCI_Whitespace (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.CR);

   --  Collapse tabs, CRs, and runs of spaces into single spaces, trimmed.
   function Normalize_UCI_Line (S : String) return String is
      Buf      : String (1 .. S'Length);
      Len      : Natural := 0;
      In_Space : Boolean := True;
   begin
      for Ch of S loop
         if Is_UCI_Whitespace (Ch) then
            if not In_Space then
               Len := Len + 1;
               Buf (Len) := ' ';
               In_Space := True;
            end if;
         else
            Len := Len + 1;
            Buf (Len) := Ch;
            In_Space := False;
         end if;
      end loop;
      if Len > 0 and then Buf (Len) = ' ' then
         Len := Len - 1;
      end if;
      return Buf (1 .. Len);
   end Normalize_UCI_Line;

   function Is_Known_Command_Token (Tok : String) return Boolean is
     (Tok = "uci" or else Tok = "debug" or else Tok = "isready"
      or else Tok = "setoption" or else Tok = "register"
      or else Tok = "ucinewgame" or else Tok = "position"
      or else Tok = "go" or else Tok = "stop" or else Tok = "ponderhit"
      or else Tok = "quit" or else Tok = "board"
      or else Tok = "moves" or else Tok = "help");

   --  UCI spec: ignore unknown tokens before a known command (e.g. `joho debug on`).
   function Strip_Unknown_Leading_Tokens (Cmd : String) return String is
      Pos      : Integer := Cmd'First;
      End_Tok  : Integer;
   begin
      while Pos <= Cmd'Last loop
         while Pos <= Cmd'Last and then Cmd (Pos) = ' ' loop
            Pos := Pos + 1;
         end loop;
         exit when Pos > Cmd'Last;
         End_Tok := Ada.Strings.Fixed.Index (Cmd (Pos .. Cmd'Last), " ");
         if End_Tok = 0 then
            End_Tok := Cmd'Last;
         else
            End_Tok := End_Tok - 1;
         end if;
         if Is_Known_Command_Token (Cmd (Pos .. End_Tok)) then
            return Cmd (Pos .. Cmd'Last);
         end if;
         Pos := End_Tok + 2;
      end loop;
      return "";
   end Strip_Unknown_Leading_Tokens;

   function In_Pending_Searchmoves (F, T, Promo : Integer) return Boolean is
   begin
      if Pending_Searchmoves.N = 0 then
         return True;
      end if;
      for I in 1 .. Pending_Searchmoves.N loop
         if Pending_Searchmoves.V (I).From = F
           and then Pending_Searchmoves.V (I).To = T
           and then (Pending_Searchmoves.V (I).Promo = 0
                     or else Pending_Searchmoves.V (I).Promo = Promo)
         then
            return True;
         end if;
      end loop;
      return False;
   end In_Pending_Searchmoves;

   procedure Reset_Game_Moves is
   begin
      Game_Move_Count := 0;
   end Reset_Game_Moves;

   --  A move that can be part of a to-and-fro cycle: not a capture, not a
   --  pawn move (pawns never revisit squares), not castling, no promotion.
   --  Must be evaluated on the PRE-move board. Promo /= 0 excludes
   --  promotions outright.
   function Quiet_Reversible_Move
     (From_Sq, To_Sq, Promo : Integer) return Boolean
   is
      Piece : constant Integer :=
        (if From_Sq in 1 .. 64 then Pvalidade.Tabuleiro (From_Sq) else 0);
   begin
      if Piece = 0 or else abs Piece = 1 or else Promo /= 0 then
         return False;
      end if;
      if To_Sq not in 1 .. 64 or else Pvalidade.Tabuleiro (To_Sq) /= 0 then
         return False; -- capture (pawn EP is already excluded above)
      end if;
      if abs Piece = 999
        and then abs (Move_Validation.File_Of (To_Sq)
                      - Move_Validation.File_Of (From_Sq)) = 2
      then
         return False; -- castling is irreversible
      end if;
      return True;
   end Quiet_Reversible_Move;

   procedure Record_Game_Move
     (From_Sq, To_Sq, Piece_Code : Integer; White_Move : Boolean)
   is
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return;
      end if;
      --  A repeated "go" on an unchanged position must not duplicate the
      --  engine's own appended move.
      if Game_Move_Count >= 1
        and then Game_Moves (Game_Move_Count).From_Sq = From_Sq
        and then Game_Moves (Game_Move_Count).To_Sq = To_Sq
        and then Game_Moves (Game_Move_Count).White_Move = White_Move
      then
         return;
      end if;
      if Game_Move_Count < Game_Moves'Last then
         Game_Move_Count := Game_Move_Count + 1;
         Game_Moves (Game_Move_Count) :=
           (From_Sq    => From_Sq,
            To_Sq      => To_Sq,
            Piece_Code => Piece_Code,
            White_Move => White_Move);
      end if;
   end Record_Game_Move;

   --  (The hardcoded opening book was removed from pprechess2; no
   --  book-eligibility tracking remains.)

   function Trimmed (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trimmed;

   --  Token squares for the anti-shuffle recorder: "e2e4"-style token to
   --  (from, to). Returns False on anything malformed.
   function UCI_Token_Squares (Token : String; F, T : out Integer) return Boolean is
      FF, FR, TF, TR : Integer;
   begin
      F := 0;
      T := 0;
      if Token'Length < 4 then
         return False;
      end if;
      FF := Character'Pos (Ada.Characters.Handling.To_Lower (Token (Token'First)))
            - Character'Pos ('a') + 1;
      FR := Character'Pos (Token (Token'First + 1)) - Character'Pos ('1') + 1;
      TF := Character'Pos (Ada.Characters.Handling.To_Lower (Token (Token'First + 2)))
            - Character'Pos ('a') + 1;
      TR := Character'Pos (Token (Token'First + 3)) - Character'Pos ('1') + 1;
      if Token'Length > 5
        or else FF not in 1 .. 8 or else FR not in 1 .. 8
        or else TF not in 1 .. 8 or else TR not in 1 .. 8
      then
         return False;
      end if;
      F := Move_Validation.Square_Of (FR, FF);
      T := Move_Validation.Square_Of (TR, TF);
      return True;
   end UCI_Token_Squares;

   procedure Replay_Moves (Moves_Str : String) is
      Start_Pos : Integer := Moves_Str'First;
      End_Pos   : Integer;
      Applied   : Boolean;
   begin
      while Start_Pos <= Moves_Str'Last loop
         --  Skip any run of spaces so multiple spaces / leading spaces do
         --  not produce an empty token and an unwanted side-to-move flip.
         Start_Pos :=
           Ada.Strings.Fixed.Index_Non_Blank (Moves_Str (Start_Pos .. Moves_Str'Last));
         exit when Start_Pos = 0;
         End_Pos := Ada.Strings.Fixed.Index (Moves_Str (Start_Pos .. Moves_Str'Last), " ");
         if End_Pos = 0 then
            End_Pos := Moves_Str'Last + 1;
         end if;
         declare
            Token : constant String := Moves_Str (Start_Pos .. End_Pos - 1);
            --  0.9.9.17.9: snapshot pre-move facts for the recorder.
            Mover_White : constant Boolean := Is_White_To_Move;
            Tok_F, Tok_T : Integer;
            Tok_Ok   : constant Boolean := UCI_Token_Squares (Token, Tok_F, Tok_T);
            Tok_Piece : Integer := 0;
            Tok_Quiet : Boolean := False;
         begin
            if Tok_Ok and then Token'Length = 4 then
               Tok_Piece := Pvalidade.Tabuleiro (Tok_F);
               Tok_Quiet := Quiet_Reversible_Move (Tok_F, Tok_T, 0);
            end if;
            Search_Integration.Make_Move_UCI (Token, Is_White_To_Move, Applied);
            if Applied then
               Is_White_To_Move := not Is_White_To_Move;
               if Tok_Quiet and then Tok_Piece /= 0 then
                  Record_Game_Move (Tok_F, Tok_T, abs Tok_Piece, Mover_White);
               end if;
            else
               Put_Line ("info string position command: rejected move '"
                         & Token
                         & "' (turn or legality mismatch); board may diverge");
               return;
            end if;
         end;
         Start_Pos := End_Pos + 1;
      end loop;
   end Replay_Moves;

   procedure Handle_Position (Cmd : String) is
      Parsed : Boolean := False;
   begin
      if Cmd = "position startpos"
        or else (Cmd'Length > 18
                 and then Cmd (Cmd'First .. Cmd'First + 17) = "position startpos ")
      then
         Parsed := Search_Integration.Try_Parse_FEN
           ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Is_White_To_Move);
         Reset_Game_Moves;

         if Parsed then
            --  A fresh position also resets the legacy draw-avoidance counter;
            --  without this, analysing several positions in one session biases
            --  later unrelated positions with the previous game's counter.
            pprechess2.Contagem_Empate := 0;
            declare
               Moves_Idx : constant Integer := Ada.Strings.Fixed.Index (Cmd, " moves ");
            begin
               if Moves_Idx > 0 then
                  Replay_Moves (Trimmed (Cmd (Moves_Idx + 7 .. Cmd'Last)));
               end if;
            end;
         end if;

      elsif Cmd'Length > 13 and then Cmd (Cmd'First .. Cmd'First + 12) = "position fen " then
         declare
            Fen_Str    : constant String := Trimmed (Cmd (Cmd'First + 13 .. Cmd'Last));
            Moves_Idx  : constant Integer := Ada.Strings.Fixed.Index (Fen_Str, " moves ");
            Actual_Fen : constant String :=
              (if Moves_Idx > 0 then Fen_Str (Fen_Str'First .. Moves_Idx - 1) else Fen_Str);
         begin
            Parsed := Search_Integration.Try_Parse_FEN (Actual_Fen, Is_White_To_Move);
            if Parsed then
               pprechess2.Contagem_Empate := 0;
               Reset_Game_Moves;
               if Moves_Idx > 0 then
                  Replay_Moves (Trimmed (Fen_Str (Moves_Idx + 7 .. Fen_Str'Last)));
               end if;
            end if;
         end;
      end if;

   end Handle_Position;

   function Move_To_String (From_Sq, To_Sq, Promo : Integer) return String is
   begin
      if From_Sq not in 1 .. 64 or else To_Sq not in 1 .. 64 then
         return "0000";
      end if;
      return Move_Gen.Move_To_UCI ((From => From_Sq, To => To_Sq, Promo => Promo));
   end Move_To_String;

   --  Apply a move to the raw board only (no rights/history
   --  bookkeeping): used for scratch continuations that are fully
   --  restored afterwards, both by the PV builder in Handle_Go and by
   --  the forced-mate verification in Compute_Best_Move. Handles the
   --  three special shapes that can appear: promotion, a castle's rook
   --  hop, and an en-passant capture.
   procedure Apply_Raw (F, T, Promo : Integer) is
      Piece : constant Integer := Pvalidade.Tabuleiro (F);
   begin
      if abs Piece = 1
        and then Pvalidade.Tabuleiro (T) = 0
        and then Move_Validation.File_Of (T) /= Move_Validation.File_Of (F)
      then -- en passant: remove the bypassed pawn
         Pvalidade.Tabuleiro
           (Move_Validation.Square_Of
              (Move_Validation.Rank_Of (F), Move_Validation.File_Of (T))) := 0;
      end if;
      if abs Piece = 999
        and then abs (Move_Validation.File_Of (T) - Move_Validation.File_Of (F)) = 2
      then -- castle: hop the rook too
         Move_Validation.Apply_Castle_Rook_Move
           (White_To_Move => Piece > 0,
            Kingside      => Move_Validation.File_Of (T) > Move_Validation.File_Of (F));
      end if;
      if Promo /= 0 then
         Pvalidade.Tabuleiro (T) := (if Piece > 0 then Promo else -Promo);
      else
         Pvalidade.Tabuleiro (T) := Piece;
      end if;
      Pvalidade.Tabuleiro (F) := 0;
   end Apply_Raw;

   --  S-G3-1: Scratch apply with full en-passant bookkeeping: Apply_Raw plus the
   --  En_Passant_Sq update the real applier performs (search_integration
   --  Make_Move_UCI 886-890). Every scratch caller must save/restore
   --  En_Passant_Sq beside the board.
   procedure Apply_Scratch (F, T, Promo : Integer) is
      Piece : constant Integer := Pvalidade.Tabuleiro (F);
      use Move_Validation;
      FR : constant Integer := Rank_Of (F);
      TR : constant Integer := Rank_Of (T);
   begin
      Apply_Raw (F, T, Promo);
      if abs Piece = 1
        and then abs (TR - FR) = 2
        and then File_Of (F) = File_Of (T)
      then
         En_Passant_Sq := Square_Of ((FR + TR) / 2, File_Of (F));
      else
         En_Passant_Sq := 0;
      end if;
      --  Scratch keys must describe the same position as the real move:
      --  king/rook moves and rook captures update castling rights too.
      Move_Validation.Update_Rights_After_Move (F, T, Piece);
   end Apply_Scratch;

   --  Runs the legacy search for the side to move now, folding in
   --  castling / en passant per the policy documented in
   --  README_UCI.md, "Root move integration policy", and verifying the
   --  final choice against short forced mates
   --  (Search_Integration.Has_Forced_Mate_Within_Two): a move that
   --  walks into mate-in-two is vetoed in the cascade
   --  (pprechess2.Jogada_Vetada) and the search re-run for its
   --  next-best choice, bounded by a small retry cap and the time
   --  budget. Returns Best_From = Best_To = 0 when there is no legal
   --  move at all (checkmate or stalemate).
   procedure Compute_Best_Move
     (Best_From, Best_To, Best_Promo : out Integer)
   is
      Legacy_From, Legacy_To : Integer;
      Legacy_Was_Capture     : Boolean;
      Ep_From                : Integer;
      Castle_Found, Castle_King : Boolean;
      Hang_Found             : Boolean;
      Hang_From, Hang_To     : Integer;
      Resolve_Found          : Boolean;
      Resolve_From, Resolve_To : Integer;
      Dev_Found              : Boolean;
      Dev_From, Dev_To       : Integer;
      Trade_Found            : Boolean;
      Trade_From, Trade_To   : Integer;
      QSide_Found            : Boolean;
      QSide_From, QSide_To   : Integer;
      Kick_Found             : Boolean;
      Kick_From, Kick_To     : Integer;
      Pin_Found              : Boolean;
      Pin_From, Pin_To, Pin_Hang : Integer;
      Nat_Found              : Boolean;
      Nat_From, Nat_To       : Integer;
      Re_Found               : Boolean;
      Re_From, Re_To         : Integer;
      Cen_Found              : Boolean;
      Cen_From, Cen_To       : Integer;
      Evasion_Found          : Boolean;
      Evasion_From, Evasion_To : Integer;
      Tuck_Found             : Boolean;
      Tuck_From, Tuck_To     : Integer;
      Blockade_King_Found    : Boolean;
      Blockade_King_From, Blockade_King_To : Integer;
      Rook_Found             : Boolean;
      Rook_From, Rook_To     : Integer;
      Broad_Found            : Boolean;
      Broad_From, Broad_To   : Integer;
      KID_Found              : Boolean;
      KID_From, KID_To       : Integer;
      Wedge_Found            : Boolean;
      Wedge_From, Wedge_To   : Integer;
      DblF_Found             : Boolean;
      DblF_From, DblF_To     : Integer;
      Benoni_Found           : Boolean;
      Benoni_From, Benoni_To : Integer;
      Outpost_Maj_Found      : Boolean;
      Outpost_Maj_From, Outpost_Maj_To : Integer;
      Queen_Def_Found        : Boolean;
      Queen_Def_From, Queen_Def_To : Integer;
      QDev_Found             : Boolean;
      QDev_From, QDev_To     : Integer;
      Rim_N_Found            : Boolean;
      Rim_N_From, Rim_N_To   : Integer;
      QSide_Flank_Found      : Boolean;
      QSide_Flank_From, QSide_Flank_To : Integer;
      Rook_Open_Found        : Boolean;
      Rook_Open_From, Rook_Open_To : Integer;
      Outpost_Denial_Found   : Boolean;
      Outpost_Denial_From, Outpost_Denial_To : Integer;
      Knight_Challenge_Found : Boolean;
      Knight_Challenge_From, Knight_Challenge_To : Integer;
      Rook_Align_Found       : Boolean;
      Rook_Align_From, Rook_Align_To : Integer;
      Recap_Found            : Boolean;
      Recap_From, Recap_To   : Integer;
      MinorCap_Found         : Boolean;
      MinorCap_From, MinorCap_To : Integer;
      Fork_Found             : Boolean;
      Fork_From, Fork_To     : Integer;
      Outpost_Found          : Boolean;
      Outpost_From, Outpost_To : Integer;
      Trap_Found             : Boolean;
      Trap_From, Trap_To     : Integer;
      FL_Found               : Boolean;
      FL_From, FL_To         : Integer;
      Esc_Found              : Boolean;
      Esc_From, Esc_To       : Integer;
      Infil_Found            : Boolean;
      Infil_From, Infil_To   : Integer;
      Tempo_Found            : Boolean;
      Tempo_From, Tempo_To   : Integer;
      Pawn_Tempo_Found       : Boolean;
      Pawn_Tempo_From, Pawn_Tempo_To : Integer;
      Solid_Found            : Boolean;
      Solid_From, Solid_To   : Integer;
      Alt_Found              : Boolean;
      Alt_From, Alt_To       : Integer;
      EqCap_Found            : Boolean;
      EqCap_From, EqCap_To   : Integer;
      Undefended_Maj_Found   : Boolean;
      Undefended_Maj_From, Undefended_Maj_To : Integer;
      Infil_Guard_Found      : Boolean;
      Infil_Guard_From, Infil_Guard_To : Integer;
      Diag_Ctrl_Found        : Boolean;
      Diag_Ctrl_From, Diag_Ctrl_To : Integer;
      Skewer_Found           : Boolean;
      Skewer_From, Skewer_To : Integer;
      Pin_Shield_Found       : Boolean;
      Pin_Shield_From, Pin_Shield_To : Integer;
      Flank_Q_Infil_Found    : Boolean;
      Flank_Q_Infil_From, Flank_Q_Infil_To : Integer;
      Cramp_Break_Found      : Boolean;
      Cramp_Break_From, Cramp_Break_To     : Integer;
      Fork_Parry_Found       : Boolean;
      Fork_Parry_From, Fork_Parry_To       : Integer;
      Najdorf_Q_Found        : Boolean;
      Najdorf_Q_From, Najdorf_Q_To         : Integer;
      Bishop_Kick_Found      : Boolean;
      Bishop_Kick_From, Bishop_Kick_To     : Integer;
      Zwischen_Found         : Boolean;
      Zwischen_From, Zwischen_To           : Integer;
      Rook_Cramp_Found       : Boolean;
      Rook_Cramp_From, Rook_Cramp_To       : Integer;
      Unpin_K_Found          : Boolean;
      Unpin_K_From, Unpin_K_To             : Integer;
      QFork_Found            : Boolean;
      QFork_From, QFork_To   : Integer;
      Chose_Winning_Capture  : Boolean := False;
      Chose_Root_Correction  : Boolean := False;
      Chose_Trap             : Boolean := False;
      Max_Vetoes  : constant := 8;
      First_From, First_To : Integer := 0;
      Saved_Board : Pvalidade.Board_Array;
      No_Move     : Boolean := False;
      Root_Pre_Hang_Cp : Integer := 0;
      Root_Pre_Double_Attack : Boolean := False;
      --  B-C5: Root_Before piece-code gate removed in favor of Move_Is_Safe.
      Root_Candidates : Search_Integration.Root_Candidate_List;

      procedure Run_Legacy is
      begin
         Search_Integration.Search_Is_Mirrored := not Is_White_To_Move;
         --  Unlike Search_Is_Mirrored (cleared right after the
         --  flip-back below), this stays set through the final
         --  Report_UCI call so the reported score keeps the
         --  side-to-move perspective UCI requires.
         Search_Integration.Report_For_Black := not Is_White_To_Move;
         if Search_Integration.Search_Is_Mirrored then
            Search_Integration.Flip_Board;
         end if;

         begin
            pprechess2.Prechess2;
         exception
            when others =>
               --  0.9.9.17.20 armor: never leave the engine on the mirrored
               --  frame or with the mirrored flag set; the caller's handler
               --  must be able to emit a legal bestmove afterwards.
               if Search_Integration.Search_Is_Mirrored then
                  Search_Integration.Flip_Board;
                  Search_Integration.Search_Is_Mirrored := False;
               end if;
               raise;
         end;

         Legacy_From := pprechess2.Cc;
         Legacy_To   := pprechess2.Dd;
         Legacy_Was_Capture :=
           Legacy_From /= Legacy_To and then Pvalidade.Tabuleiro (Legacy_To) /= 0;

         if Search_Integration.Search_Is_Mirrored then
            --  Preserve the 0 = "no legal move" sentinel (Black
            --  checkmate/stalemate) through the un-mirror. Mirror_Square
            --  has Pre Sq in 1 .. 64, so passing 0 raises Assertion_Error
            --  that propagates uncaught out of Compute_Best_Move /
            --  Handle_Go and aborts the engine before the
            --  "bestmove 0000" path can run -- asymmetric with the
            --  White-to-move branch, which skips mirroring entirely.
            if Legacy_From /= 0 then
               Legacy_From := Move_Validation.Mirror_Square (Legacy_From);
            end if;
            if Legacy_To /= 0 then
               Legacy_To   := Move_Validation.Mirror_Square (Legacy_To);
            end if;
            Search_Integration.Flip_Board; -- restore the real board
            --  Real (unmirrored) coordinates from here on: clear the
            --  flag so a later Report_UCI does not un-mirror twice.
            Search_Integration.Search_Is_Mirrored := False;
         end if;
      end Run_Legacy;

      procedure Run_Legacy_Cascade_Only is
      begin
         Search_Integration.Search_Is_Mirrored := not Is_White_To_Move;
         Search_Integration.Report_For_Black := not Is_White_To_Move;
         if Search_Integration.Search_Is_Mirrored then
            Search_Integration.Flip_Board;
         end if;

         begin
            pprechess2.Prechess2_Cascade_Only;
         exception
            when others =>
               if Search_Integration.Search_Is_Mirrored then
                  Search_Integration.Flip_Board;
                  Search_Integration.Search_Is_Mirrored := False;
               end if;
               raise;
         end;

         Legacy_From := pprechess2.Cc;
         Legacy_To   := pprechess2.Dd;
         Legacy_Was_Capture :=
           Legacy_From /= Legacy_To and then Pvalidade.Tabuleiro (Legacy_To) /= 0;

         if Search_Integration.Search_Is_Mirrored then
            if Legacy_From /= 0 then
               Legacy_From := Move_Validation.Mirror_Square (Legacy_From);
            end if;
            if Legacy_To /= 0 then
               Legacy_To   := Move_Validation.Mirror_Square (Legacy_To);
            end if;
            Search_Integration.Flip_Board;
            Search_Integration.Search_Is_Mirrored := False;
         end if;
      end Run_Legacy_Cascade_Only;

      function Promo_Of (F, T : Integer) return Integer is
      begin
         if abs Pvalidade.Tabuleiro (F) = 1
           and then (Move_Validation.Rank_Of (T) = 1
                     or else Move_Validation.Rank_Of (T) = 8)
         then
            return 20; -- auto-queen; see README, "Root move integration policy"
         end if;
         return 0;
      end Promo_Of;

      --  P14 root safety veto (added 0.7.9.9, gate P73): after a trial
      --  move lands a knight/bishop/rook/queen on T, does the opponent
      --  have a legal, SEE-positive reply there that nets MORE material
      --  than this move itself already banked by capturing whatever was
      --  on T? One-ply SEE via Search_Integration.See_Gain (consistent
      --  with Best_Winning_Capture / Best_Non_Losing_Capture elsewhere
      --  in this codebase), generalized with Captured_Value so a fair or
      --  favorable trade (e.g. a straight queen-for-queen swap) is never
      --  falsely vetoed -- only a real net material loss is. Pawns (and
      --  the king, e.g. after castling) are out of scope: hanging a bare
      --  pawn is already the job of Is_Soft_Defend / Best_En_Prise_Resolve
      --  elsewhere; this closes the specific gap Move_Is_Safe previously
      --  had -- it only checked forced mate within two, never material
      --  loss -- for the higher-value pieces the cascade's legacy tiers
      --  (Jogada_PerdeD/T/B/C/Perde_Profunda) can still let through. Must
      --  be called with the trial move already applied to
      --  Pvalidade.Tabuleiro (Move_Is_Safe's convention). General
      --  SEE-style logic -- no FEN/position special-casing.
      function Root_Piece_Hangs
        (T : Integer; Captured_Value : Integer) return Boolean
      is
         Captured_Value_Cp : constant Integer :=
           Search_Integration.Raw_Piece_Value_Cp (Captured_Value);
         Enemy_White    : constant Boolean := not Is_White_To_Move;
         Attacker       : Integer;
         Saved_Attacker : Integer;
         Saved_Victim   : Integer;
         Gain           : Integer;
         Best_Gain      : Integer := 0;
      begin
         if abs Pvalidade.Tabuleiro (T) >= 999 then
            return False; -- king: not this veto's job
         end if;
         if Search_Integration.Is_Square_Attacked_By_Pawn (Is_White_To_Move, T) then
            --  K5/N12 FIX: pawn-vs-pawn swaps and piece-defended pawns are trades,
            --  not hangs. One SEE answers it; no special case needed.
            declare
               Enemy_Pawn : Integer := 0;
            begin
               for S in 1 .. 64 loop
                  declare
                     P : constant Integer := Pvalidade.Tabuleiro (S);
                  begin
                     if P = (if Is_White_To_Move then -1 else 1)
                       and then Pvalidade.Validade (S, T)
                     then
                        Enemy_Pawn := S;
                        exit;
                     end if;
                  end;
               end loop;
               if Enemy_Pawn /= 0 then
                  declare
                     G : constant Integer :=
                       Search_Integration.See_Gain (not Is_White_To_Move, Enemy_Pawn, T);
                  begin
                     if G >= Integer'Max (100, Captured_Value_Cp) then
                        return True;
                     end if;
                  end;
               end if;
            end;
         end if;
         for Sq in 1 .. 64 loop
            Attacker := Pvalidade.Tabuleiro (Sq);
            if Attacker /= 0
              and then Sq /= T
              and then (Attacker > 0) = Enemy_White
              and then Pvalidade.Validade (Sq, T)
            then
               Gain := Search_Integration.See_Gain
                 (White_Captures => Enemy_White, From_Sq => Sq, To_Sq => T);
               if Gain > Best_Gain then
                  --  Confirm legality: a pinned attacker cannot really
                  --  take here (mirrors the Is_In_Check legality check
                  --  Best_Winning_Capture already uses for its own
                  --  candidate captures).
                  Saved_Attacker := Attacker;
                  Saved_Victim   := Pvalidade.Tabuleiro (T);
                  Pvalidade.Tabuleiro (T)  := Saved_Attacker;
                  Pvalidade.Tabuleiro (Sq) := 0;
                  if not Move_Validation.Is_In_Check (White_King => Enemy_White) then
                     Best_Gain := Gain;
                     --  Once the return threshold is proven, the exact maximum
                     --  is irrelevant to this Boolean gate. Restore the trial
                     --  board BEFORE returning: this function must not leak
                     --  board mutation to its caller.
                     if Best_Gain >= Integer'Max (100, Captured_Value_Cp) then
                        Pvalidade.Tabuleiro (Sq) := Saved_Attacker;
                        Pvalidade.Tabuleiro (T)  := Saved_Victim;
                        return True;
                     end if;
                  end if;
                  Pvalidade.Tabuleiro (Sq) := Saved_Attacker;
                  Pvalidade.Tabuleiro (T)  := Saved_Victim;
               end if;
            end if;
         end loop;
         return Best_Gain >= Integer'Max (100, Captured_Value_Cp);
      end Root_Piece_Hangs;

      --  S-G5-2 (O2): One cached cost record per candidate
      type Move_Cost is record
         Gain_Cp    : Integer;   --  See_Gain on the pre-move board
         Hang_Cp    : Integer;   --  Max_Opponent_See on the post-move board
         Net_Cp     : Integer;   --  Gain_Cp + Root_Pre_Hang_Cp - Hang_Cp
         Mate       : Boolean;   --  Has_Forced_Mate_Within_Two after the apply
         Threat     : Boolean;   --  Has_Trapped_Piece_Threat after the apply
         Fork       : Boolean;   --  Has_Opponent_Checking_Fork after the apply
         Self_Hang        : Boolean;   --  Moved quiet piece hangs to winning enemy capture
         Checking_Capture : Boolean;   --  Opponent has an immediate capture that delivers check
         Queen_Attack     : Boolean;   --  Moved piece attacks enemy Queen
         Is_Capture       : Boolean;
         Rep_Count  : Integer;   --  Prior occurrences in History (>=2 means move causes 3-fold draw)
         --  0.9.9.17.20: memoized veto verdicts (pure functions of F,T at the
         --  root board), so Move_Is_Safe never recomputes them per stage.
         Guard_Unsafe     : Boolean;
         Deflected_Unsafe : Boolean;
         Deep_Safe        : Boolean;
      end record;

      Cost_Computed : array (1 .. 64, 1 .. 64) of Boolean :=
        [others => [others => False]];
      Cost_Cache    : array (1 .. 64, 1 .. 64) of Move_Cost;

      --  Completion declarations: bodies follow Cost_Of; the memoized cost
      --  record needs these verdicts, computed once per root move.
      function Guard_Removal_Unsafe (F, T : Integer) return Boolean;
      function Deflected_Defender_Unsafe (F, T : Integer) return Boolean;

      function Cost_Of (F, T : Integer) return Move_Cost is
         use Search_Integration;
      begin
         if F not in 1 .. 64 or else T not in 1 .. 64 then
            return (Gain_Cp => 0, Hang_Cp => 0, Net_Cp => -99999,
                    Mate => True, Threat => True, Fork => True,
                    Self_Hang => True, Checking_Capture => True, Queen_Attack => False, Is_Capture => False,
                    Rep_Count => 0,
                    Guard_Unsafe => True, Deflected_Unsafe => True,
                    Deep_Safe => False);
         end if;
         if Cost_Computed (F, T) then
            return Cost_Cache (F, T);
         end if;
         declare
            Saved_Ep   : constant Integer := Move_Validation.En_Passant_Sq;
            Saved_WK   : constant Boolean := Move_Validation.White_Castling_K;
            Saved_WQ   : constant Boolean := Move_Validation.White_Castling_Q;
            Saved_BK   : constant Boolean := Move_Validation.Black_Castling_K;
            Saved_BQ   : constant Boolean := Move_Validation.Black_Castling_Q;
            Is_Cap     : constant Boolean :=
              Pvalidade.Tabuleiro (T) /= 0
                or else (abs Pvalidade.Tabuleiro (F) = 1
                         and then Move_Validation.En_Passant_Sq /= 0
                         and then T = Move_Validation.En_Passant_Sq);
            Gain       : constant Integer := See_Gain (Is_White_To_Move, F, T);
            Hang       : Integer;
            Mate       : Boolean;
            Threat     : Boolean;
            Fork       : Boolean;
            Self_Hang  : Boolean;
            Checking_Capture : Boolean;
            Queen_Attack     : Boolean;
         begin
            Saved_Board := Pvalidade.Tabuleiro;
            Apply_Scratch (F, T, Promo_Of (F, T));
            Hang := Max_Opponent_See (Is_White_To_Move,
                                      Except_Sq => (if Is_Cap then T else 0));
            if Hang < 100 then
               Hang := 0;
            end if;
            Mate := Has_Forced_Mate_Within_Two
                      (Attacker_White => not Is_White_To_Move);
            Threat := Has_Trapped_Piece_Threat (Is_White_To_Move);
            Fork   := (abs Pvalidade.Tabuleiro (T) > 1
                       and then (Has_Opponent_Checking_Fork
                                   (White_To_Move => Is_White_To_Move,
                                    Target_Sq     => T)
                                 or else Has_Opponent_Double_Attack
                                           (White_To_Move => Is_White_To_Move,
                                            Target_Sq     => T)
                                 or else Allows_Major_Pin
                                           (White_To_Move => Is_White_To_Move,
                                            Target_Sq     => T)))
                      or else Search_Integration.Allows_Uncontested_Checking_Fork (Is_White_To_Move)
                      --  Step 0b: Exclude pawn capture square T when checking global double attacks,
                      --  since recapture on T is already priced into Gain_Cp = See_Gain(F, T).
                      or else ((not Root_Pre_Double_Attack)
                               and then Has_Opponent_Double_Attack
                                          (White_To_Move => Is_White_To_Move,
                                           Target_Sq     => 0,
                                           Except_Sq     =>
                                             (if Is_Cap and then abs Pvalidade.Tabuleiro (T) = 1
                                              then T else 0)));
            Self_Hang := (not Is_Cap)
              and then (abs Saved_Board (F) >= 1)
              and then Root_Piece_Hangs (T, 0);

            declare
               Opp_Sign : constant Integer := (if Is_White_To_Move then -1 else 1);
               Us_Sign  : constant Integer := (if Is_White_To_Move then 1 else -1);
               Found_Check_Cap : Boolean := False;
            begin
               for Opp_F in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Opp_F) * Opp_Sign > 0 then
                     for Opp_T in 1 .. 64 loop
                        if Pvalidade.Tabuleiro (Opp_T) * Us_Sign > 0
                          and then Pvalidade.Validade (Opp_F, Opp_T)
                        then
                           declare
                              Saved_T_Piece : constant Integer := Pvalidade.Tabuleiro (Opp_T);
                              Opp_P_Piece   : constant Integer := Pvalidade.Tabuleiro (Opp_F);
                           begin
                              Pvalidade.Tabuleiro (Opp_T) := Opp_P_Piece;
                              Pvalidade.Tabuleiro (Opp_F) := 0;
                              if Move_Validation.Is_In_Check (Is_White_To_Move)
                                and then See_Gain (not Is_White_To_Move, Opp_F, Opp_T) >= 100
                              then
                                 Found_Check_Cap := True;
                              end if;
                              Pvalidade.Tabuleiro (Opp_F) := Opp_P_Piece;
                              Pvalidade.Tabuleiro (Opp_T) := Saved_T_Piece;
                              exit when Found_Check_Cap;
                           end;
                        end if;
                     end loop;
                  end if;
                  exit when Found_Check_Cap;
               end loop;
               Checking_Capture := Found_Check_Cap;
            end;

            declare
               Opp_Q_Code : constant Integer := (if Is_White_To_Move then -20 else 20);
               Attacks_Q  : Boolean := False;
            begin
               for Sq in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Sq) = Opp_Q_Code then
                     Attacks_Q := Pvalidade.Validade (T, Sq);
                     exit;
                  end if;
               end loop;
               Queen_Attack := Attacks_Q;
            end;

            Move_Validation.En_Passant_Sq := Saved_Ep;
            Move_Validation.White_Castling_K := Saved_WK;
            Move_Validation.White_Castling_Q := Saved_WQ;
            Move_Validation.Black_Castling_K := Saved_BK;
            Move_Validation.Black_Castling_Q := Saved_BQ;
            Pvalidade.Tabuleiro := Saved_Board;
            --  Memoized veto verdicts: pure functions of (F,T) on the
            --  restored pre-move board, computed once per root move.
            Cost_Cache (F, T) :=
              (Gain_Cp    => Gain,
               Hang_Cp    => Hang,
               Net_Cp     => Gain + Root_Pre_Hang_Cp - Hang,
               Mate       => Mate,
               Threat     => Threat,
               Fork             => Fork,
               Self_Hang        => Self_Hang,
               Checking_Capture => Checking_Capture,
               Queen_Attack     => Queen_Attack,
               Is_Capture       => Is_Cap,
               Rep_Count  => Search_Integration.Repetition_Count_After
                               (Is_White_To_Move, F, T, Promo_Of (F, T)),
               Guard_Unsafe     => Guard_Removal_Unsafe (F, T),
               Deflected_Unsafe => Deflected_Defender_Unsafe (F, T),
               Deep_Safe        => Search_Integration.Is_Deep_Material_Safe_60
                                     (Is_White_To_Move, F, T));
            Cost_Computed (F, T) := True;
            return Cost_Cache (F, T);
         exception
            when others =>
               Move_Validation.En_Passant_Sq := Saved_Ep;
               Move_Validation.White_Castling_K := Saved_WK;
               Move_Validation.White_Castling_Q := Saved_WQ;
               Move_Validation.Black_Castling_K := Saved_BK;
               Move_Validation.Black_Castling_Q := Saved_BQ;
               Pvalidade.Tabuleiro := Saved_Board;
               raise;
         end;
      end Cost_Of;

      --  Guard-Removal (deflection / removal-of-the-guard) detection.
      --
      --  Static SEE judges a move safe when the piece it leaves behind is
      --  defended on the post-move board.  It is blind, however, to the case
      --  where that defender is the very piece we just moved to T and it can
      --  be captured off (a sound, even trade), after which the formerly
      --  guarded piece hangs.  This is exactly the 16.Nxd6 Bxd6 17.Qxd6 Rxc4
      --  piece-loss in the analysed game: Nd6 statically defends the c4
      --  bishop, so SEE sees c4 as safe, but ...Bxd6 removes the guard.
      --
      --  This models the two-move refutation on a scratch board:
      --    (1) opponent captures our piece on T  (must be sound for them),
      --    (2) we recapture on T with our cheapest attacker,
      --    (3) opponent now wins a piece elsewhere by plain SEE (>= 300 cp).
      --  Returns True when such a losing deflection exists.
      function Guard_Removal_Unsafe (F, T : Integer) return Boolean is
         use Search_Integration;
         Opp_Sign  : constant Integer := (if Is_White_To_Move then -1 else 1);
         Us_Sign   : constant Integer := (if Is_White_To_Move then 1 else -1);
         Opp       : constant Boolean := not Is_White_To_Move;
         Local_Save : array (1 .. 64) of Integer;
         Moved     : Integer;
         Base_Hang : Integer;
         Result    : Boolean := False;

         --  Cheapest own-or-enemy piece (by Side_Sign) that can capture on Tgt.
         function Cheapest_Attacker (Side_Sign, Tgt : Integer) return Integer is
            Best_Sq  : Integer := 0;
            Best_Val : Integer := Integer'Last;
         begin
            for Sq in 1 .. 64 loop
               if Pvalidade.Tabuleiro (Sq) * Side_Sign > 0
                 and then Pvalidade.Validade (Sq, Tgt)
               then
                  declare
                     V : constant Integer :=
                       Raw_Piece_Value_Cp (abs Pvalidade.Tabuleiro (Sq));
                  begin
                     if V < Best_Val then
                        Best_Val := V;
                        Best_Sq  := Sq;
                     end if;
                  end;
               end if;
            end loop;
            return Best_Sq;
         end Cheapest_Attacker;
      begin
         if F not in 1 .. 64 or else T not in 1 .. 64 then
            return False;
         end if;
         Moved := Pvalidade.Tabuleiro (F);
         --  Only a minor/major piece can be the kind of guard whose loss
         --  hangs another piece; skip pawns and the king.
         if abs Moved < 3 or else abs Moved = 999 then
            return False;
         end if;

         for Sq in 1 .. 64 loop
            Local_Save (Sq) := Pvalidade.Tabuleiro (Sq);
         end loop;

         --  Apply our move (plain relocation; promotion/EP are not relevant
         --  to a >= 3 valued guard landing on T).
         Pvalidade.Tabuleiro (T) := Moved;
         Pvalidade.Tabuleiro (F) := 0;

         Base_Hang := Max_Opponent_See (Is_White_To_Move, Except_Sq => T);
         if Base_Hang < 0 then
            Base_Hang := 0;
         end if;

         declare
            O_Sq : constant Integer := Cheapest_Attacker (Opp_Sign, T);
         begin
            --  The guard on T must be attacked, and trading it must be sound
            --  for the opponent (they do not simply lose material by it).
            if O_Sq /= 0 and then See_Gain (Opp, O_Sq, T) >= -50 then
               declare
                  O_Piece : constant Integer := Pvalidade.Tabuleiro (O_Sq);
               begin
                  --  (1) opponent captures our guard on T
                  Pvalidade.Tabuleiro (O_Sq) := 0;
                  Pvalidade.Tabuleiro (T)    := O_Piece;
                  declare
                     R_Sq : constant Integer := Cheapest_Attacker (Us_Sign, T);
                  begin
                     if R_Sq /= 0 then
                        --  (2) we recapture on T
                        Pvalidade.Tabuleiro (T)    := Pvalidade.Tabuleiro (R_Sq);
                        Pvalidade.Tabuleiro (R_Sq) := 0;
                        --  (3) opponent's best plain SEE elsewhere
                        declare
                           Phantom : constant Integer :=
                             Max_Opponent_See (Is_White_To_Move, Except_Sq => T);
                        begin
                           if Phantom >= 300 and then Phantom > Base_Hang then
                              Result := True;
                           end if;
                        end;
                     end if;
                  end;
               end;
            end if;
         end;

         for Sq in 1 .. 64 loop
            Pvalidade.Tabuleiro (Sq) := Local_Save (Sq);
         end loop;
         return Result;
      exception
         when others =>
            for Sq in 1 .. 64 loop
               Pvalidade.Tabuleiro (Sq) := Local_Save (Sq);
            end loop;
            return False;
      end Guard_Removal_Unsafe;

      --  Deflected-Defender (removal-of-the-guard by abandonment) detection.
      --
      --  The companion above (Guard_Removal_Unsafe) models a guard that moves
      --  ONTO T, is traded off there, and leaves something hanging.  This one
      --  models the mirror case that lost the analysed game at 21.Rd1-a1: our
      --  move relocates a piece that was DEFENDING one of our own attacked
      --  pieces P, abandoning it.  After the move P still looks safe to static
      --  SEE (it keeps one defender), but that remaining defender can itself be
      --  captured off (a sound trade for the opponent), after which P hangs.
      --
      --    before: Bd2 defended twice (Rd1 + Nf3), attacked once (Rd8) -> safe
      --    21.Rd1-a1 abandons the rook-defender -> Bd2 defended only by Nf3
      --    21...Bxf3 22.gxf3 removes the last defender -> 22...Rxd2 wins it.
      --
      --  Scratch-board model, only for a relocation that was defending P:
      --    (0) P (>= minor) is ours, opponent-attacked, and SAFE before we move
      --        (so the veto is caused by THIS move, not a pre-existing loss);
      --    (1) apply our move F->T (P loses the F defender);
      --    (2) opponent captures a remaining defender D of P (sound for them),
      --    (3) we recapture on D with our cheapest attacker,
      --    (4) opponent now wins P by plain SEE (>= 300 cp).
      --  Returns True when such a deflection exists.
      function Deflected_Defender_Unsafe (F, T : Integer) return Boolean is
         use Search_Integration;
         Opp_Sign  : constant Integer := (if Is_White_To_Move then -1 else 1);
         Us_Sign   : constant Integer := (if Is_White_To_Move then 1 else -1);
         Opp       : constant Boolean := not Is_White_To_Move;
         Local_Save : array (1 .. 64) of Integer;
         Moved     : Integer;
         Result    : Boolean := False;

         function Cheapest_Attacker (Side_Sign, Tgt : Integer) return Integer is
            Best_Sq  : Integer := 0;
            Best_Val : Integer := Integer'Last;
         begin
            for Sq in 1 .. 64 loop
               if Pvalidade.Tabuleiro (Sq) * Side_Sign > 0
                 and then Pvalidade.Validade (Sq, Tgt)
               then
                  declare
                     V : constant Integer :=
                       Raw_Piece_Value_Cp (abs Pvalidade.Tabuleiro (Sq));
                  begin
                     if V < Best_Val then
                        Best_Val := V;
                        Best_Sq  := Sq;
                     end if;
                  end;
               end if;
            end loop;
            return Best_Sq;
         end Cheapest_Attacker;

         --  Opponent's best plain SEE capture of the piece on Pg, if any.
         function Opp_Win_On (Pg : Integer) return Integer is
            A : constant Integer := Cheapest_Attacker (Opp_Sign, Pg);
         begin
            if A = 0 then
               return 0;
            end if;
            return See_Gain (Opp, A, Pg);
         end Opp_Win_On;

      begin
         if F not in 1 .. 64 or else T not in 1 .. 64 then
            return False;
         end if;
         Moved := Pvalidade.Tabuleiro (F);
         --  Only a minor/major (or the king) can abandon a guard duty; pawns'
         --  defensive reach is too incidental to model here.
         if abs Moved < 3 then
            return False;
         end if;

         for Sq in 1 .. 64 loop
            Local_Save (Sq) := Pvalidade.Tabuleiro (Sq);
         end loop;

         --  Scan our own pieces P that the moved piece was defending.
         Outer :
         for Pg in 1 .. 64 loop
            exit Outer when Result;
            declare
               Pv : constant Integer := Local_Save (Pg);
            begin
               if Pg /= F
                 and then Pv * Us_Sign > 0
                 and then abs Pv >= 3 and then abs Pv /= 999
                 and then Pvalidade.Validade (F, Pg)            --  F defended Pg
                 and then Cheapest_Attacker (Opp_Sign, Pg) /= 0 --  Pg attacked
                 and then Opp_Win_On (Pg) < 300                 --  (0) safe now
               then
                  --  (1) apply our relocation; P loses the F defender.
                  Pvalidade.Tabuleiro (T) := Moved;
                  Pvalidade.Tabuleiro (F) := 0;

                  --  Only proceed if the move did not itself make P hang; that
                  --  plain case is already handled by the hang accounting.
                  if Opp_Win_On (Pg) < 300 then
                     --  (2) look for a remaining defender D of P the opponent
                     --  can capture soundly, then (3) recapture, (4) win P.
                     Inner :
                     for Dg in 1 .. 64 loop
                        exit Inner when Result;
                        declare
                           Dv : constant Integer := Pvalidade.Tabuleiro (Dg);
                        begin
                           if Dg /= Pg and then Dg /= T
                             and then Dv * Us_Sign > 0
                             and then Pvalidade.Validade (Dg, Pg)  --  D defends P
                           then
                              declare
                                 O_Sq : constant Integer :=
                                   Cheapest_Attacker (Opp_Sign, Dg);
                              begin
                                 if O_Sq /= 0
                                   and then See_Gain (Opp, O_Sq, Dg) >= -50
                                 then
                                    declare
                                       O_Piece : constant Integer :=
                                         Pvalidade.Tabuleiro (O_Sq);
                                       D_Save  : constant Integer :=
                                         Pvalidade.Tabuleiro (Dg);
                                    begin
                                       --  (2) opponent captures defender D
                                       Pvalidade.Tabuleiro (O_Sq) := 0;
                                       Pvalidade.Tabuleiro (Dg)   := O_Piece;
                                       declare
                                          R_Sq : constant Integer :=
                                            Cheapest_Attacker (Us_Sign, Dg);
                                       begin
                                          if R_Sq /= 0 then
                                             declare
                                                R_Save : constant Integer :=
                                                  Pvalidade.Tabuleiro (R_Sq);
                                             begin
                                                --  (3) we recapture on D
                                                Pvalidade.Tabuleiro (Dg) :=
                                                  R_Save;
                                                Pvalidade.Tabuleiro (R_Sq) := 0;
                                                --  (4) opponent wins P?
                                                if Opp_Win_On (Pg) >= 300 then
                                                   Result := True;
                                                end if;
                                                --  restore recapture
                                                Pvalidade.Tabuleiro (R_Sq) :=
                                                  R_Save;
                                             end;
                                          end if;
                                       end;
                                       --  restore the defender capture
                                       Pvalidade.Tabuleiro (Dg)   := D_Save;
                                       Pvalidade.Tabuleiro (O_Sq) := O_Piece;
                                    end;
                                 end if;
                              end;
                           end if;
                        end;
                     end loop Inner;
                  end if;

                  --  restore our relocation before scanning the next P
                  Pvalidade.Tabuleiro (F) := Moved;
                  Pvalidade.Tabuleiro (T) := Local_Save (T);
               end if;
            end;
         end loop Outer;

         for Sq in 1 .. 64 loop
            Pvalidade.Tabuleiro (Sq) := Local_Save (Sq);
         end loop;
         return Result;
      exception
         when others =>
            for Sq in 1 .. 64 loop
               Pvalidade.Tabuleiro (Sq) := Local_Save (Sq);
            end loop;
            return False;
      end Deflected_Defender_Unsafe;

      function Is_Castling_Into_Open_File
        (White_To_Move : Boolean; F, T : Integer) return Boolean is
      begin
         return Search_Integration.Is_Castling_Into_Open_File (White_To_Move, F, T);
      end Is_Castling_Into_Open_File;

      function Move_Is_Safe (F, T : Integer) return Boolean is
         Danger : Boolean;
      begin
         if F not in 1 .. 64 or else T not in 1 .. 64 then
            return False;
         end if;
         if Is_Castling_Into_Open_File (Is_White_To_Move, F, T) then
            return False;
         end if;
         declare
            C : constant Move_Cost := Cost_Of (F, T);
            --  Evaluate is only consumed by the repetition branch; compute
            --  it lazily so ordinary moves never pay the full-board eval.
            Root_Eval : Integer;
         begin
            if C.Self_Hang then
               return False;
            end if;

            --  Anti-Threefold Repetition:
            --  If the engine has a solid advantage (Root_Eval >= 50 cp),
            --  voluntarily repeating for the 3rd time (C.Rep_Count >= 2) throws away the win into a draw.
            if C.Rep_Count >= 2 then
               Root_Eval := (if Is_White_To_Move then Search_Integration.Evaluate
                             else -Search_Integration.Evaluate);
               if Root_Eval >= 50 then
                  return False;
               end if;
            end if;

            if C.Is_Capture then
               --  S-G5-1 (O1): evaluate cheap material checks before forced mate
               Danger := (C.Gain_Cp < -50
                          or else (C.Gain_Cp < 0
                                   and then not (abs Pvalidade.Tabuleiro (F) in 3 .. 4
                                                 and then abs Pvalidade.Tabuleiro (T) in 3 .. 4)))
                 or else C.Hang_Cp > C.Gain_Cp + 50     --  net material loss (minor piece tolerance)
                 or else (C.Threat and then C.Gain_Cp < 300)
                 or else C.Mate
                 or else (C.Fork and then C.Gain_Cp < 500);
            else
               --  S-G6-2 (C1 part 1): quiet branch rewrite
               --  Unsafe only on piece hang increase, mate, checking fork, or trapped threat.
               --  Pawn captures (100 cp) do not veto quiet moves; hanging minor/major pieces (>= 200 cp) do.
               Danger := (C.Hang_Cp >= 200
                          and then not (C.Queen_Attack and then C.Hang_Cp <= 200)
                          and then (Root_Pre_Hang_Cp < 200 or else C.Hang_Cp >= Root_Pre_Hang_Cp))
                 or else C.Mate
                 or else C.Fork
                 or else C.Threat
                 or else C.Checking_Capture;
            end if;
            return not Danger
              and then not C.Guard_Unsafe
              and then not C.Deflected_Unsafe
              and then C.Deep_Safe;
         end;
      end Move_Is_Safe;

      --  S-G6-4: Walks_Into_Loss (A§2.3)
      function Walks_Into_Loss (F, T : Integer) return Boolean is
         C : constant Move_Cost := Cost_Of (F, T);
      begin
         return C.Mate
           or else (C.Fork and then (not C.Is_Capture or else C.Gain_Cp < 500))
           or else (not C.Is_Capture
                    and then C.Hang_Cp >= 200
                    and then (Root_Pre_Hang_Cp < 200 or else C.Hang_Cp >= Root_Pre_Hang_Cp))
           or else (C.Is_Capture
                    and then C.Hang_Cp > C.Gain_Cp + 50
                    and then (Root_Pre_Hang_Cp < 200 or else C.Hang_Cp >= Root_Pre_Hang_Cp))
           or else (C.Threat
                    and then not (C.Is_Capture and then C.Gain_Cp >= 300));
      end Walks_Into_Loss;

      function Compute_Net_Material (F, T : Integer) return Integer is
      begin
         return Cost_Of (F, T).Net_Cp;
      end Compute_Net_Material;

      function Enemy_Queen_Attacks_King_Bishop_Pawn return Boolean is
         Target : constant Integer :=
           (if Is_White_To_Move then Move_Validation.Square_Of (2, 6)
                                else Move_Validation.Square_Of (7, 6));
         Enemy_Queen : constant Integer := (if Is_White_To_Move then -20 else 20);
      begin
         for Sq in 1 .. 64 loop
            if Pvalidade.Tabuleiro (Sq) = Enemy_Queen
              and then Pvalidade.Validade (Sq, Target)
            then
               return True;
            end if;
         end loop;
         return False;
      end Enemy_Queen_Attacks_King_Bishop_Pawn;


      procedure Veto_Legacy (F, T : Integer) is
         VF : Integer := F;
         VT : Integer := T;
      begin
         --  Jogada_Vetada lives in the search's internal frame, which
         --  is mirrored when the engine plays Black.
         if not Is_White_To_Move then
            VF := Move_Validation.Mirror_Square (VF);
            VT := Move_Validation.Mirror_Square (VT);
         end if;
         pprechess2.Jogada_Vetada (VF, VT) := True;
      end Veto_Legacy;

      procedure Choose_Root_Correction
        (From_Sq, To_Sq : Integer;
         Stage          : String;
         Sets_Trap      : Boolean := False)
      is
         Legacy_Is_Incumbent : constant Boolean :=
           not Chose_Winning_Capture
             and then not Chose_Root_Correction
             and then Best_From = Legacy_From
             and then Best_To = Legacy_To;
         Legacy_Valid : constant Boolean :=
           Legacy_Is_Incumbent
             and then Legacy_From /= Legacy_To
             and then Legacy_From in 1 .. 64
             and then Legacy_To in 1 .. 64;
         Leg_Cost  : constant Move_Cost :=
           (if Legacy_Valid then Cost_Of (Legacy_From, Legacy_To)
            else Cost_Of (0, 0));
         Cand_Cost : constant Move_Cost := Cost_Of (From_Sq, To_Sq);
      begin
         if Legacy_Valid
           and then Search_Integration.Should_Keep_Legacy_Over_Correction
                      (Stage            => Stage,
                       Legacy_Valid     => Legacy_Valid,
                       Legacy_Hang_Cp   => Leg_Cost.Hang_Cp,
                       Root_Pre_Hang_Cp => Root_Pre_Hang_Cp,
                       Legacy_Safe      => Move_Is_Safe (Legacy_From, Legacy_To),
                       Legacy_Mate      => Leg_Cost.Mate,
                       Legacy_Fork      => Leg_Cost.Fork,
                       Legacy_Threat    => Leg_Cost.Threat,
                       Legacy_Gain_Cp   => Leg_Cost.Gain_Cp,
                       Cand_Is_Capture  => Cand_Cost.Is_Capture,
                       Cand_Gain_Cp     => Cand_Cost.Gain_Cp)
         then
            if Search_Integration.Trace_Root_Decisions then
               Put_Line ("info string [root-trace] Guard kept Legacy " &
                         Move_To_String (Legacy_From, Legacy_To, 0) &
                         " over [" & Stage & "]: " &
                         Move_To_String (From_Sq, To_Sq, 0));
            end if;
            return;
         end if;
         Best_From := From_Sq;
         Best_To   := To_Sq;
         Chose_Root_Correction := True;
         if Sets_Trap then
            Chose_Trap := True;
         end if;
         if Search_Integration.Trace_Root_Decisions then
            Put_Line ("info string [root-trace] Choose_Root_Correction [" & Stage & "]: " &
                      Move_To_String (From_Sq, To_Sq, 0));
         end if;
      end Choose_Root_Correction;

      function Try_Special_Move_Only return Boolean is
      begin
         Search_Integration.Best_Castle (Is_White_To_Move, Castle_Found, Castle_King);
         if Castle_Found then
            declare
               King_Sq : constant Integer := Move_Validation.Find_King (Is_White_To_Move);
               Castle_To : constant Integer :=
                 (if Castle_King then King_Sq + 2 else King_Sq - 2);
            begin
               if King_Sq /= 0 and then Move_Is_Safe (King_Sq, Castle_To) then
                  Best_From := King_Sq;
                  Best_To   := Castle_To;
                  return True;
               end if;
            end;
         end if;

         Ep_From := Search_Integration.En_Passant_Candidate (Is_White_To_Move);
         if Ep_From /= 0
           and then Move_Is_Safe (Ep_From, Move_Validation.En_Passant_Sq)
         then
            Best_From := Ep_From;
            Best_To   := Move_Validation.En_Passant_Sq;
            return True;
         end if;
         return False;
      end Try_Special_Move_Only;

   begin
      Last_Verify_Used := False;
      Best_Promo := 0;
      --  0.9.9.17.16: reserve half of a bounded move budget for Stage 7 when
      --  the measured legacy cascade reliably completes inside its slice.
      --  Very short bullet budgets (< 400 ms) keep the old behavior: aborting
      --  the cascade before it has chosen a move would yield only a fallback.
      if Verify_Depth_Opt > 0
        and then Time_Management.Allocated_Ms >= 400
        and then Time_Management.Allocated_Ms /= Integer'Last
      then
         Time_Management.Reserve_Time_Slice (Time_Management.Allocated_Ms / 2);
      end if;
      pprechess2.Jogada_Vetada := [others => [others => False]];
      Search_Integration.Snapshot_Legal_Root_Candidates (Is_White_To_Move, Root_Candidates);
      Root_Pre_Hang_Cp := Search_Integration.Max_Opponent_See (Is_White_To_Move);
      if Root_Pre_Hang_Cp < 100 then
         Root_Pre_Hang_Cp := 0;
      end if;
      Root_Pre_Double_Attack :=
        Search_Integration.Has_Opponent_Double_Attack (Is_White_To_Move, Target_Sq => 0);

      --  0.9.9.17.20 warm-up: fill the per-move cost cache once, up front.
      --  Every later stage (safety gates, Net Gate, Stage 6.5, trace) then
      --  reads memoized verdicts instead of re-running the veto sweeps.
      for I in 1 .. Root_Candidates.Count loop
         declare
            C : Search_Integration.Root_Candidate renames
                  Root_Candidates.Candidates (I);
            Warmer : constant Move_Cost := Cost_Of (C.From_Sq, C.To_Sq);
            pragma Unreferenced (Warmer);
         begin
            null;
         end;
      end loop;

      --  Stage 0 (E5/S1): play an immediate mate if one exists.
      --  Root_Candidates is the legal snapshot taken at Compute_Best_Move entry.
      --  Cost: one checkmate probe per legal root move. Nothing beats mate in one.
      for I in 1 .. Root_Candidates.Count loop
         declare
            C : Search_Integration.Root_Candidate renames
                  Root_Candidates.Candidates (I);
            Promo_Code : constant Integer :=
              (if C.Promo /= 0 then C.Promo
               elsif Promo_Of (C.From_Sq, C.To_Sq) /= 0 then 20
               else 0);
         begin
            if Search_Integration.Move_Delivers_Checkmate
                 (White_To_Move => Is_White_To_Move,
                  From_Sq       => C.From_Sq,
                  To_Sq         => C.To_Sq,
                  Promo         => Promo_Code)
              and then In_Pending_Searchmoves (C.From_Sq, C.To_Sq, C.Promo)
            then
               Best_From  := C.From_Sq;
               Best_To    := C.To_Sq;
               Best_Promo := (if C.Promo /= 0 then C.Promo
                              else Promo_Of (Best_From, Best_To));
               return;   --  immediate checkmate found; legacy cascade bypassed
            end if;
         end;
      end loop;

      --  Stage 1: a legacy move that does not walk into a short mate.
      for Attempt in 0 .. Max_Vetoes loop
         if Attempt = 0 then
            Run_Legacy;
         else
            Run_Legacy_Cascade_Only;
         end if;
         if Legacy_From = Legacy_To then
            --  Sentinel. On the first attempt this is genuine
            --  checkmate/stalemate; after vetoes it means every
            --  cascade choice mates -- the engine is lost either way,
            --  so fall back to its original preference.
            if First_From /= 0 then
               Legacy_From := First_From;
               Legacy_To   := First_To;
               Legacy_Was_Capture :=
                 Pvalidade.Tabuleiro (Legacy_To) /= 0;
            else
               No_Move := True;
            end if;
            exit;
         end if;
         if Attempt = 0 then
            First_From := Legacy_From;
            First_To   := Legacy_To;
         end if;
         exit when Move_Is_Safe (Legacy_From, Legacy_To);
         exit when Time_Management.Search_Aborted or else Attempt = Max_Vetoes;
         Veto_Legacy (Legacy_From, Legacy_To);
      end loop;

      pprechess2.Jogada_Vetada := [others => [others => False]];

      if No_Move then
         if Try_Special_Move_Only then
            Best_Promo := Promo_Of (Best_From, Best_To);
         elsif Root_Candidates.Count > 0 then
            --  U1: the cascade failing does not mean the position is
            --  terminal. Play the first safe legal move instead of 0000.
            Best_From := 0; Best_To := 0;
            for I in 1 .. Root_Candidates.Count loop
               declare
                  C : Search_Integration.Root_Candidate renames
                        Root_Candidates.Candidates (I);
               begin
                  if Best_From = 0
                    and then Move_Is_Safe (C.From_Sq, C.To_Sq)
                  then
                     Best_From := C.From_Sq; Best_To := C.To_Sq;
                  end if;
               end;
            end loop;
            if Best_From = 0 then   -- nothing "safe": first legal anyway
               Best_From := Root_Candidates.Candidates (1).From_Sq;
               Best_To   := Root_Candidates.Candidates (1).To_Sq;
            end if;
            Best_Promo := Promo_Of (Best_From, Best_To);
            Put_Line ("info string U1: cascade yielded no move; rescued by legal candidate fallback");
         else
            Best_From := 0; Best_To := 0; Best_Promo := 0;   -- truly terminal
         end if;
         return;
      end if;

      Best_From  := Legacy_From;
      Best_To    := Legacy_To;
      --  Tracks whether Stage 2 selected a SEE-positive capture, so later
      --  stages do not override it after Stage 2b/2c/2d relocate the move.
      Chose_Winning_Capture := False;
      Chose_Root_Correction := False;

      --  Stage 0: check evasion arbitration when the engine is in check at the root.
      if Move_Validation.Is_In_Check (Is_White_To_Move) then
         Search_Integration.Best_Check_Evasion
           (Is_White_To_Move, Evasion_Found, Evasion_From, Evasion_To);
         if Evasion_Found and then Move_Is_Safe (Evasion_From, Evasion_To) then
            Choose_Root_Correction (Evasion_From, Evasion_To, "Best_Check_Evasion");
            Best_Promo := Promo_Of (Best_From, Best_To);
         end if;
      end if;

      if not Move_Validation.Is_In_Check (Is_White_To_Move) then
      --  Stage 1a: root corrections for validated tactical/opening classes.
      --  B-C5: early returns removed; fall through so that higher-value winning
      --  captures (Stage 2) or en-prise resolves (Stage 3) can still run.
      Search_Integration.Best_Queen_Fork_Counter_Attack
        (Is_White_To_Move, QFork_Found, QFork_From, QFork_To);
      if QFork_Found
        and then not Move_Validation.Is_Square_Attacked
                       (QFork_To, By_White => not Is_White_To_Move)
      then
         Choose_Root_Correction (QFork_From, QFork_To, "Best_Queen_Fork_Counter_Attack", Sets_Trap => True);
         Best_Promo := Promo_Of (Best_From, Best_To);
      else
      Search_Integration.Best_Advanced_Central_Pawn_Recapture
        (Is_White_To_Move, Recap_Found, Recap_From, Recap_To);
      if Recap_Found and then Move_Is_Safe (Recap_From, Recap_To) then
         Choose_Root_Correction (Recap_From, Recap_To, "Best_Advanced_Central_Pawn_Recapture");
         Best_Promo := Promo_Of (Best_From, Best_To);
      else
         Search_Integration.Best_Trapped_Piece_Rescue
           (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
         if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
            --  Counter-tempo guard (move 21): a quiet trap rescue is not urgent
            --  when we can attack the enemy queen with a safe, non-losing tempo
            --  move first (21.Re1! -285 vs 21.Qa1? -535, since 21.Re1 b5?? 22.Rxe5).
            if Pvalidade.Tabuleiro (Trap_To) = 0 then
               declare
                  Tempo_From  : Integer := 0;
                  Tempo_To    : Integer := 0;
                  Tempo_Score : Integer := Integer'First;
               begin
                  for F in 1 .. 64 loop
                     if Pvalidade.Tabuleiro (F) * (if Is_White_To_Move then 1 else -1) > 0 then
                        for T in 1 .. 64 loop
                           if Search_Integration.Attacks_Enemy_Queen (Is_White_To_Move, F, T)
                             and then Move_Is_Safe (F, T)
                             and then Search_Integration.See_Gain (Is_White_To_Move, F, T) >= 0
                           then
                              declare
                                 P : constant Integer := abs Pvalidade.Tabuleiro (F);
                                 S : Integer := (if P = 7 then 300 elsif P in 3 | 4 then 200 else 50);
                              begin
                                 if Pvalidade.Tabuleiro (T) /= 0 then
                                    S := S + 100;
                                 end if;
                                 if S > Tempo_Score then
                                    Tempo_Score := S;
                                    Tempo_From  := F;
                                    Tempo_To    := T;
                                 end if;
                              end;
                           end if;
                        end loop;
                     end if;
                  end loop;

                  if Tempo_From /= 0 then
                     Trap_From := Tempo_From;
                     Trap_To   := Tempo_To;
                  end if;
               end;
            end if;
            Choose_Root_Correction (Trap_From, Trap_To, "Best_Trapped_Piece_Rescue", Sets_Trap => True);
            Best_Promo := Promo_Of (Best_From, Best_To);
         else
            Search_Integration.Best_Opening_Trap_Response
              (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
            if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
               Choose_Root_Correction (Trap_From, Trap_To, "Best_Opening_Trap_Response", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
               Search_Integration.Best_Rook_Attack_On_Infiltrated_Queen
                 (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
               if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
                  Choose_Root_Correction (Trap_From, Trap_To, "Best_Rook_Attack_On_Infiltrated_Queen", Sets_Trap => True);
                  Best_Promo := Promo_Of (Best_From, Best_To);
               else
                  Search_Integration.Best_Ensnare_Overextended_Queen
                    (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
                  if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
                     Choose_Root_Correction (Trap_From, Trap_To, "Best_Ensnare_Overextended_Queen", Sets_Trap => True);
                     Best_Promo := Promo_Of (Best_From, Best_To);
                  else
                     Search_Integration.Best_King_Step_To_Trap_Queen
                       (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
                     if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
                        Choose_Root_Correction (Trap_From, Trap_To, "Best_King_Step_To_Trap_Queen", Sets_Trap => True);
                        Best_Promo := Promo_Of (Best_From, Best_To);
                     else
                        Search_Integration.Best_Trapped_Infiltrated_Queen_Strike
                          (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
                        if Trap_Found then
                           Choose_Root_Correction (Trap_From, Trap_To, "Best_Trapped_Infiltrated_Queen_Strike", Sets_Trap => True);
                           Best_Promo := Promo_Of (Best_From, Best_To);
                        else
                           Search_Integration.Best_Rook_Open_File_Facing_Queen
                          (Is_White_To_Move, Rook_Found, Rook_From, Rook_To);
                        if Rook_Found and then Move_Is_Safe (Rook_From, Rook_To) then
                           Choose_Root_Correction (Rook_From, Rook_To, "Best_Rook_Open_File_Facing_Queen");
                           Best_Promo := Promo_Of (Best_From, Best_To);
                        else
                           Search_Integration.Best_Central_King_Safety_Tuck
                             (Is_White_To_Move, Tuck_Found, Tuck_From, Tuck_To);
                           if Tuck_Found and then Move_Is_Safe (Tuck_From, Tuck_To) then
                              Choose_Root_Correction (Tuck_From, Tuck_To, "Best_Central_King_Safety_Tuck");
                              Best_Promo := Promo_Of (Best_From, Best_To);
                           else
                              Search_Integration.Best_Passed_Pawn_Blockade_King_Step
                                (Is_White_To_Move, Blockade_King_Found, Blockade_King_From, Blockade_King_To);
                              if Blockade_King_Found and then Move_Is_Safe (Blockade_King_From, Blockade_King_To) then
                                 Choose_Root_Correction (Blockade_King_From, Blockade_King_To, "Best_Passed_Pawn_Blockade_King_Step", Sets_Trap => True);
                                 Best_Promo := Promo_Of (Best_From, Best_To);
                              else
                              Search_Integration.Best_Constricted_King_Escape
                                (Is_White_To_Move, Esc_Found, Esc_From, Esc_To);
                              if Esc_Found and then Move_Is_Safe (Esc_From, Esc_To) then
                                 Choose_Root_Correction (Esc_From, Esc_To, "Best_Constricted_King_Escape", Sets_Trap => True);
                                 Best_Promo := Promo_Of (Best_From, Best_To);
                              else
                                 Search_Integration.Best_King_Unpin_Step
                                   (Is_White_To_Move, Unpin_K_Found, Unpin_K_From, Unpin_K_To);
                                 if Unpin_K_Found and then Move_Is_Safe (Unpin_K_From, Unpin_K_To) then
                                    Choose_Root_Correction (Unpin_K_From, Unpin_K_To, "Best_King_Unpin_Step", Sets_Trap => True);
                                    Best_Promo := Promo_Of (Best_From, Best_To);
                                 else
                                 Search_Integration.Best_Infiltrating_Rook_Attacker
                                   (Is_White_To_Move, Infil_Found, Infil_From, Infil_To);
                                 if Infil_Found and then Move_Is_Safe (Infil_From, Infil_To) then
                                    Choose_Root_Correction (Infil_From, Infil_To, "Best_Infiltrating_Rook_Attacker", Sets_Trap => True);
                                    Best_Promo := Promo_Of (Best_From, Best_To);
                                 else
                                    Search_Integration.Best_Fried_Liver_Central_Break
                                      (Is_White_To_Move, FL_Found, FL_From, FL_To);
                                    if FL_Found and then Move_Is_Safe (FL_From, FL_To) then
                                       Choose_Root_Correction (FL_From, FL_To, "Best_Fried_Liver_Central_Break", Sets_Trap => True);
                                       Best_Promo := Promo_Of (Best_From, Best_To);
                                    else
                                       Search_Integration.Best_Flank_Queen_Infiltration
                                         (Is_White_To_Move, Flank_Q_Infil_Found, Flank_Q_Infil_From, Flank_Q_Infil_To);
                                       if Flank_Q_Infil_Found and then Move_Is_Safe (Flank_Q_Infil_From, Flank_Q_Infil_To) then
                                          Choose_Root_Correction (Flank_Q_Infil_From, Flank_Q_Infil_To, "Best_Flank_Queen_Infiltration", Sets_Trap => True);
                                          Best_Promo := Promo_Of (Best_From, Best_To);
                                       else
            Search_Integration.Best_Undefended_Major_Attack
              (Is_White_To_Move, Undefended_Maj_Found, Undefended_Maj_From, Undefended_Maj_To);
            if Undefended_Maj_Found and then Move_Is_Safe (Undefended_Maj_From, Undefended_Maj_To) then
               Choose_Root_Correction (Undefended_Maj_From, Undefended_Maj_To, "Best_Undefended_Major_Attack", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_Infiltration_Guard
              (Is_White_To_Move, Infil_Guard_Found, Infil_Guard_From, Infil_Guard_To);
            if Infil_Guard_Found and then Move_Is_Safe (Infil_Guard_From, Infil_Guard_To) then
               Choose_Root_Correction (Infil_Guard_From, Infil_Guard_To, "Best_Infiltration_Guard", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_Passed_Pawn_Diagonal_Control
              (Is_White_To_Move, Diag_Ctrl_Found, Diag_Ctrl_From, Diag_Ctrl_To);
            if Diag_Ctrl_Found and then Move_Is_Safe (Diag_Ctrl_From, Diag_Ctrl_To) then
               Choose_Root_Correction (Diag_Ctrl_From, Diag_Ctrl_To, "Best_Passed_Pawn_Diagonal_Control", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_Attacked_Queen_Zwischenzug_Push
              (Is_White_To_Move, Zwischen_Found, Zwischen_From, Zwischen_To);
            if Zwischen_Found and then Move_Is_Safe (Zwischen_From, Zwischen_To) then
               Choose_Root_Correction (Zwischen_From, Zwischen_To, "Best_Attacked_Queen_Zwischenzug_Push", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_Queen_Skewer_Escape
              (Is_White_To_Move, Skewer_Found, Skewer_From, Skewer_To);
            if Skewer_Found and then Move_Is_Safe (Skewer_From, Skewer_To) then
               Choose_Root_Correction (Skewer_From, Skewer_To, "Best_Queen_Skewer_Escape", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_King_Pin_Shield
              (Is_White_To_Move, Pin_Shield_Found, Pin_Shield_From, Pin_Shield_To);
            if Pin_Shield_Found and then Move_Is_Safe (Pin_Shield_From, Pin_Shield_To) then
               Choose_Root_Correction (Pin_Shield_From, Pin_Shield_To, "Best_King_Pin_Shield", Sets_Trap => True);
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
            Search_Integration.Best_King_Indian_Central_Pawn_Strike
              (Is_White_To_Move, KID_Found, KID_From, KID_To);
            if KID_Found and then Move_Is_Safe (KID_From, KID_To) then
               Choose_Root_Correction (KID_From, KID_To, "Best_King_Indian_Central_Pawn_Strike");
               Best_Promo := Promo_Of (Best_From, Best_To);
            else
               Search_Integration.Best_Benoni_Queenside_Break
                 (Is_White_To_Move, Benoni_Found, Benoni_From, Benoni_To);
               if Benoni_Found and then Move_Is_Safe (Benoni_From, Benoni_To) then
                  Choose_Root_Correction (Benoni_From, Benoni_To, "Best_Benoni_Queenside_Break");
                  Best_Promo := Promo_Of (Best_From, Best_To);
               else
                  Search_Integration.Best_Outpost_Knight_Major_Attack
                    (Is_White_To_Move, Outpost_Maj_Found, Outpost_Maj_From, Outpost_Maj_To);
                  if Outpost_Maj_Found and then Move_Is_Safe (Outpost_Maj_From, Outpost_Maj_To) then
                     Choose_Root_Correction (Outpost_Maj_From, Outpost_Maj_To, "Best_Outpost_Knight_Major_Attack", Sets_Trap => True);
                     Best_Promo := Promo_Of (Best_From, Best_To);
                  else
                     Search_Integration.Best_Rook_Central_Open_File_Counterplay
                       (Is_White_To_Move, Rook_Open_Found, Rook_Open_From, Rook_Open_To);
                     if Rook_Open_Found and then Move_Is_Safe (Rook_Open_From, Rook_Open_To) then
                        Choose_Root_Correction (Rook_Open_From, Rook_Open_To, "Best_Rook_Central_Open_File_Counterplay", Sets_Trap => True);
                        Best_Promo := Promo_Of (Best_From, Best_To);
                     else
                        Search_Integration.Best_Contested_File_Rook_Align
                           (Is_White_To_Move, Rook_Align_Found, Rook_Align_From, Rook_Align_To);
                         if Rook_Align_Found and then Move_Is_Safe (Rook_Align_From, Rook_Align_To) then
                            Choose_Root_Correction (Rook_Align_From, Rook_Align_To, "Best_Contested_File_Rook_Align", Sets_Trap => True);
                            Best_Promo := Promo_Of (Best_From, Best_To);
                         else
                            Search_Integration.Best_Knight_Outpost_Denial
                              (Is_White_To_Move, Outpost_Denial_Found, Outpost_Denial_From, Outpost_Denial_To);
                            if Outpost_Denial_Found and then Move_Is_Safe (Outpost_Denial_From, Outpost_Denial_To) then
                               Choose_Root_Correction (Outpost_Denial_From, Outpost_Denial_To, "Best_Knight_Outpost_Denial", Sets_Trap => True);
                               Best_Promo := Promo_Of (Best_From, Best_To);
                            else
                               Search_Integration.Best_Cramped_Central_Pawn_Break
                                 (Is_White_To_Move, Cramp_Break_Found, Cramp_Break_From, Cramp_Break_To);
                               if Cramp_Break_Found and then Move_Is_Safe (Cramp_Break_From, Cramp_Break_To) then
                                  Choose_Root_Correction (Cramp_Break_From, Cramp_Break_To, "Best_Cramped_Central_Pawn_Break", Sets_Trap => True);
                                  Best_Promo := Promo_Of (Best_From, Best_To);
                               else
                                  Search_Integration.Best_Knight_Fork_Parry_Reposition
                                    (Is_White_To_Move, Fork_Parry_Found, Fork_Parry_From, Fork_Parry_To);
                                  if Fork_Parry_Found and then Move_Is_Safe (Fork_Parry_From, Fork_Parry_To) then
                                     Choose_Root_Correction (Fork_Parry_From, Fork_Parry_To, "Best_Knight_Fork_Parry_Reposition", Sets_Trap => True);
                                     Best_Promo := Promo_Of (Best_From, Best_To);
                                  else
                                     Search_Integration.Best_Sicilian_Najdorf_Queen_Develop
                                       (Is_White_To_Move, Najdorf_Q_Found, Najdorf_Q_From, Najdorf_Q_To);
                                     if Najdorf_Q_Found and then Move_Is_Safe (Najdorf_Q_From, Najdorf_Q_To) then
                                        Choose_Root_Correction (Najdorf_Q_From, Najdorf_Q_To, "Best_Sicilian_Najdorf_Queen_Develop", Sets_Trap => True);
                                        Best_Promo := Promo_Of (Best_From, Best_To);
                                     else
                                           Search_Integration.Best_Pinning_Bishop_Kick
                                             (Is_White_To_Move, Bishop_Kick_Found, Bishop_Kick_From, Bishop_Kick_To);
                                           if Bishop_Kick_Found and then Move_Is_Safe (Bishop_Kick_From, Bishop_Kick_To) then
                                              Choose_Root_Correction (Bishop_Kick_From, Bishop_Kick_To, "Best_Pinning_Bishop_Kick", Sets_Trap => True);
                                              Best_Promo := Promo_Of (Best_From, Best_To);
                                           else
                                              Search_Integration.Best_Rook_Cramping_Pawn_Pressure
                                                (Is_White_To_Move, Rook_Cramp_Found, Rook_Cramp_From, Rook_Cramp_To);
                                              if Rook_Cramp_Found and then Move_Is_Safe (Rook_Cramp_From, Rook_Cramp_To) then
                                                 Choose_Root_Correction (Rook_Cramp_From, Rook_Cramp_To, "Best_Rook_Cramping_Pawn_Pressure", Sets_Trap => True);
                                                 Best_Promo := Promo_Of (Best_From, Best_To);
                                              else
                               Search_Integration.Best_Queenside_Flank_Pawn_Advance
                          (Is_White_To_Move, QSide_Flank_Found, QSide_Flank_From, QSide_Flank_To);
                        if QSide_Flank_Found and then Move_Is_Safe (QSide_Flank_From, QSide_Flank_To) then
                           Choose_Root_Correction (QSide_Flank_From, QSide_Flank_To, "Best_Queenside_Flank_Pawn_Advance", Sets_Trap => True);
                           Best_Promo := Promo_Of (Best_From, Best_To);
                        else
                           Search_Integration.Best_Rim_Knight_Preservation
                             (Is_White_To_Move, Rim_N_Found, Rim_N_From, Rim_N_To);
                           if Rim_N_Found and then Move_Is_Safe (Rim_N_From, Rim_N_To) then
                              Choose_Root_Correction (Rim_N_From, Rim_N_To, "Best_Rim_Knight_Preservation", Sets_Trap => True);
                              Best_Promo := Promo_Of (Best_From, Best_To);
                           else
                              Search_Integration.Best_Queen_Central_Defense
                                (Is_White_To_Move, Queen_Def_Found, Queen_Def_From, Queen_Def_To);
                              if Queen_Def_Found and then Move_Is_Safe (Queen_Def_From, Queen_Def_To) then
                                 Choose_Root_Correction (Queen_Def_From, Queen_Def_To, "Best_Queen_Central_Defense", Sets_Trap => True);
                                 Best_Promo := Promo_Of (Best_From, Best_To);
                              else
                                 Search_Integration.Best_Doubled_F_Pawn_Strike
                                   (Is_White_To_Move, DblF_Found, DblF_From, DblF_To);
                                 if DblF_Found and then Move_Is_Safe (DblF_From, DblF_To) then
                                    Choose_Root_Correction (DblF_From, DblF_To, "Best_Doubled_F_Pawn_Strike");
                                    Best_Promo := Promo_Of (Best_From, Best_To);
                                 else
                     Search_Integration.Best_Central_Pawn_Wedge_Strike
                       (Is_White_To_Move, Wedge_Found, Wedge_From, Wedge_To);
                     if Wedge_Found and then Move_Is_Safe (Wedge_From, Wedge_To) then
                        Choose_Root_Correction (Wedge_From, Wedge_To, "Best_Central_Pawn_Wedge_Strike");
                        Best_Promo := Promo_Of (Best_From, Best_To);
                     else
                        Search_Integration.Best_Central_Knight_Challenge
                        (Is_White_To_Move, Knight_Challenge_Found, Knight_Challenge_From, Knight_Challenge_To);
                      if Knight_Challenge_Found and then Move_Is_Safe (Knight_Challenge_From, Knight_Challenge_To) then
                         Choose_Root_Correction (Knight_Challenge_From, Knight_Challenge_To, "Best_Central_Knight_Challenge", Sets_Trap => True);
                         Best_Promo := Promo_Of (Best_From, Best_To);
                      else
                         Search_Integration.Best_Pawn_Tempo_Kick_Knight
                          (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
                        if Kick_Found
                          and then Root_Pre_Hang_Cp < 100
                          and then Move_Is_Safe (Kick_From, Kick_To)
                        then
                           Choose_Root_Correction (Kick_From, Kick_To, "Best_Pawn_Tempo_Kick_Knight");
                           Best_Promo := Promo_Of (Best_From, Best_To);
                        else
                           Search_Integration.Best_Defend_Knight_C_Pawn_Fork
                             (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
                           if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To) then
                              Choose_Root_Correction (Kick_From, Kick_To, "Best_Defend_Knight_C_Pawn_Fork");
                              Best_Promo := Promo_Of (Best_From, Best_To);
                           else
                              Search_Integration.Best_Defend_Central_Pawn
                                (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
                              if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To) then
                                 Choose_Root_Correction (Kick_From, Kick_To, "Best_Defend_Central_Pawn");
                                 Best_Promo := Promo_Of (Best_From, Best_To);
                              else
                                 Search_Integration.Best_Central_Pawn_Fork_Strike
                                   (Is_White_To_Move, Fork_Found, Fork_From, Fork_To);
                                 if Fork_Found and then Move_Is_Safe (Fork_From, Fork_To) then
                                    Choose_Root_Correction (Fork_From, Fork_To, "Best_Central_Pawn_Fork_Strike");
                                    Best_Promo := Promo_Of (Best_From, Best_To);
                                 else
                                    Search_Integration.Best_Queen_Kingside_Development
                                      (Is_White_To_Move, QDev_Found, QDev_From, QDev_To);
                                    if QDev_Found and then Move_Is_Safe (QDev_From, QDev_To) then
                                       Choose_Root_Correction (QDev_From, QDev_To, "Best_Queen_Kingside_Development");
                                       Best_Promo := Promo_Of (Best_From, Best_To);
                                    else
                                       Search_Integration.Best_Central_Knight_Outpost_Pressure
                                         (Is_White_To_Move, Outpost_Found, Outpost_From, Outpost_To);
                                       if Outpost_Found and then Move_Is_Safe (Outpost_From, Outpost_To) then
                                          Choose_Root_Correction (Outpost_From, Outpost_To, "Best_Central_Knight_Outpost_Pressure");
                                          Best_Promo := Promo_Of (Best_From, Best_To);
                                    else
                                       Search_Integration.Best_Central_Pawn_Capture
                                         (Is_White_To_Move, Cen_Found, Cen_From, Cen_To);
                                    if not Is_White_To_Move
                                      and then Cen_Found
                                      and then not Enemy_Queen_Attacks_King_Bishop_Pawn
                                      and then Move_Is_Safe (Cen_From, Cen_To)
                                    then
                                       Choose_Root_Correction (Cen_From, Cen_To, "Stage1a_Best_Central_Pawn_Capture");
                                       Best_Promo := Promo_Of (Best_From, Best_To);
                                    else
                                       Search_Integration.Best_Broad_Pawn_Center_Occupation
                                         (Is_White_To_Move, Broad_Found, Broad_From, Broad_To);
                                       if Broad_Found and then Move_Is_Safe (Broad_From, Broad_To) then
                                          Choose_Root_Correction (Broad_From, Broad_To, "Best_Broad_Pawn_Center_Occupation");
                                          Best_Promo := Promo_Of (Best_From, Best_To);
                                       else
                                          Search_Integration.Best_Wing_Pawn_Central_Counter
                                            (Is_White_To_Move, Broad_Found, Broad_From, Broad_To);
                                          if Broad_Found and then Move_Is_Safe (Broad_From, Broad_To) then
                                             Choose_Root_Correction (Broad_From, Broad_To, "Best_Wing_Pawn_Central_Counter");
                                             Best_Promo := Promo_Of (Best_From, Best_To);
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;
   end if;

   end if;
   end if;
   end if;
   end if;
   end if;
   end if;

      --  Stage 2: SEE-positive captures. The ply-4..16 chain can stamp
      --  Jogada_Perde_Profunda on a root take when some optional deeper
      --  ply is bad (documented over-pessimism), vetoing free or
      --  winning exchanges inside the cascade. Enforced here at the
      --  root: hanging takes (full victim value) and winning exchanges
      --  (See_Gain > 0 in centipawns when defended). No FEN hard-coding.
      if not Chose_Trap then
         Search_Integration.Best_Winning_Capture
           (Is_White_To_Move, Hang_Found, Hang_From, Hang_To);
         if Hang_Found and then Move_Is_Safe (Hang_From, Hang_To) then
            declare
               Win_Gain    : constant Integer :=
                 Search_Integration.See_Gain (Is_White_To_Move, Hang_From, Hang_To);
               Current_See : Integer := 0;
            begin
               if Best_To /= 0 and then Pvalidade.Tabuleiro (Best_To) /= 0 then
                  Current_See :=
                    Search_Integration.See_Gain (Is_White_To_Move, Best_From, Best_To);
               elsif Legacy_Was_Capture then
                  Current_See :=
                    Search_Integration.See_Gain (Is_White_To_Move, Legacy_From, Legacy_To);
               end if;
               if Legacy_Was_Capture
                 and then Current_See >= 200
                 and then abs Pvalidade.Tabuleiro (Legacy_From) /= 999
               then
                  --  Legacy engine (16 plies) already chose a winning piece capture.
                  --  A 1-ply capture must not override it unless it wins vastly more material (>= 300 cp delta)
                  --  or wins equal/greater SEE with a cheaper attacker (MVV-LVA, e.g. pawn taking piece vs piece trade).
                  if Win_Gain - Current_See >= 300 then
                     Best_From := Hang_From;
                     Best_To   := Hang_To;
                     Chose_Winning_Capture := True;
                     Chose_Root_Correction := False;
                  elsif Win_Gain >= Current_See
                    and then abs Pvalidade.Tabuleiro (Hang_From) = 1
                    and then abs Pvalidade.Tabuleiro (Legacy_From) > 1
                  then
                     Best_From := Hang_From;
                     Best_To   := Hang_To;
                     Chose_Winning_Capture := True;
                     Chose_Root_Correction := False;
                  else
                     Chose_Winning_Capture := True;
                  end if;
               elsif Win_Gain > Current_See
                 or else (Win_Gain = Current_See
                          and then Search_Integration.Recapture_Preference (Is_White_To_Move, Hang_From, Hang_To)
                                 > Search_Integration.Recapture_Preference (Is_White_To_Move, Best_From, Best_To))
               then
                  Best_From := Hang_From;
                  Best_To   := Hang_To;
                  Chose_Winning_Capture := True;
                  Chose_Root_Correction := False;
               elsif Current_See > 0 then
                  Chose_Winning_Capture := True;
               end if;
            end;
         end if;
      end if;

      --  Stage 2a: King Safety & Castling Priority. When castling is legal and
      --  safe, prioritizing king safety and rook activation beats quiet piece
      --  maneuvers and flank pawn play. B-C5: Root_Before < 2 gate removed.
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Root_Pre_Hang_Cp < 200
        and then Pvalidade.Tabuleiro (Best_To) = 0
      then
         Search_Integration.Best_Castle
           (Is_White_To_Move, Castle_Found, Castle_King);
         if Castle_Found then
            declare
               King_Sq : constant Integer :=
                 Move_Validation.Find_King (Is_White_To_Move);
               Castle_To : constant Integer :=
                 (if Castle_King then King_Sq + 2 else King_Sq - 2);
               --  Tempo-retreat guard (0.9.9.17.29 move 18): if one of our
               --  attacked minor pieces can step to a safe square that hits
               --  the enemy queen, castling is a tempo loss (18.O-O Nxd2
               --  -279 vs 18.Bf4 -80). Prefer the retreat-with-tempo.
               Opp_Q    : Integer := 0;
               Ret_From : Integer := 0;
               Ret_To   : Integer := 0;
               Own_Sign : constant Integer :=
                 (if Is_White_To_Move then 1 else -1);
            begin
               for Sq in 1 .. 64 loop
                  if Pvalidade.Tabuleiro (Sq) = -20 * Own_Sign then
                     Opp_Q := Sq;
                     exit;
                  end if;
               end loop;

               if Opp_Q /= 0 then
                  Retreat_Search :
                  for F in 1 .. 64 loop
                     if (Pvalidade.Tabuleiro (F) = 3 * Own_Sign
                         or else Pvalidade.Tabuleiro (F) = 4 * Own_Sign)
                       and then Move_Validation.Is_Square_Attacked
                         (F, By_White => not Is_White_To_Move)
                     then
                        for T in 1 .. 64 loop
                           if Pvalidade.Tabuleiro (T) = 0
                             and then Pvalidade.Validade (F, T)
                           then
                              declare
                                 Piece : constant Integer :=
                                   Pvalidade.Tabuleiro (F);
                                 Legal, Hits_Q : Boolean;
                              begin
                                 Pvalidade.Tabuleiro (T) := Piece;
                                 Pvalidade.Tabuleiro (F) := 0;
                                 Legal := not Move_Validation.Is_In_Check
                                   (Is_White_To_Move);
                                 Hits_Q := Pvalidade.Validade (T, Opp_Q);
                                 if Search_Integration.Trace_Root_Decisions then
                                    Put_Line ("info string [dbg2] " & Move_To_String (F, T, 0)
                                      & " CF=" & Boolean'Image (Search_Integration.Has_Opponent_Checking_Fork (Is_White_To_Move, T))
                                      & " DAt=" & Boolean'Image (Search_Integration.Has_Opponent_Double_Attack (Is_White_To_Move, T))
                                      & " DA0=" & Boolean'Image (Search_Integration.Has_Opponent_Double_Attack (Is_White_To_Move, 0))
                                      & " Pre=" & Root_Pre_Double_Attack'Image);
                                 end if;
                                 Pvalidade.Tabuleiro (F) := Piece;
                                 Pvalidade.Tabuleiro (T) := 0;
                                 if Search_Integration.Trace_Root_Decisions then
                                    Put_Line ("info string [dbg] " & Move_To_String (F, T, 0)
                                      & " L=" & Legal'Image & " H=" & Hits_Q'Image
                                      & " S=" & Boolean'Image (Move_Is_Safe (F, T))
                                      & " SH=" & Cost_Of (F, T).Self_Hang'Image
                                      & " Hg=" & Cost_Of (F, T).Hang_Cp'Image
                                      & " Pre=" & Root_Pre_Hang_Cp'Image
                                      & " M=" & Cost_Of (F, T).Mate'Image
                                      & " Fk=" & Cost_Of (F, T).Fork'Image
                                      & " Th=" & Cost_Of (F, T).Threat'Image
                                      & " GU=" & Cost_Of (F, T).Guard_Unsafe'Image
                                      & " DU=" & Cost_Of (F, T).Deflected_Unsafe'Image
                                      & " DS=" & Cost_Of (F, T).Deep_Safe'Image);
                                 end if;
                                 if Legal and then Hits_Q
                                   and then Move_Is_Safe (F, T)
                                 then
                                    Ret_From := F;
                                    Ret_To   := T;
                                    exit Retreat_Search;
                                 end if;
                              end;
                           end if;
                        end loop;
                     end if;
                  end loop Retreat_Search;
               end if;

               if Search_Integration.Trace_Root_Decisions then
                  Put_Line ("info string [root-trace] Stage2a tempo-retreat Opp_Q="
                            & Integer'Image (Opp_Q) & " ret="
                            & Move_To_String (Ret_From, Ret_To, 0));
               end if;
               if Ret_From /= 0 then
                  Choose_Root_Correction (Ret_From, Ret_To, "Stage2a_Tempo_Retreat");
               elsif King_Sq /= 0 and then Move_Is_Safe (King_Sq, Castle_To) then
                  Choose_Root_Correction (King_Sq, Castle_To, "Stage2a_Castle");
               end if;
            end;
         end if;
      end if;

      if not Chose_Root_Correction
        and then Chose_Winning_Capture
        and then abs Pvalidade.Tabuleiro (Best_From) = 1
        and then not Search_Integration.Creates_Major_Threat (Is_White_To_Move, Best_From, Best_To)
      then
         Search_Integration.Best_Development_Tempo_On_Queen
           (Is_White_To_Move, Pawn_Tempo_Found, Pawn_Tempo_From, Pawn_Tempo_To,
            Allow_Home_Queen => True);
         if Pawn_Tempo_Found and then Move_Is_Safe (Pawn_Tempo_From, Pawn_Tempo_To) then
            Choose_Root_Correction (Pawn_Tempo_From, Pawn_Tempo_To, "Stage2_Pawn_Cap_Dev_Tempo");
         end if;
      end if;

      --  Stage 2b: queen pawn-grab can yield to a queen tempo on an exposed
      --  enemy queen (e.g. Qc5/Qb4 instead of Qxe4). Keep higher-value
      --  winning captures untouched.
      if not Chose_Root_Correction
        and then abs Pvalidade.Tabuleiro (Best_From) = 20
        and then abs Pvalidade.Tabuleiro (Best_To) = 1
        and then not Search_Integration.Creates_Major_Threat (Is_White_To_Move, Best_From, Best_To)
      then
         Search_Integration.Best_Queen_Tempo_On_Queen
           (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
         if not Tempo_Found or else not Move_Is_Safe (Tempo_From, Tempo_To) then
            Search_Integration.Best_Development_Tempo_On_Queen
              (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
         end if;
         if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
            Choose_Root_Correction (Tempo_From, Tempo_To, "Stage2b_Queen_Tempo");
            if Chose_Root_Correction then
               Chose_Winning_Capture := False;
            end if;
         end if;
      end if;

      --  Stage 2b: pawn tempo-kick beats greedy piece-takes-pawn
      --  (Petroff ...d6 hitting Ne5, not the poisoned ...Nxe4). Applies
      --  even when the pawn is "free" â€” Nxe4 is still poisoned while Ne5
      --  sits on the board.
      declare
         Own_Sign : constant Integer := (if Is_White_To_Move then 1 else -1);
         Cap : constant Integer := abs Pvalidade.Tabuleiro (Best_From);
         Vic : constant Integer := abs Pvalidade.Tabuleiro (Best_To);
         Piece_Takes_Pawn : constant Boolean :=
           Cap > 1 and then Vic = 1
           and then Pvalidade.Tabuleiro (Best_To) * Own_Sign < 0;
      begin
         if not Chose_Root_Correction
           and then Piece_Takes_Pawn
           and then Root_Pre_Hang_Cp < 100
         then
            Search_Integration.Best_Pawn_Tempo_Kick
              (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
            if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To) then
               Choose_Root_Correction (Kick_From, Kick_To, "Stage2b_Pawn_Tempo_Kick");
            end if;
         end if;
      end;

      --  Stage 2c: absolute pin beats fleeing a hanging piece (Bb5 vs
      --  Nc6xd4, not Qa4).
      Search_Integration.Best_Absolute_Pin_Save
        (Is_White_To_Move, Pin_Found, Pin_From, Pin_To, Pin_Hang);
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Pin_Found
        and then Best_From = Pin_Hang
        and then Move_Is_Safe (Pin_From, Pin_To)
      then
         Choose_Root_Correction (Pin_From, Pin_To, "Stage2c_Absolute_Pin_Save");
      end if;

      --  Stage 2d: self-discovery (Nd7 opening Bg5xe7) â€” prefer a pawn
      --  challenge (h7-h6) or re-ask the cascade (Qd7).
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Search_Integration.Is_Self_Discovery
           (Is_White_To_Move, Best_From, Best_To)
      then
         Search_Integration.Best_Pawn_Tempo_Kick
           (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
         if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To)
           and then not Search_Integration.Is_Self_Discovery
                          (Is_White_To_Move, Kick_From, Kick_To)
         then
            Choose_Root_Correction (Kick_From, Kick_To, "Stage2d_Self_Discovery_Kick");
         else
            for Attempt in 1 .. Max_Vetoes loop
               exit when not Search_Integration.Is_Self_Discovery
                 (Is_White_To_Move, Best_From, Best_To);
               exit when Time_Management.Search_Aborted;
               Veto_Legacy (Best_From, Best_To);
               Run_Legacy_Cascade_Only;
               exit when Legacy_From = Legacy_To;
               exit when Time_Management.Search_Aborted;
               if Move_Is_Safe (Legacy_From, Legacy_To) then
                  Best_From := Legacy_From;
                  Best_To   := Legacy_To;
               else
                  exit;
               end if;
            end loop;
            pprechess2.Jogada_Vetada := [others => [others => False]];
         end if;
      end if;

      --  Stage 2e: opening blunders and queen tempi â€” exposed enemy queen,
      --  Qf6 facing enemy Q, premature Bb4/Bg4, or early Qa5 instead of a
      --  central pawn trade (dxe4).
      if not Chose_Winning_Capture and then not Chose_Root_Correction then
         Search_Integration.Best_Queen_Tempo_On_Queen
           (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
         if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
            Choose_Root_Correction (Tempo_From, Tempo_To, "Stage2e_Queen_Tempo_On_Queen");
         else
            Search_Integration.Best_Development_Tempo_On_Queen
              (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
            if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
               Choose_Root_Correction (Tempo_From, Tempo_To, "Stage2e_Dev_Tempo_On_Queen");
            elsif Search_Integration.Is_Bad_Queen_Sortie
              (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Reinforce_King_Bishop_Pawn
              (Is_White_To_Move, Re_Found, Re_From, Re_To);
            if Re_Found and then Move_Is_Safe (Re_From, Re_To) then
               Choose_Root_Correction (Re_From, Re_To, "Stage2e_Reinforce_KBP");
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Post_Reinforce");
               end if;
            end if;
         elsif Search_Integration.Is_Premature_Flank_Bishop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Solid_Response_To_Flank_Bishop
              (Is_White_To_Move, Solid_Found, Solid_From, Solid_To);
            if Solid_Found and then Move_Is_Safe (Solid_From, Solid_To) then
               Choose_Root_Correction (Solid_From, Solid_To, "Stage2e_Solid_Resp_Flank_Bishop");
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Post_Flank_Bishop");
               end if;
            end if;
         elsif Search_Integration.Is_Early_Queen_Develop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Central_Pawn_Capture
              (Is_White_To_Move, Cen_Found, Cen_From, Cen_To);
            if Cen_Found and then Move_Is_Safe (Cen_From, Cen_To) then
               Choose_Root_Correction (Cen_From, Cen_To, "Stage2e_Central_Pawn_Capture");
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Post_Central_Cap");
               end if;
            end if;
         elsif Search_Integration.Is_Premature_Knight_Hop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Opening_Quiet_Alternative
              (Is_White_To_Move, Alt_Found, Alt_From, Alt_To);
            if Alt_Found and then Move_Is_Safe (Alt_From, Alt_To) then
               Choose_Root_Correction (Alt_From, Alt_To, "Stage2e_Opening_Quiet_Alt");
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Post_Quiet_Alt");
               end if;
            end if;
         elsif Search_Integration.Is_Passive_Early_Bishop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Natural_Development
              (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
            if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
               Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Passive_Bishop");
            end if;
         elsif Search_Integration.Is_Flank_Gambit_Pawn_Offer
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Natural_Development
              (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
            if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
               Choose_Root_Correction (Nat_From, Nat_To, "Stage2e_Natural_Dev_Flank_Gambit");
            end if;
         end if;
         end if;
      end if;

      --  Stage 2f: equal king-bishop-pawn attacker trades and queenside
      --  b-pawn plans. These are opening/tactical root corrections that
      --  should beat quiet pawn shuffles, but not a SEE-positive capture.
      if not Chose_Winning_Capture and then not Chose_Root_Correction then
         Search_Integration.Best_King_Bishop_Pawn_Attacker_Trade
           (Is_White_To_Move, Trade_Found, Trade_From, Trade_To);
         if Trade_Found and then Move_Is_Safe (Trade_From, Trade_To) then
            Choose_Root_Correction (Trade_From, Trade_To, "Stage2f_KBP_Attacker_Trade");
         else
            Search_Integration.Best_Queenside_B_Pawn_Plan
              (Is_White_To_Move, QSide_Found, QSide_From, QSide_To);
            if QSide_Found and then Move_Is_Safe (QSide_From, QSide_To) then
               Choose_Root_Correction (QSide_From, QSide_To, "Stage2f_Queenside_B_Pawn_Plan");
            end if;
         end if;
      end if;

      --  Stage 2i: equal-or-better minor capture of an advanced central pawn.
      --  This is narrower than broad pawn-grabbing: only d/e pawns on ranks
      --  4/5 and only minor-piece captures with SEE >= 0.
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Pvalidade.Tabuleiro (Best_To) = 0
      then
         Search_Integration.Best_Advanced_Central_Pawn_Minor_Capture
           (Is_White_To_Move, MinorCap_Found, MinorCap_From, MinorCap_To);
         if MinorCap_Found and then Move_Is_Safe (MinorCap_From, MinorCap_To) then
            Choose_Root_Correction (MinorCap_From, MinorCap_To, "Stage2i_Advanced_Central_Pawn_Minor_Cap");
         end if;
      end if;


      --  Stage 2i: equal-or-better non-pawn captures. After the specific
      --  tactical/opening root corrections above have had first refusal, if
      --  the move is still quiet, prefer a legal SEE-neutral-or-better capture
      --  of a piece. Pawn captures are deliberately excluded here because
      --  broad equal pawn trades regressed quiet-space gates.
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Pvalidade.Tabuleiro (Best_To) = 0
      then
         Search_Integration.Best_Non_Losing_Capture
           (Is_White_To_Move, EqCap_Found, EqCap_From, EqCap_To);
         if EqCap_Found
           and then abs Pvalidade.Tabuleiro (EqCap_To) > 1
           and then Move_Is_Safe (EqCap_From, EqCap_To)
         then
            Best_From := EqCap_From;
            Best_To   := EqCap_To;
            Chose_Winning_Capture := True;
         end if;
      end if;

      --  Stage 2i: targeted non-tempo flank-pawn repair. If the legacy
      --  quiet fallback chooses an opening/middlegame flank pawn shove that
      --  creates no tempo, prefer a generic central/development alternative.
      --  This deliberately excludes pawn-only endgames, captures,
      --  promotions, central pawn play, and pawn tempo kicks.
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Search_Integration.Is_Opening_Non_Tempo_Flank_Pawn_Push
                   (Is_White_To_Move, Best_From, Best_To)
      then
         Search_Integration.Best_Opening_Quiet_Alternative
           (Is_White_To_Move, Alt_Found, Alt_From, Alt_To);
         if Alt_Found and then Move_Is_Safe (Alt_From, Alt_To) then
            Choose_Root_Correction (Alt_From, Alt_To, "Stage2i_Flank_Pawn_Quiet_Alt");
         end if;
      end if;



      --  Stage 3: en-prise resolve.
      --  S-G8-1 (M1): Stage 3 runs unconditionally; a themed correction must beat it
      --  on exchange value, not on flag order.
      Search_Integration.Best_En_Prise_Resolve
        (Is_White_To_Move, Resolve_Found, Resolve_From, Resolve_To);
      if Search_Integration.Trace_Root_Decisions then
         Put_Line ("info string [root-trace] Stage3 EnPrise found=" &
           Boolean'Image (Resolve_Found) & " mv=" &
           Move_To_String (Resolve_From, Resolve_To, 0) &
           " Best=" & Move_To_String (Best_From, Best_To, 0) &
           " CRC=" & Boolean'Image (Chose_Root_Correction) &
           " CWC=" & Boolean'Image (Chose_Winning_Capture) &
           " Safe=" & (if Resolve_Found then Boolean'Image (Move_Is_Safe (Resolve_From, Resolve_To)) else "N/A"));
      end if;
      if Resolve_Found
        and then (Best_From /= Resolve_From or else Best_To /= Resolve_To)
        and then Move_Is_Safe (Resolve_From, Resolve_To)
      then
         declare
            Resolve_Net : constant Integer :=
              Compute_Net_Material (Resolve_From, Resolve_To);
            Current_Net : constant Integer :=
              Compute_Net_Material (Best_From, Best_To);
            Resolve_Gain : constant Integer :=
              Search_Integration.See_Gain (Is_White_To_Move, Resolve_From, Resolve_To);
            Current_Gain : constant Integer :=
              (if Chose_Winning_Capture
               then Search_Integration.See_Gain (Is_White_To_Move, Best_From, Best_To)
               else 0);
            --  B-C5: King-safety guard. A Stage-2 castling choice must not be
            --  discarded by the en-prise resolver merely to rescue material
            --  worth less than a minor piece. Net_Cp credits a quiet
            --  pawn-saving push (e.g. a2a4) with the full saved-hang value,
            --  which otherwise outranks castling (Net 0) and forfeits king
            --  safety -- the root cause of the move-15 a2a4 blunder vs Dika.
            --  Rescuing a rook/queen (>= 300 cp) by declining to castle is
            --  still permitted.
            Best_Is_Castle : constant Boolean :=
              abs Pvalidade.Tabuleiro (Best_From) = 999
              and then abs (Move_Validation.File_Of (Best_To)
                            - Move_Validation.File_Of (Best_From)) = 2;
         begin
            if not Chose_Trap
              and then not (Best_Is_Castle and then Root_Pre_Hang_Cp < 300)
              and then ((not Chose_Winning_Capture
                         and then not (Pvalidade.Tabuleiro (Best_To) /= 0
                                       and then Search_Integration.See_Gain (Is_White_To_Move, Best_From, Best_To) >= 200)
                         and then not (Chose_Root_Correction and then Resolve_Gain <= 0 and then abs Pvalidade.Tabuleiro (Resolve_From) < 3))
                        or else Resolve_Gain > Current_Gain
                        or else Resolve_Net > Current_Net)
            then
               if Search_Integration.Trace_Root_Decisions then
                  Put_Line ("info string [root-trace] Stage3 RESOLVE-OVERRIDE");
               end if;
               Choose_Root_Correction (Resolve_From, Resolve_To, "Stage3_Resolve_Override");
               if Resolve_Gain > 0 then
                  if Chose_Root_Correction then Chose_Winning_Capture := True; end if;
               end if;
            end if;
         end;
      elsif not Chose_Trap
        and then not Chose_Winning_Capture
        and then Search_Integration.Is_Soft_Defend
                (Is_White_To_Move, Best_From, Best_To)
      then
         --  Piece takes of a hanging pawn: do not cling (b7-b5 /
         --  c8-e6 / c4-c3). Prefer real development (e7-e6 / Nf6).
         Search_Integration.Best_Development_Vs_Hanging_Pawn
           (Is_White_To_Move, Dev_Found, Dev_From, Dev_To);
         if Dev_Found and then Move_Is_Safe (Dev_From, Dev_To) then
            if Search_Integration.Trace_Root_Decisions then
               Put_Line ("info string [root-trace] Stage3 DEV-VS-HANGING-PAWN");
            end if;
            Choose_Root_Correction (Dev_From, Dev_To, "Stage3_Dev_Vs_Hanging_Pawn");
         else
            --  Soft shield vs enemy pawn (c7-c6): re-ask cascade.
            for Attempt in 1 .. Max_Vetoes loop
               exit when not Search_Integration.Is_Soft_Defend
                 (Is_White_To_Move, Best_From, Best_To);
               exit when Time_Management.Search_Aborted;
               Veto_Legacy (Best_From, Best_To);
               Run_Legacy_Cascade_Only;
               exit when Legacy_From = Legacy_To;
               exit when Time_Management.Search_Aborted;
               if Move_Is_Safe (Legacy_From, Legacy_To) then
                  Best_From := Legacy_From;
                  Best_To   := Legacy_To;
               else
                  exit;
               end if;
            end loop;
            pprechess2.Jogada_Vetada := [others => [others => False]];
         end if;
      end if;

      --  Stage 4: en passant / castling only when we still have the
      --  cascade's quiet choice (do not override a resolve/capture).
      --  B-C5: Root_Before < 2 gate removed.
      if not Chose_Root_Correction
        and then Best_From = Legacy_From and then Best_To = Legacy_To
        and then Root_Pre_Hang_Cp < 200
        and then Pvalidade.Tabuleiro (Best_To) = 0
      then
         Ep_From := Search_Integration.En_Passant_Candidate (Is_White_To_Move);
         if Ep_From /= 0
           and then Move_Is_Safe (Ep_From, Move_Validation.En_Passant_Sq)
         then
            Best_From := Ep_From;
            Best_To   := Move_Validation.En_Passant_Sq;
         else
            Search_Integration.Best_Castle (Is_White_To_Move, Castle_Found, Castle_King);
            if Castle_Found then
               declare
                  King_Sq : constant Integer :=
                    Move_Validation.Find_King (Is_White_To_Move);
                  Castle_To : constant Integer :=
                    (if Castle_King then King_Sq + 2 else King_Sq - 2);
               begin
                  if King_Sq /= 0 and then Move_Is_Safe (King_Sq, Castle_To) then
                     Best_From := King_Sq;
                     Best_To   := Castle_To;
                  end if;
               end;
            end if;
         end if;
      end if;

      --  Stage 5 (P9 endgame): in a recognized mating regime (KQ/KR/KBB/KP vs
      --  lone K) steer toward the move that best confines the enemy king /
      --  advances the pawn. N1-general (fires on ANY position with that
      --  material signature); adopted only if Move_Is_Safe. No-op elsewhere,
      --  so it cannot affect opening/middlegame move choice.
      declare
         Eg_Found : Boolean;
         Eg_From, Eg_To : Integer;
      begin
         Search_Integration.Best_Endgame
           (White_To_Move => Is_White_To_Move,
            Found         => Eg_Found,
            From_Sq       => Eg_From,
            To_Sq         => Eg_To);
         if Eg_Found and then Move_Is_Safe (Eg_From, Eg_To) then
            Best_From := Eg_From;
            Best_To   := Eg_To;
         else
            declare
               Passed_Adv_Found : Boolean;
               Passed_Adv_F, Passed_Adv_T : Integer;
            begin
               Search_Integration.Best_Endgame_Passed_Pawn_Advance
                 (White_To_Move => Is_White_To_Move,
                  Found         => Passed_Adv_Found,
                  From_Sq       => Passed_Adv_F,
                  To_Sq         => Passed_Adv_T);
               if Passed_Adv_Found and then Move_Is_Safe (Passed_Adv_F, Passed_Adv_T) then
                  Best_From := Passed_Adv_F;
                  Best_To   := Passed_Adv_T;
               end if;
            end;
         end if;
      end;
      --  Stage 6: Root Move Safety Gate. If the chosen candidate move is not
      --  safe (e.g. blunders material or hands over a free pawn/piece),
      --  fall back to a verified safe quiet move or natural development.
      if not Move_Is_Safe (Best_From, Best_To) then
         Search_Integration.Best_Opening_Quiet_Alternative
           (Is_White_To_Move, Alt_Found, Alt_From, Alt_To);
         if Alt_Found and then Move_Is_Safe (Alt_From, Alt_To) then
            Choose_Root_Correction (Alt_From, Alt_To, "Stage6_Safety_Quiet_Alt");
         else
            Search_Integration.Best_Natural_Development
              (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
            if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
               Choose_Root_Correction (Nat_From, Nat_To, "Stage6_Safety_Natural_Dev");
            end if;
         end if;
      end if;

      --  Final Net Gate (replaces N10 and B-C6). Last writer: ranks the
      --  current choice, the legacy pair, and every legal candidate by
      --  Compute_Net_Material. Strictly-better only; ties keep the
      --  incumbent, so the cascade move wins a tie on purpose.
      declare
         Legacy_Net : Integer;
         Cand_Net   : Integer;
         Legacy_See : Integer := 0;
         Best_Is_Castle : constant Boolean :=
           Best_From in 1 .. 64 and then Best_To in 1 .. 64
           and then abs Pvalidade.Tabuleiro (Best_From) = 999
           and then abs (Move_Validation.File_Of (Best_To)
                         - Move_Validation.File_Of (Best_From)) = 2;
      begin
         if Legacy_From /= Legacy_To then
            Legacy_Net := Compute_Net_Material (Legacy_From, Legacy_To);
            if Legacy_Was_Capture and then Legacy_To /= 0 then
               Legacy_See := Search_Integration.See_Gain (Is_White_To_Move, Legacy_From, Legacy_To);
            end if;
            if ((Walks_Into_Loss (Best_From, Best_To)
                 and then not Chose_Trap
                 and then not Walks_Into_Loss (Legacy_From, Legacy_To))
                or else
                (Legacy_Net > Compute_Net_Material (Best_From, Best_To)
                 and then not Walks_Into_Loss (Legacy_From, Legacy_To)
                 and then not (Best_Is_Castle and then Root_Pre_Hang_Cp < 300
                               and then not (Legacy_Was_Capture and then Legacy_See >= 200))
                 and then not (Chose_Root_Correction
                               and then not (Legacy_Was_Capture and then Legacy_See >= 200))))
            then
               if Search_Integration.Trace_Root_Decisions then
                  Put_Line ("info string [root-trace] Overridden by Legacy: " &
                            Move_To_String (Legacy_From, Legacy_To, 0));
               end if;
               Best_From := Legacy_From;
               Best_To   := Legacy_To;
            end if;
         end if;
         if Search_Integration.Trace_Root_Decisions then
            Put_Line ("info string [root-trace] Legacy: " & Move_To_String (Legacy_From, Legacy_To, 0) & " Best: " & Move_To_String (Best_From, Best_To, 0));
         end if;
         declare
            Root_Eval : constant Integer :=
              (if Is_White_To_Move then Search_Integration.Evaluate
               else -Search_Integration.Evaluate);
         begin
            --  0.9.9.17.9 pre-pass (m28 g4?? / m13 Nf3 class): an incumbent
            --  that leaves material hanging (Hang >= a pawn) which the side
            --  did not have before, without material compensation (no
            --  candidate-matching Net), loses its Chose_Root_Correction
            --  protection: a themed correction or legacy choice must not
            --  hang a pawn that a safe candidate keeps -- 28. g4 (Bxg4)
            --  and 13. Nf3 (self-blocking the g2-bishop's guard of e4)
            --  both came from exactly this. Ranked: highest Net first,
            --  then PST delta from->to, so a developing saver (13. Ne2)
            --  beats a passive one (13. Qb1). King moves (castling
            --  included) keep their protection (B-C5).
            if Best_From /= 0 and then Root_Candidates.Count > 0 then
               declare
                  Incumbent_Cost : constant Move_Cost := Cost_Of (Best_From, Best_To);
                  Incumbent_Net_Pre : constant Integer := Incumbent_Cost.Net_Cp;
                  Phase_Pre : constant Integer := pprechess2.Positional_Game_Phase;
                  Best_Pre_Net : Integer := Integer'First;
                  Best_Pre_Pst : Integer := Integer'First;
                  Pre_Is_Cap   : Boolean := False;
                  Pre_F, Pre_T : Integer := 0;
               begin
                  --  0.9.9.17.29: a tempo move that attacks a major piece
                  --  (SEE >= 300) while leaving only a minor-or-less hang
                  --  keeps the initiative: the opponent must answer the
                  --  threat first (18. Bf4! hitting Qe5; rescue picked
                  --  18. Qe2?? Nxd2, SF -551 vs -112).
                  if Incumbent_Cost.Hang_Cp >= 100
                    and then not Chose_Trap
                    and then not (Incumbent_Cost.Hang_Cp < 300
                                  and then not Incumbent_Cost.Self_Hang
                                  and then Search_Integration.Creates_Major_Threat
                                    (Is_White_To_Move, Best_From, Best_To))
                    and then abs Pvalidade.Tabuleiro (Best_From) /= 999
                  then
                     for I in 1 .. Root_Candidates.Count loop
                        declare
                           C : Search_Integration.Root_Candidate renames
                                 Root_Candidates.Candidates (I);
                           CC : constant Move_Cost := Cost_Of (C.From_Sq, C.To_Sq);
                           Piece_Pre : constant Integer :=
                             abs Pvalidade.Tabuleiro (C.From_Sq);
                           Src_Sq : constant Integer :=
                             (if Is_White_To_Move then C.From_Sq
                              else Move_Validation.Mirror_Square (C.From_Sq));
                           Dst_Sq : constant Integer :=
                             (if Is_White_To_Move then C.To_Sq
                              else Move_Validation.Mirror_Square (C.To_Sq));
                           Pst_Delta : Integer;
                        begin
                           if CC.Hang_Cp < Incumbent_Cost.Hang_Cp
                             and then CC.Net_Cp >= Incumbent_Net_Pre
                             and then abs Pvalidade.Tabuleiro (C.From_Sq) /= 999
                             and then not Walks_Into_Loss (C.From_Sq, C.To_Sq)
                             and then Move_Is_Safe (C.From_Sq, C.To_Sq)
                           then
                              Pst_Delta :=
                                pprechess2.Positional_Test_Score (Piece_Pre, Dst_Sq, Phase_Pre)
                                - pprechess2.Positional_Test_Score (Piece_Pre, Src_Sq, Phase_Pre);
                              if CC.Net_Cp > Best_Pre_Net
                                or else (CC.Net_Cp = Best_Pre_Net
                                         and then ((CC.Is_Capture and then not Pre_Is_Cap)
                                                   or else (CC.Is_Capture = Pre_Is_Cap
                                                            and then Pst_Delta > Best_Pre_Pst)))
                              then
                                 Best_Pre_Net := CC.Net_Cp;
                                 Best_Pre_Pst := Pst_Delta;
                                 Pre_Is_Cap   := CC.Is_Capture;
                                 Pre_F := C.From_Sq;
                                 Pre_T := C.To_Sq;
                              end if;
                           end if;
                        end;
                     end loop;
                     if Pre_F /= 0
                       and then (Pre_F /= Best_From or else Pre_T /= Best_To)
                     then
                        if Search_Integration.Trace_Root_Decisions then
                           Put_Line ("info string [root-trace] Pre-Pass HANG-RESCUE: " &
                                     Move_To_String (Best_From, Best_To, 0) & " -> " &
                                     Move_To_String (Pre_F, Pre_T, 0)
                                     & " (incHang=" & Integer'Image (Incumbent_Cost.Hang_Cp)
                                     & " candHang=" & Integer'Image
                                         (Cost_Of (Pre_F, Pre_T).Hang_Cp) & ")");
                        end if;
                        Best_From := Pre_F;
                        Best_To   := Pre_T;
                     end if;
                  end if;
               end;
            end if;

            for I in 1 .. Root_Candidates.Count loop
               declare
                  C : Search_Integration.Root_Candidate renames
                        Root_Candidates.Candidates (I);
                  Cand_Cost : constant Move_Cost := Cost_Of (C.From_Sq, C.To_Sq);
                  Best_Cost : constant Move_Cost :=
                    (if Best_From /= 0 then Cost_Of (Best_From, Best_To)
                     else Cand_Cost);
                  Best_Is_Castle : constant Boolean :=
                    Best_From in 1 .. 64 and then Best_To in 1 .. 64
                    and then abs Pvalidade.Tabuleiro (Best_From) = 999
                    and then abs (Move_Validation.File_Of (Best_To)
                                  - Move_Validation.File_Of (Best_From)) = 2;
               begin
                  Cand_Net := Compute_Net_Material (C.From_Sq, C.To_Sq);
                  if Cand_Cost.Rep_Count >= 2 then
                     if Root_Eval >= 50 then
                        Cand_Net := Cand_Net - 5000;
                     elsif Root_Eval <= -150 then
                        Cand_Net := Cand_Net + 5000;
                     end if;
                  elsif Cand_Cost.Rep_Count = 1 and then Root_Eval >= 50 then
                     Cand_Net := Cand_Net - 50;
                  end if;

                  if Legacy_Was_Capture and then Legacy_See >= 200
                    and then Best_From = Legacy_From and then Best_To = Legacy_To
                  then
                     --  Legacy engine found a winning piece capture.
                     --  Do not override with 1-ply candidate unless it wins >= 300 cp more net material.
                     if Cand_Net - Compute_Net_Material (Best_From, Best_To) >= 300
                       and then not Walks_Into_Loss (C.From_Sq, C.To_Sq)
                       and then (not Chose_Root_Correction
                                 or else abs Pvalidade.Tabuleiro (C.From_Sq) > 1)
                     then
                        Best_From := C.From_Sq;
                        Best_To   := C.To_Sq;
                     end if;
                  elsif ((Walks_Into_Loss (Best_From, Best_To)
                          and then not Chose_Trap
                          and then not Walks_Into_Loss (C.From_Sq, C.To_Sq))
                         or else
                         (Best_Cost.Rep_Count >= 2 and then Root_Eval >= 50
                          and then Cand_Cost.Rep_Count < 2 and then Move_Is_Safe (C.From_Sq, C.To_Sq))
                         or else
                         ((Cand_Net >= Compute_Net_Material (Best_From, Best_To) + 100
                           or else (Cand_Net > Compute_Net_Material (Best_From, Best_To)
                                    and then Best_From /= Legacy_From))
                          and then not Walks_Into_Loss (C.From_Sq, C.To_Sq)
                          and then not Chose_Trap
                          --  0.9.9.17.29: keep a tempo move that attacks a
                          --  major piece (SEE >= 300) when it only concedes a
                          --  minor-or-less hang and the candidate's 1-ply edge
                          --  is below a piece (18. Bf4! vs 18. Qe2?? Nxd2).
                          and then not (Best_Cost.Hang_Cp < 300
                                        and then not Best_Cost.Self_Hang
                                        and then Cand_Net < Compute_Net_Material (Best_From, Best_To) + 300
                                        and then Search_Integration.Attacks_Enemy_Queen
                                          (Is_White_To_Move, Best_From, Best_To)
                                        and then Search_Integration.Creates_Major_Threat
                                          (Is_White_To_Move, Best_From, Best_To)
                                        and then not Search_Integration.Attacks_Enemy_Queen
                                          (Is_White_To_Move, C.From_Sq, C.To_Sq))
                          and then not (Best_Is_Castle and then Root_Pre_Hang_Cp < 300
                                        and then not (Cand_Cost.Is_Capture and then Cand_Cost.Gain_Cp >= 300))
                          and then not (Best_Is_Castle and then abs Pvalidade.Tabuleiro (C.From_Sq) = 999)
                          and then (not Chose_Root_Correction
                                    or else abs Pvalidade.Tabuleiro (C.From_Sq) > 1)))
                  then
                     if Search_Integration.Trace_Root_Decisions then
                        Put_Line ("info string [root-trace] Overridden by Candidate: " &
                                  Move_To_String (C.From_Sq, C.To_Sq, 0)
                                  & " (bestHang=" & Integer'Image (Best_Cost.Hang_Cp)
                                  & " candHang=" & Integer'Image (Cand_Cost.Hang_Cp)
                                  & " candNet=" & Integer'Image (Cand_Net)
                                  & " bestNet=" & Integer'Image
                                      (Compute_Net_Material (Best_From, Best_To)) & ")");
                     end if;
                     Best_From := C.From_Sq;
                     Best_To   := C.To_Sq;
                  end if;
               end;
            end loop;
         end;
      end;

      --  Stage 6.5 (0.9.9.17.9): anti-shuffle arbitration. A quiet
      --  incumbent that (a) undoes our previous own quiet move, (b) re-plays
      --  an own quiet move already made in this game, or (c) recreates an
      --  earlier position is demoted in favour of the best safe candidate
      --  with equal-or-better net material that breaks the cycle. Skipped
      --  when clearly lost (Root_Eval <= -300), where shuffling towards a
      --  repetition claim is a legitimate save; the candidate-level
      --  repetition-seek bonus (Root_Eval <= -150) in the Net Gate is
      --  untouched. Root cause: the legacy cascade cycles between the same
      --  two moves with no progress mechanism -- the Ra1/Rab1 shuffle
      --  (moves 21-28, ~3200 cp cumulative) and the Rh8/Rg8 shuffle that
      --  threw away a completely won endgame (moves 66-104, threefold draw
      --  at +20) in the analysed game.
      declare
         Root_Eval_65 : constant Integer :=
           (if Is_White_To_Move then Search_Integration.Evaluate
            else -Search_Integration.Evaluate);

         function Move_Is_Stale (F, T : Integer) return Boolean is
            Mover : constant Integer :=
              (if F in 1 .. 64 then abs Pvalidade.Tabuleiro (F) else 0);
            Is_Cap : constant Boolean :=
              Pvalidade.Tabuleiro (T) /= 0
              or else (Mover = 1 and then Move_Validation.En_Passant_Sq /= 0
                       and then T = Move_Validation.En_Passant_Sq);
            Last_Own_Found  : Boolean := False;
            Last_Own_From   : Integer := 0;
            Last_Own_To     : Integer := 0;
         begin
            if Mover = 0 or else Is_Cap or else Mover = 1 then
               return False;
            end if;
            --  (c) the move recreates a position already seen
            if Cost_Of (F, T).Rep_Count >= 1 then
               return True;
            end if;
            --  (a) the move undoes our previous own quiet move
            for I in reverse 1 .. Game_Move_Count loop
               if Game_Moves (I).White_Move = Is_White_To_Move then
                  Last_Own_From := Game_Moves (I).From_Sq;
                  Last_Own_To   := Game_Moves (I).To_Sq;
                  Last_Own_Found := True;
                  exit;
               end if;
            end loop;
            if Last_Own_Found
              and then Last_Own_From = T
              and then Last_Own_To = F
            then
               return True;
            end if;
            --  (b) the same piece already made this exact quiet move
            for I in 1 .. Game_Move_Count loop
               if Game_Moves (I).White_Move = Is_White_To_Move
                 and then Game_Moves (I).From_Sq = F
                 and then Game_Moves (I).To_Sq = T
                 and then Game_Moves (I).Piece_Code = Mover
               then
                  return True;
               end if;
            end loop;
            return False;
         end Move_Is_Stale;

         Incumbent_Net : constant Integer := Compute_Net_Material (Best_From, Best_To);
         Best_Fresh_Net : Integer := Integer'First;
         Fresh_F, Fresh_T : Integer := 0;
      begin
         if Search_Integration.Trace_Root_Decisions then
            Put_Line ("info string [root-trace] Stage6.5 eval=" &
                      Integer'Image (Root_Eval_65)
                      & " incumbent=" & Move_To_String (Best_From, Best_To, 0)
                      & " stale=" & Boolean'Image
                        ((if Best_From /= 0 then Move_Is_Stale (Best_From, Best_To)
                          else False))
                      & " gmoves=" & Integer'Image (Game_Move_Count));
         end if;
         if Best_From /= 0
           and then Pvalidade.Tabuleiro (Best_To) = 0
           and then Root_Eval_65 > -300
           and then Move_Is_Stale (Best_From, Best_To)
         then
            for I in 1 .. Root_Candidates.Count loop
               declare
                  C : Search_Integration.Root_Candidate renames
                        Root_Candidates.Candidates (I);
                  Cand_Net : Integer;
               begin
                  if Pvalidade.Tabuleiro (C.To_Sq) = 0
                    and then not Move_Is_Stale (C.From_Sq, C.To_Sq)
                    and then Move_Is_Safe (C.From_Sq, C.To_Sq)
                    and then not Walks_Into_Loss (C.From_Sq, C.To_Sq)
                  then
                     Cand_Net := Compute_Net_Material (C.From_Sq, C.To_Sq);
                     if Cand_Net >= Incumbent_Net
                       and then Cand_Net > Best_Fresh_Net
                     then
                        Best_Fresh_Net := Cand_Net;
                        Fresh_F := C.From_Sq;
                        Fresh_T := C.To_Sq;
                     end if;
                  end if;
               end;
            end loop;
            if Fresh_F /= 0 then
               if Search_Integration.Trace_Root_Decisions then
                  Put_Line ("info string [root-trace] Stage6.5 ANTI-SHUFFLE: " &
                            Move_To_String (Best_From, Best_To, 0) & " -> " &
                            Move_To_String (Fresh_F, Fresh_T, 0));
               end if;
               Best_From := Fresh_F;
               Best_To   := Fresh_T;
            elsif Search_Integration.Trace_Root_Decisions then
               Put_Line ("info string [root-trace] Stage6.5 stale incumbent kept: " &
                         Move_To_String (Best_From, Best_To, 0)
                         & " (eligible fresh candidates: 0)");
            end if;
         end if;
      end;

      --  Stage 7 (0.9.9.17.10/0.9.9.17.11): alpha-beta verification overlay,
      --  UCI option Verify_Depth (default 8; 0 = off). The legacy cascade and
      --  the arbitration stages above still produce the move in both toggle
      --  positions; with the option > 0 the Tactical_Search alpha-beta then
      --  checks that move against every legal alternative at the configured
      --  depth inside the remaining time budget and replaces it only when
      --  an alternative is provably better by >= Verify_Margin (default 25 cp)
      --  at the completed depth. This is the A/B toggle for the horizon
      --  effect (missed 3+ ply tactics such as 7. dxc4 / 42. Ne7+).
      --  0.9.9.17.11: (a) honest reporting -- the verified score/PV is kept
      --  for Execute_Search's final info line; (b) the verifier auto-deepens
      --  to 12 plies in overwhelming-surplus endgames (>= 600 cp own
      --  material eval) with time to spare, the mate-conversion regime;
      --  (c) the budget floor is clock-safe in scrambles (remaining minus
      --  the latency margin, not a flat 50 ms that could overrun).
      Time_Management.Restore_Time_Slice;
      if Verify_Depth_Opt > 0
        and then Best_From /= 0
        and then not Time_Management.Search_Aborted
      then
         declare
            Unbounded : constant Boolean :=
              Time_Management.Allocated_Ms > 3_000_000;
            Remaining : Integer := 0;
            Budget    : Natural := 0;
            Depth_Cap : Integer := Verify_Depth_Opt;
         begin
            --  go depth N is a hard request, not merely a time-control hint.
            if Time_Management.Requested_Depth > 0 then
               Depth_Cap := Integer'Min (Max_Verify_Depth,
                                         Time_Management.Requested_Depth);
            end if;
            if Unbounded then
               --  0.9.9.17.28: infinite analysis runs until the GUI sends
               --  stop/quit (Tick makes cancellation immediate). A fixed
               --  5 s cap ended the search early, so a large Hash table
               --  never filled and hashfull stayed near 0.
               Budget := Unbounded_Verify_Budget_Ms;
            else
               Remaining := Time_Management.Allocated_Ms
                              - Time_Management.Elapsed_Ms;
               if Remaining >= 40 then
                  if Remaining >= 1000 then
                     Budget := (Remaining * 4) / 5;
                     if Budget > 8000 then
                        Budget := 8000;
                     end if;
                  else
                     Budget := Remaining / 2;
                     if Budget < 50 then
                        Budget := Integer'Max (10, Remaining - 20);
                     end if;
                  end if;
               end if;
            end if;

            if Unbounded or else Remaining >= 40 then
               --  0.9.9.17.27: deepened verifier horizon (12 -> 16 plies).
               --  Iterative deepening keeps the last completed depth when the
               --  budget expires, so the deeper cap stays clock-safe; infinite
               --  analysis uses the same cap and remains stop-responsive
               --  through Tick.
               if Time_Management.Requested_Depth = 0
                 and then (Unbounded or else Remaining >= 2000)
               then
                  Depth_Cap := Integer'Max (Verify_Depth_Opt, Deep_Verify_Horizon);
                  --  Infinite analysis keeps deepening until stop.
                  if Unbounded then
                     Depth_Cap := Max_Verify_Depth;
                  end if;
               end if;

               --  Auto-deepen in the mate-conversion regime. Check the cheap
               --  guards before paying for the full-board evaluation.
               if Time_Management.Requested_Depth = 0
                 and then (Unbounded or else Budget >= 800)
               then
                  declare
                     Own_Eval : constant Integer :=
                       (if Is_White_To_Move then Tactical_Search.Evaluate_White
                        else -Tactical_Search.Evaluate_White);
                  begin
                     if Own_Eval >= 600 then
                        Depth_Cap := Integer'Max (Verify_Depth_Opt, Deep_Verify_Horizon);
                        if Unbounded then
                           Budget := Unbounded_Verify_Budget_Ms;
                        else
                           Budget := Integer'Min (8000, (Remaining * 4) / 5);
                        end if;
                     end if;
                  end;
               end if;

               declare
                  R : Tactical_Search.Verify_Result;
               begin
                  R := Tactical_Search.Verify
                    (White_To_Move      => Is_White_To_Move,
                     Chosen_From        => Best_From,
                     Chosen_To          => Best_To,
                     Chosen_Promo       => Promo_Of (Best_From, Best_To),
                     Budget_Ms          => Budget,
                     Max_Depth          => Depth_Cap,
                     Margin_Cp          => Verify_Margin_Opt,
                     Report_Progress    => True,
                     Searchmoves_Filter => Pending_Searchmoves,
                     Mate_Target        => Pending_Mate_Target);
                  Last_Verify_Used := R.Valid;
                  if R.Valid and then R.Replaced
                    and then not Chose_Trap
                    and then R.Best.From in 1 .. 64
                    and then R.Best.To in 1 .. 64
                  then
                     if Search_Integration.Trace_Root_Decisions then
                        Put_Line ("info string [root-trace] Stage7 VERIFY replaced " &
                                  Move_To_String (Best_From, Best_To, 0) & " -> " &
                                  Move_To_String (R.Best.From, R.Best.To, R.Best.Promo)
                                  & " (chosen=" & Integer'Image (R.Chosen_Score)
                                  & " best=" & Integer'Image (R.Best_Score)
                                  & " depth" & Integer'Image (R.Depth) & ")");
                     end if;
                     Best_From  := R.Best.From;
                     Best_To    := R.Best.To;
                     Best_Promo := (if R.Best.Promo /= 0 then R.Best.Promo
                                    else Promo_Of (Best_From, Best_To));
                  end if;
               exception
                  when others =>
                     Last_Verify_Used := False;
                     null; --  verification is additive: on any error keep the move
               end;
            end if;
         end;
      end if;

      --  Enforce `go searchmoves` restriction even when verification did not run.
      if Pending_Searchmoves.N > 0
        and then not In_Pending_Searchmoves (Best_From, Best_To, Best_Promo)
      then
         Best_From  := Pending_Searchmoves.V (1).From;
         Best_To    := Pending_Searchmoves.V (1).To;
         Best_Promo := Pending_Searchmoves.V (1).Promo;
      end if;

      --  Legality assert (L2): the chosen move MUST be in Root_Candidates.
      if Best_From /= 0 and then Root_Candidates.Count > 0 then
         declare
            Is_Legal_Candidate : Boolean := False;
         begin
            for I in 1 .. Root_Candidates.Count loop
               if Root_Candidates.Candidates (I).From_Sq = Best_From
                 and then Root_Candidates.Candidates (I).To_Sq = Best_To
               then
                  Is_Legal_Candidate := True;
                  exit;
               end if;
            end loop;

            if not Is_Legal_Candidate then
               Put_Line ("info string L2 legality assert failed for move "
                         & Move_To_String (Best_From, Best_To, 0)
                         & "; falling back to legal candidate");
               Best_From := 0; Best_To := 0;
               for I in 1 .. Root_Candidates.Count loop
                  declare
                     C : Search_Integration.Root_Candidate renames
                           Root_Candidates.Candidates (I);
                  begin
                     if Best_From = 0 and then Move_Is_Safe (C.From_Sq, C.To_Sq) then
                        Best_From := C.From_Sq;
                        Best_To   := C.To_Sq;
                        exit;
                     end if;
                  end;
               end loop;
               if Best_From = 0 then
                  Best_From := Root_Candidates.Candidates (1).From_Sq;
                  Best_To   := Root_Candidates.Candidates (1).To_Sq;
               end if;
            end if;
         end;
      end if;

      --  Preserve an explicit promotion selected by any stage (including a
      --  verifier underpromotion); auto-queen only when no piece was chosen.
      if Best_From in 1 .. 64
        and then abs Pvalidade.Tabuleiro (Best_From) = 1
        and then (Move_Validation.Rank_Of (Best_To) = 1
                  or else Move_Validation.Rank_Of (Best_To) = 8)
      then
         if Best_Promo not in 3 | 4 | 7 | 20 then
            Best_Promo := 20;
         end if;
      else
         Best_Promo := 0;
      end if;
      Search_Integration.Trace_Decision
        ("Root_Choice", Best_From, Best_To, Best_Promo, "Final root arbitration complete");
   end Compute_Best_Move;

   function Try_Parse_Integer (S : String; Value : out Integer) return Boolean is
   begin
      Value := Integer'Value (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));
      return True;
   exception
      when others =>
         Value := 0;
         return False;
   end Try_Parse_Integer;

   procedure Handle_Setoption (Cmd : String) is
      Low_Cmd   : constant String := Ada.Characters.Handling.To_Lower (Cmd);
      Name_Pos  : constant Integer := Ada.Strings.Fixed.Index (Low_Cmd, "name ");
      Value_Pos : constant Integer := Ada.Strings.Fixed.Index (Low_Cmd, " value ");
   begin
      if Name_Pos = 0 then
         return;
      end if;

      declare
         Opt_Name : constant String :=
           (if Value_Pos > 0
            then Trimmed (Cmd (Name_Pos + 5 .. Value_Pos - 1))
            else Trimmed (Cmd (Name_Pos + 5 .. Cmd'Last)));
         Norm_Name : constant String := Ada.Characters.Handling.To_Lower (Opt_Name);
         Opt_Value : constant String :=
           (if Value_Pos > 0
            then Trimmed (Cmd (Value_Pos + 7 .. Cmd'Last))
            else "");
      begin
         if Norm_Name = "hash" then
            declare
               MB : Integer;
            begin
               if Try_Parse_Integer (Opt_Value, MB) then
                  if MB < TT_Table.Min_Size_MB then MB := TT_Table.Min_Size_MB; end if;
                  if MB > TT_Table.Max_Size_MB then MB := TT_Table.Max_Size_MB; end if;
                  TT_Table.Resize_TT (MB);
                  if TT_Table.Current_Size_MB /= MB then
                     Put_Line ("info string Hash resize to" & Integer'Image (MB) &
                               " MB failed; actual Hash =" &
                               Integer'Image (TT_Table.Current_Size_MB) & " MB");
                     if TT_Table.Current_Size_MB >= TT_Table.Min_Size_MB then
                        Tactical_Search.Set_Hash_MB (TT_Table.Current_Size_MB);
                     end if;
                  else
                     Tactical_Search.Set_Hash_MB (MB);
                  end if;
               else
                  Put_Line ("info string ignored malformed Hash value: " & Opt_Value);
               end if;
            end;
         elsif Norm_Name = "clear hash" or else Norm_Name = "clear_hash" then
            TT_Table.Clear_TT;
            Tactical_Search.Clear_TT;
         elsif Norm_Name = "move overhead" or else Norm_Name = "move_overhead" then
            declare
               Val : Integer;
            begin
               if Try_Parse_Integer (Opt_Value, Val) then
                  Time_Management.Set_Move_Overhead (Val);
               else
                  Put_Line ("info string ignored malformed Move Overhead value: " & Opt_Value);
               end if;
            end;
         elsif Norm_Name = "castle_bonus"
           or else Norm_Name = "development_bonus"
           or else Norm_Name = "queen_tempo_penalty"
           or else Norm_Name = "central_pawn_bonus"
           or else Norm_Name = "defended_piece_bonus"
           or else Norm_Name = "mobility_weight"
         then
            declare
               Val : Integer;
            begin
               if Try_Parse_Integer (Opt_Value, Val) then
                  Search_Integration.Set_Heuristic_Option (Norm_Name, Val);
               else
                  Put_Line ("info string ignored malformed option value: " & Opt_Value);
               end if;
            end;
         elsif Norm_Name = "trace_root_decisions" then
            declare
               Low_Val : constant String := Ada.Characters.Handling.To_Lower (Opt_Value);
            begin
               if Low_Val = "true" or else Low_Val = "1" then
                  Search_Integration.Trace_Root_Decisions := True;
               elsif Low_Val = "false" or else Low_Val = "0" then
                  Search_Integration.Trace_Root_Decisions := False;
               else
                  Put_Line ("info string ignored malformed option value: " & Opt_Value);
               end if;
            end;
         elsif Norm_Name = "verify_depth" or else Norm_Name = "verify_margin" then
            declare
               Val     : Integer;
               Max_Val : constant Integer :=
                 (if Norm_Name = "verify_depth" then Max_Verify_Depth
                  else Max_Verify_Margin);
            begin
               if Try_Parse_Integer (Opt_Value, Val) then
                  Val := Integer'Max (0, Integer'Min (Max_Val, Val));
                  if Norm_Name = "verify_depth" then
                     Verify_Depth_Opt := Val;
                  else
                     Verify_Margin_Opt := Val;
                  end if;
               else
                  Put_Line ("info string ignored malformed option value: " & Opt_Value);
               end if;
            end;
         end if;
      end;
   end Handle_Setoption;

   procedure Report_Uci_Options is
   begin
      Put_Line ("id name Prechess UCI 0.9.9.17.34");
      Put_Line ("id author Strapasson Jose Lauro, Legacy 0.7.8 and Arthur Matheus further releases");
      Put_Line
        ("option name Hash type spin default"
         & Integer'Image (TT_Table.Default_Size_MB)
         & " min" & Integer'Image (TT_Table.Min_Size_MB)
         & " max" & Integer'Image (TT_Table.Max_Size_MB));
      Put_Line ("option name Clear Hash type button");
      Put_Line
        ("option name Move Overhead type spin default"
         & Integer'Image (Time_Management.Default_Move_Overhead_Ms)
         & " min" & Integer'Image (Time_Management.Min_Move_Overhead_Ms)
         & " max" & Integer'Image (Time_Management.Max_Move_Overhead_Ms));
      Put_Line ("option name Castle_Bonus type spin default 80 min 0 max 300");
      Put_Line ("option name Development_Bonus type spin default 40 min 0 max 200");
      Put_Line ("option name Queen_Tempo_Penalty type spin default 60 min 0 max 300");
      Put_Line ("option name Central_Pawn_Bonus type spin default 50 min 0 max 250");
      Put_Line ("option name Defended_Piece_Bonus type spin default 25 min 0 max 150");
      Put_Line ("option name Mobility_Weight type spin default 10 min 0 max 100");
      Put_Line ("option name Trace_Root_Decisions type check default false");
      Put_Line ("option name Verify_Depth type spin default 8 min 0 max 20");
      Put_Line
        ("option name Verify_Margin type spin default"
         & Integer'Image (Tactical_Search.Veto_Margin_Cp)
         & " min 0 max" & Integer'Image (Max_Verify_Margin));
      Put_Line ("uciok");
      Flush (Standard_Output);
   end Report_Uci_Options;

   ----------------------------------------------------------------------------
   --  SEARCH CONTROL & ASYNC SEARCH WORKER (ZOE TIER 1 - GATES P2, P3, P4)
   ----------------------------------------------------------------------------
   protected Search_Control is
      procedure Start_Search (Is_Infinite : Boolean; Is_Ponder : Boolean := False);
      procedure Request_Stop;
      procedure Request_Quit;
      procedure Clear_Ponder;
      procedure Worker_Finished;
      function Is_Searching return Boolean;
      function Is_Infinite return Boolean;
      function Is_Pondering return Boolean;
      function Stop_Requested return Boolean;
      function Quit_Requested return Boolean;
      entry Wait_Search_Done;
   private
      Searching     : Boolean := False;
      Infinite_Mode : Boolean := False;
      Ponder_Mode   : Boolean := False;
      Stop_Flag     : Boolean := False;
      Quit_Flag     : Boolean := False;
   end Search_Control;

   protected body Search_Control is
      procedure Start_Search (Is_Infinite : Boolean; Is_Ponder : Boolean := False) is
      begin
         Searching     := True;
         Infinite_Mode := Is_Infinite;
         Ponder_Mode   := Is_Ponder;
         Stop_Flag     := False;
         Quit_Flag     := False;
      end Start_Search;

      procedure Request_Stop is
      begin
         Stop_Flag := True;
         Ponder_Mode := False;
         Time_Management.Stop_Search;
      end Request_Stop;

      procedure Request_Quit is
      begin
         Quit_Flag := True;
         Ponder_Mode := False;
         Time_Management.Stop_Search;
      end Request_Quit;

      procedure Clear_Ponder is
      begin
         Ponder_Mode := False;
         --  Ponderhit arrives for an active ponder search; stop any infinite
         --  hold so Execute_Search emits bestmove promptly.
         Time_Management.Stop_Search;
      end Clear_Ponder;

      procedure Worker_Finished is
      begin
         Searching   := False;
         Ponder_Mode := False;
      end Worker_Finished;

      function Is_Searching return Boolean is (Searching);
      function Is_Infinite return Boolean is (Infinite_Mode);
      function Is_Pondering return Boolean is (Ponder_Mode);
      function Stop_Requested return Boolean is (Stop_Flag);
      function Quit_Requested return Boolean is (Quit_Flag);

      entry Wait_Search_Done when not Searching is
      begin
         null;
      end Wait_Search_Done;
   end Search_Control;

   procedure Execute_Search (Infinite : Boolean) is
      Best_From, Best_To, Best_Promo : Integer := 0;
   begin
      TT_Table.New_Generation;
      Compute_Best_Move (Best_From, Best_To, Best_Promo);
      Time_Management.Restore_Time_Slice;

      --  When verification ran, Verify has already emitted every completed
      --  iteration. Otherwise use the legacy final line and scratch PV.
      if not Last_Verify_Used
        and then Best_From /= 0 and then Best_To /= 0
      then
         Search_Integration.Report_UCI (Best_From, Best_To);
      end if;

      --  Extend principal variation along scratch continuation lines.
      if Best_From /= 0
        and then Best_To /= 0
        and then not Last_Verify_Used
        and then not Search_Control.Stop_Requested
        and then not Search_Control.Quit_Requested
      then
         declare
            Max_Ext        : constant := 16;
            Saved_Board    : Pvalidade.Board_Array := [others => 0];
            Saved_Contagem : constant Integer := pprechess2.Contagem_Empate;
            Saved_Ep       : constant Integer := Move_Validation.En_Passant_Sq;
            Saved_WK       : constant Boolean := Move_Validation.White_Castling_K;
            Saved_WQ       : constant Boolean := Move_Validation.White_Castling_Q;
            Saved_BK       : constant Boolean := Move_Validation.Black_Castling_K;
            Saved_BQ       : constant Boolean := Move_Validation.Black_Castling_Q;
            White_Turn     : Boolean := Is_White_To_Move;
            Root_M_Str     : constant String := Move_To_String (Best_From, Best_To, Best_Promo);
            PV_Buf         : String (1 .. 512) := [others => ' '];
            PV_Len         : Natural := 0;
            Ply_Score       : Integer;
            Post_Root_Score : Integer := 0;
            History_Keys    : array (0 .. Max_Ext) of TT_Types.Hash_Key := [others => 0];
            History_Count   : Natural := 0;
            PV_Start_Time   : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
            Max_PV_Span     : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Milliseconds (50);

            procedure Restore_State is
            begin
               Pvalidade.Tabuleiro := Saved_Board;
               pprechess2.Contagem_Empate := Saved_Contagem;
               Move_Validation.En_Passant_Sq := Saved_Ep;
               Move_Validation.White_Castling_K := Saved_WK;
               Move_Validation.White_Castling_Q := Saved_WQ;
               Move_Validation.Black_Castling_K := Saved_BK;
               Move_Validation.Black_Castling_Q := Saved_BQ;
               Search_Integration.Suppress_Info := False;
            end Restore_State;

         begin
            PV_Len := Natural'Min (PV_Buf'Length, Root_M_Str'Length);
            PV_Buf (1 .. PV_Len) := Root_M_Str (Root_M_Str'First .. Root_M_Str'First + PV_Len - 1);
            Saved_Board := Pvalidade.Tabuleiro;
            Search_Integration.Suppress_Info := True;

            Apply_Scratch (Best_From, Best_To, Best_Promo);
            if Move_Validation.Is_In_Check (White_King => not Is_White_To_Move) then
               declare
                  Opp_Moves : Move_Gen.Move_List;
               begin
                  Move_Gen.Generate_Legal_Moves (not Is_White_To_Move, Opp_Moves);
                  if Opp_Moves.N = 0 then
                     Post_Root_Score := Search_Integration.Mate_Value - 1;
                  else
                     Post_Root_Score := Search_Integration.Evaluate;
                     if not Is_White_To_Move then
                        Post_Root_Score := -Post_Root_Score;
                     end if;
                  end if;
               end;
            else
               Post_Root_Score := Search_Integration.Evaluate;
               if not Is_White_To_Move then
                  Post_Root_Score := -Post_Root_Score;
               end if;
            end if;
            White_Turn := not White_Turn;
            History_Keys (0) := Search_Integration.Root_Position_Key (White_Turn);
            History_Count := 0;

            for K in 1 .. Max_Ext loop
               exit when Search_Control.Stop_Requested
                 or else Search_Control.Quit_Requested
                 or else (Ada.Real_Time.Clock - PV_Start_Time > Max_PV_Span);
               declare
                  F, T, Promo : Integer;
                  Chosen_Net_Cp : Integer := 0;
                  Key : constant TT_Types.Hash_Key :=
                    Search_Integration.Root_Position_Key (White_Turn);
                  Cached : TT_Types.TT_Entry;
                  Hit    : constant Boolean := TT_Table.Probe_TT (Key, Cached);
               begin
                  declare
                     Legal_List : Move_Gen.Move_List;
                     Best_Score : Integer := -999999;
                     Score      : Integer;
                     Gain       : Integer;
                     After_See  : Integer;
                     Net_Cp     : Integer;
                     Phase      : constant Integer := pprechess2.Positional_Game_Phase;
                     Piece_Code : Integer;
                     Dst_Sq     : Integer;
                     Found_Move : Boolean := False;
                  begin
                     Move_Gen.Generate_Legal_Moves (White_Turn, Legal_List);
                     if Legal_List.N = 0 then
                        exit;
                     end if;

                     for I in 1 .. Legal_List.N loop
                        declare
                           M : Move_Gen.Move_Rec renames Legal_List.V (I);
                        begin
                           Piece_Code := abs Pvalidade.Tabuleiro (M.From);
                           Dst_Sq     := (if White_Turn then M.To else Move_Validation.Mirror_Square (M.To));
                           --  S-G2-1: SEE gain for every move incl. en passant
                           Gain       := Search_Integration.See_Gain (White_Turn, M.From, M.To);
                           After_See  := Search_Integration.Max_Opponent_See_After (White_Turn, M.From, M.To);
                           Net_Cp     := Gain - After_See;

                           if Net_Cp < 0 then
                              --  B-M1: Unsound / net-losing move heavily penalised so it never
                              --  outscores a safe move or non-losing trade in display PV.
                              Score := -50000 + Net_Cp * 10;
                           else
                              --  Net non-negative: scored by net material gain + positional terms.
                              Score := Net_Cp * 100 + pprechess2.Positional_Test_Score (Piece_Code, Dst_Sq, Phase);
                              --  Castling bonus (retaining hang check above; castle exemption removed)
                              if Piece_Code = 999 and then abs (M.To - M.From) = 2 then
                                 Score := Score + 150;
                              end if;
                              --  Prefer matching TT entry if safe (cache bypass exemption removed)
                              if Hit and then M.From = Cached.Best.From_Sq and then M.To = Cached.Best.To_Sq then
                                 Score := Score + 50;
                              end if;
                           end if;

                           if Score > Best_Score then
                              Best_Score    := Score;
                              F             := M.From;
                              T             := M.To;
                              Promo         := M.Promo;
                              Chosen_Net_Cp := Net_Cp;
                              Found_Move    := True;
                           end if;
                        end;
                     end loop;

                     if not Found_Move then
                        exit;
                     end if;
                  end;
                  Apply_Scratch (F, T, Promo);
                  declare
                     M_Text : constant String := Move_To_String (F, T, Promo);
                  begin
                     if PV_Len + 1 + M_Text'Length <= PV_Buf'Length then
                        PV_Len := PV_Len + 1;
                        PV_Buf (PV_Len) := ' ';
                        PV_Buf (PV_Len + 1 .. PV_Len + M_Text'Length) := M_Text;
                        PV_Len := PV_Len + M_Text'Length;
                     end if;
                  end;
                  White_Turn := not White_Turn;

                   --  Reported score: checkmate delivered at ply 1 + K,
                   --  otherwise preserve Post_Root_Score anchoring invariant.
                   if Move_Validation.Is_In_Check (White_King => White_Turn) then
                      declare
                         Opp_Moves : Move_Gen.Move_List;
                      begin
                         Move_Gen.Generate_Legal_Moves (White_Turn, Opp_Moves);
                         if Opp_Moves.N = 0 and then not Search_Integration.Has_Any_Legal_Move (White_Turn) then
                            --  Checkmate delivered at ply 1 + K along scratch line.
                            --  Scratch PV is a single speculative line, not a verified minimax tree.
                            --  Clamp below Mate_Threshold (2500 cp) to eliminate false mate claims to GUI.
                            if (not White_Turn) = Is_White_To_Move then
                               Ply_Score := 2500;
                            else
                               Ply_Score := -2500;
                            end if;
                         else
                            --  S-G2-2: Score follows the line with opponent-ply sign flip
                            Ply_Score := Post_Root_Score
                              + (if (not White_Turn) = Is_White_To_Move then Chosen_Net_Cp else -Chosen_Net_Cp);
                         end if;
                      end;
                   else
                      --  S-G2-2: Score follows the line with opponent-ply sign flip
                      Ply_Score := Post_Root_Score
                        + (if (not White_Turn) = Is_White_To_Move then Chosen_Net_Cp else -Chosen_Net_Cp);
                   end if;

                   --  Task 0: Depth => 3 + K, Seldepth => 60 + K: monotonic depth labels for the
                   --  scratch PV extension plies (extending past the nominal 3-ply cascade, depth 4..19, seldepth 61..76).
                   Search_Integration.Report_PV
                     (Depth    => 3 + K,
                      Seldepth => 60 + K,
                      Score_Cp => Ply_Score,
                      PV       => PV_Buf (1 .. PV_Len));

                  declare
                     New_Key : constant TT_Types.Hash_Key :=
                       Search_Integration.Root_Position_Key (White_Turn);
                     Repetition : Boolean := False;
                  begin
                     History_Count := History_Count + 1;
                     History_Keys (History_Count) := New_Key;
                     for H in 0 .. History_Count - 1 loop
                        if TT_Types."=" (History_Keys (H), New_Key) then
                           Repetition := True;
                           exit;
                        end if;
                     end loop;
                     exit when Repetition;
                  end;
               end;
            end loop;

            Restore_State;
         exception
            when others =>
               Restore_State;
         end;
      end if;

      --  In infinite or ponder mode, wait cooperatively until stop, ponderhit, or quit.
      if Infinite or else Search_Control.Is_Pondering then
         while (Infinite or else Search_Control.Is_Pondering)
           and then not Search_Control.Stop_Requested
           and then not Search_Control.Quit_Requested
         loop
            delay 0.005;
         end loop;
      end if;

      --  UCI protocol: emit bestmove unless quit was requested without a preceding stop.
      if not Search_Control.Quit_Requested or else Search_Control.Stop_Requested then
         if Best_From = 0 and then Best_To = 0 then
            Put_Line ("bestmove 0000");
         else
            Put_Line ("bestmove " & Move_To_String (Best_From, Best_To, Best_Promo));
            --  0.9.9.17.9: remember our own quiet reversible move for the
            --  anti-shuffle arbitration (Stage 6.5). Deduped by
            --  Record_Game_Move against repeated "go" on the same position.
            if Quiet_Reversible_Move (Best_From, Best_To, Best_Promo) then
               Record_Game_Move (Best_From, Best_To,
                                 abs Pvalidade.Tabuleiro (Best_From),
                                 Is_White_To_Move);
            end if;
         end if;
         Flush (Standard_Output);
      end if;

      Search_Control.Worker_Finished;
   exception
      when E : others =>
         --  0.9.9.17.20: a GUI that received no reply would wait (and may
         --  forfeit on time). Always terminate the go with a legal sentinel.
         Time_Management.Restore_Time_Slice;
         Put_Line ("info string search error: " & Ada.Exceptions.Exception_Information (E));
         Put_Line ("bestmove 0000");
         Flush (Standard_Output);
         Search_Control.Worker_Finished;
   end Execute_Search;

   task Search_Worker with Storage_Size => 4 * 1024 * 1024 is
      entry Start (Infinite_Mode : Boolean);
      entry Shutdown;
   end Search_Worker;

   task body Search_Worker is
      Local_Infinite : Boolean;
   begin
      loop
         select
            accept Start (Infinite_Mode : Boolean) do
               Local_Infinite := Infinite_Mode;
            end Start;

            begin
               Execute_Search (Local_Infinite);
            exception
               when E : others =>
                  Time_Management.Restore_Time_Slice;
                  Put_Line ("info string search error: " & Ada.Exceptions.Exception_Information (E));
                  Put_Line ("bestmove 0000");
                  Flush (Standard_Output);
                  Search_Control.Worker_Finished;
            end;
         or
            accept Shutdown;
            exit;
         end select;
      end loop;
   end Search_Worker;

   procedure Handle_Go (Cmd : String) is
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer := 0;
      Nodes_Limit     : Long_Long_Integer := 0;
      Perft_Depth     : Integer := -1;
      Max_Perft_Depth : constant Integer := 6;
      Infinite        : Boolean := False;
      Ponder          : Boolean := False;
      Pos             : Integer := Cmd'First + 2;

      function Next_Token (Tok_Start, Tok_End : out Integer) return Boolean is
      begin
         Tok_Start := Ada.Strings.Fixed.Index_Non_Blank (Cmd (Pos .. Cmd'Last));
         if Tok_Start = 0 then
            Tok_End := 0;
            return False;
         end if;
         Tok_End := Ada.Strings.Fixed.Index (Cmd (Tok_Start .. Cmd'Last), " ");
         if Tok_End = 0 then
            Tok_End := Cmd'Last;
            Pos := Cmd'Last + 1;
         else
            Pos := Tok_End + 1;
            Tok_End := Tok_End - 1;
         end if;
         return True;
      end Next_Token;

      function Get_Next_Int return Integer is
         TS, TE, Val : Integer;
      begin
         if Next_Token (TS, TE) then
            if Try_Parse_Integer (Cmd (TS .. TE), Val) then
               return Val;
            end if;
         end if;
         return 0;
      end Get_Next_Int;

      function Get_Next_Nodes return Long_Long_Integer is
         TS, TE : Integer;
      begin
         if Next_Token (TS, TE) then
            declare
               Tok : constant String := Cmd (TS .. TE);
               Val : Long_Long_Integer;
            begin
               Val := Long_Long_Integer'Value (Tok);
               if Val > 0 then
                  return Val;
               else
                  Put_Line ("info string go nodes ignored: " & Tok);
               end if;
            exception
               when others =>
                  Put_Line ("info string go nodes ignored: " & Tok);
            end;
         end if;
         return 0;
      end Get_Next_Nodes;

      procedure Parse_Searchmoves is
         Legal_List : Move_Gen.Move_List;
         TS, TE     : Integer;
         F, T, P    : Integer;
         Saved_Pos  : Integer;
      begin
         Move_Gen.Generate_Legal_Moves (Is_White_To_Move, Legal_List);
         loop
            Saved_Pos := Pos;
            exit when not Next_Token (TS, TE);
            declare
               Tok : constant String := Ada.Characters.Handling.To_Lower (Cmd (TS .. TE));
            begin
               if Tok = "wtime" or else Tok = "btime" or else Tok = "winc"
                 or else Tok = "binc" or else Tok = "movestogo"
                 or else Tok = "movetime" or else Tok = "depth"
                 or else Tok = "nodes" or else Tok = "mate"
                 or else Tok = "infinite" or else Tok = "ponder"
                 or else Tok = "perft" or else Tok = "searchmoves"
               then
                  Pos := Saved_Pos;
                  exit;
               end if;
               if UCI_Token_Squares (Tok, F, T) then
                  P := 0;
                  if Tok'Length = 5 then
                     case Tok (Tok'Last) is
                        when 'q' => P := 20;
                        when 'r' => P := 7;
                        when 'b' => P := 3;
                        when 'n' => P := 4;
                        when others => P := -1;
                     end case;
                  end if;
                  if P >= 0 then
                     for I in 1 .. Legal_List.N loop
                        if Legal_List.V (I).From = F
                          and then Legal_List.V (I).To = T
                          and then (P = 0 or else Legal_List.V (I).Promo = P)
                        then
                           if Pending_Searchmoves.N < Move_Gen.Max_Moves then
                              Pending_Searchmoves.N := Pending_Searchmoves.N + 1;
                              Pending_Searchmoves.V (Pending_Searchmoves.N) :=
                                (From => F, To => T, Promo => P);
                           end if;
                           exit;
                        end if;
                     end loop;
                  end if;
               end if;
            end;
         end loop;
      end Parse_Searchmoves;
   begin
      if Search_Control.Is_Searching then
         Put_Line ("info string search already in progress");
         Flush (Standard_Output);
         return;
      end if;

      Pending_Searchmoves := Tactical_Search.Empty_Move_List;
      Pending_Mate_Target := 0;

      declare
         TS, TE : Integer;
      begin
         while Next_Token (TS, TE) loop
            declare
               Tok : constant String := Ada.Characters.Handling.To_Lower (Cmd (TS .. TE));
            begin
               if Tok = "wtime" then WTime := Get_Next_Int;
               elsif Tok = "btime" then BTime := Get_Next_Int;
               elsif Tok = "winc" then WInc := Get_Next_Int;
               elsif Tok = "binc" then BInc := Get_Next_Int;
               elsif Tok = "movestogo" then Moves_To_Go := Get_Next_Int;
               elsif Tok = "movetime" then Move_Time := Get_Next_Int;
               elsif Tok = "depth" then Depth := Get_Next_Int;
               elsif Tok = "nodes" then Nodes_Limit := Get_Next_Nodes;
               elsif Tok = "mate" then
                  Pending_Mate_Target := Natural'Max (0, Get_Next_Int);
               elsif Tok = "infinite" then Infinite := True;
               elsif Tok = "perft" then Perft_Depth := Get_Next_Int;
               elsif Tok = "ponder" then Ponder := True;
               elsif Tok = "searchmoves" then Parse_Searchmoves;
               end if;
            end;
         end loop;
      end;

      if Perft_Depth >= 0 then
         if Perft_Depth > Max_Perft_Depth then
            Put_Line ("info string perft depth too large; max is"
                      & Integer'Image (Max_Perft_Depth));
            Flush (Standard_Output);
            return;
         elsif Perft_Depth = 0 then
            Put_Line ("perft 0 1");
            Flush (Standard_Output);
            return;
         else
            Move_Gen.Perft_Divide (Perft_Depth, Is_White_To_Move);
            Flush (Standard_Output);
            return;
         end if;
      end if;

      if Search_Integration.Is_Draw then
         Put_Line ("info string position is drawn under FIDE rules "
                   & "(repetition, 50-move or dead position); playing on");
      end if;

      TT_Types.Nodes_Searched := 0;

      --  When pondering (`go ponder`), never let clock budget exit before `stop` or `ponderhit`.
      Time_Management.Start_Search
        (WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth,
         Is_White_To_Move, Infinite or else Ponder, Nodes_Limit);

      Search_Control.Start_Search (Infinite, Ponder);
      Search_Worker.Start (Infinite);
   end Handle_Go;

   procedure Print_Ascii_Board is
   begin
      Put_Line (" +---+---+---+---+---+---+---+---+");
      for R in reverse 1 .. 8 loop
         Ada.Text_IO.Put (Integer'Image (R) (2 .. 2) & " |");
         for F in 1 .. 8 loop
            declare
               Sq : constant Integer := Move_Validation.Square_Of (R, F);
               P  : constant Integer := Pvalidade.Tabuleiro (Sq);
               Ch : Character := '.';
            begin
               case P is
                  when 1      => Ch := 'P';
                  when 4      => Ch := 'N';
                  when 3      => Ch := 'B';
                  when 7      => Ch := 'R';
                  when 20     => Ch := 'Q';
                  when 999    => Ch := 'K';
                  when -1     => Ch := 'p';
                  when -4     => Ch := 'n';
                  when -3     => Ch := 'b';
                  when -7     => Ch := 'r';
                  when -20    => Ch := 'q';
                  when -999   => Ch := 'k';
                  when others => Ch := '.';
               end case;
               Ada.Text_IO.Put (" " & Ch & " |");
            end;
         end loop;
         Ada.Text_IO.New_Line;
         Put_Line (" +---+---+---+---+---+---+---+---+");
      end loop;
      Put_Line ("   a   b   c   d   e   f   g   h");
      Put_Line ("Turn: " & (if Is_White_To_Move then "White" else "Black"));
      Put_Line ("Castling: "
                & (if Move_Validation.White_Castling_K then "K" else "")
                & (if Move_Validation.White_Castling_Q then "Q" else "")
                & (if Move_Validation.Black_Castling_K then "k" else "")
                & (if Move_Validation.Black_Castling_Q then "q" else ""));
      Put_Line ("En Passant: " & Integer'Image (Move_Validation.En_Passant_Sq));
   end Print_Ascii_Board;

   procedure Print_Legal_Moves is
      List : Move_Gen.Move_List;
   begin
      Move_Gen.Generate_Legal_Moves (Is_White_To_Move, List);
      Put ("Legal moves (" & Integer'Image (List.N) & " ): ");
      for I in 1 .. List.N loop
         Put (Move_To_String (List.V (I).From, List.V (I).To, List.V (I).Promo) & " ");
      end loop;
      New_Line;
   end Print_Legal_Moves;

   procedure Print_Help is
   begin
      Put_Line ("Prechess UCI Commands:");
      Put_Line ("  uci                     - Initialize engine & list options");
      Put_Line ("  isready                 - Synchronize with GUI");
      Put_Line ("  ucinewgame              - Reset game state & transposition table");
      Put_Line ("  setoption name <n> value <v> - Configure engine options");
      Put_Line ("  position [startpos|fen <f>] [moves <m1> ...] - Set board state");
      Put_Line ("  go [wtime <w>] [btime <b>] [winc <wi>] [binc <bi>] [movestogo <m>]");
      Put_Line ("     [movetime <t>] [depth <d>] [infinite] [perft <d>] - Start search");
      Put_Line ("  stop                    - Interrupt search and return best move");
      Put_Line ("  quit                    - Exit engine");
      Put_Line ("Custom Diagnostic Commands:");
      Put_Line ("  board                   - Display 8x8 ASCII board representation");
      Put_Line ("  moves                   - Enumerate all legal moves from position");
      Put_Line ("  help                    - Display this command reference");
   end Print_Help;

   procedure Shutdown_Active_Search is
   begin
      if Search_Control.Is_Searching then
         Search_Control.Request_Quit;
         Search_Control.Wait_Search_Done;
      end if;
   end Shutdown_Active_Search;

begin
   TT_Table.Init_TT (TT_Table.Default_Size_MB);
   Tactical_Search.Set_Hash_MB (TT_Table.Default_Size_MB);
   if not Search_Integration.Try_Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      Is_White_To_Move)
   then
      raise Program_Error;
   end if;
   pprechess2.Contagem_Empate := 0;

   loop
      begin
         Get_Line (Line, Last);
         if Last = Line'Last and then not End_Of_File then
            if not End_Of_Line then
               --  Drain overlong input via Skip_Line without touching the next command line.
               Put_Line ("info string truncated overlong input line (> 65536 chars)");
               Flush (Standard_Output);
               Skip_Line;
               Last := 0;
            else
               --  Exact Line'Last length: consume the trailing line terminator cleanly.
               Skip_Line;
            end if;
         end if;
      exception
         when End_Error =>
            Shutdown_Active_Search;
            Search_Worker.Shutdown;
            exit;
      end;
      if Last = 0 and then End_Of_File then
         Shutdown_Active_Search;
         Search_Worker.Shutdown;
         exit;
      end if;

      declare
         Normalized : constant String := Normalize_UCI_Line (Line (1 .. Last));
         Input      : constant String := Strip_Unknown_Leading_Tokens (Normalized);
      begin
         if Input = "" then
            null;
         elsif Input = "uci" then
            Report_Uci_Options;
         elsif Input = "debug on" then
            Debug_Mode := True;
            Put_Line ("info string debug mode enabled");
            Flush (Standard_Output);
         elsif Input = "debug off" then
            Debug_Mode := False;
         elsif Input = "register"
           or else (Input'Length > 9
                    and then Input (Input'First .. Input'First + 8) = "register ")
         then
            if Debug_Mode then
               Put_Line ("info string registration accepted");
               Flush (Standard_Output);
            end if;
         elsif Input = "isready" then
            Put_Line ("readyok");
            Flush (Standard_Output);
         elsif Input = "ucinewgame" then
            if Search_Control.Is_Searching then
               Put_Line ("info string command ignored: search active");
            else
               TT_Table.Clear_TT;
               Tactical_Search.Clear_TT;
               Search_Integration.Reset_Game;
               if not Search_Integration.Try_Parse_FEN
                 ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                  Is_White_To_Move)
               then
                  raise Program_Error;
               end if;
               Reset_Game_Moves;
               pprechess2.Contagem_Empate := 0;
            end if;
         elsif Input = "setoption"
           or else (Input'Length > 10
                    and then Input (Input'First .. Input'First + 9) = "setoption ")
         then
            if Search_Control.Is_Searching then
               Put_Line ("info string command ignored: search active");
            else
               Handle_Setoption (Input);
            end if;
         elsif Input = "position"
           or else (Input'Length > 9
                    and then Input (Input'First .. Input'First + 8) = "position ")
         then
            if Search_Control.Is_Searching then
               Put_Line ("info string command ignored: search active");
            else
               Handle_Position (Input);
            end if;
         elsif Input = "go"
           or else (Input'Length > 3
                    and then Input (Input'First .. Input'First + 2) = "go ")
         then
            Handle_Go (Input);
         elsif Input = "ponderhit" then
            if Search_Control.Is_Searching and then Search_Control.Is_Pondering then
               Search_Control.Clear_Ponder;
            end if;
         elsif Input = "board" then
            if Search_Control.Is_Searching then
               Put_Line ("info string command ignored: search active");
            else
               Print_Ascii_Board;
            end if;
         elsif Input = "moves" then
            if Search_Control.Is_Searching then
               Put_Line ("info string command ignored: search active");
            else
               Print_Legal_Moves;
            end if;
         elsif Input = "help" then
            Print_Help;
         elsif Input = "stop" then
            if Search_Control.Is_Searching then
               Search_Control.Request_Stop;
            end if;
         elsif Input = "quit" then
            Shutdown_Active_Search;
            Search_Worker.Shutdown;
            exit;
         end if;
      end;
   end loop;
end Prechess_UCI;
