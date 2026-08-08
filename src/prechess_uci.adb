with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Pvalidade;
with pprechess2;
with TT_Table;
with TT_Types;
with BCH_Hash;
with Time_Management;

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

   --  Set when "quit" (or stdin EOF) arrives during "go infinite": UCI
   --  requires the engine to exit immediately, emitting no bestmove.
   --  Handle_Go checks it to skip bestmove; the main loop checks it to
   --  terminate.
   Quit_Requested : Boolean := False;

   --  (The hardcoded opening book was removed from pprechess2; no
   --  book-eligibility tracking remains.)

   function Trimmed (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trimmed;

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
            Search_Integration.Make_Move_UCI
              (Moves_Str (Start_Pos .. Moves_Str'Last),
               Is_White_To_Move,
               Applied);
            if Applied then
               Is_White_To_Move := not Is_White_To_Move;
            end if;
            exit;
         else
            Search_Integration.Make_Move_UCI
              (Moves_Str (Start_Pos .. End_Pos - 1),
               Is_White_To_Move,
               Applied);
            if Applied then
               Is_White_To_Move := not Is_White_To_Move;
            end if;
            Start_Pos := End_Pos + 1;
         end if;
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
               if Moves_Idx > 0 then
                  Replay_Moves (Trimmed (Fen_Str (Moves_Idx + 7 .. Fen_Str'Last)));
               end if;
            end if;
         end;
      end if;

   end Handle_Position;

   function Move_To_String (From_Sq, To_Sq, Promo : Integer) return String is
      F_File : constant Character := Character'Val (Character'Pos ('a') + Move_Validation.File_Of (From_Sq) - 1);
      F_Rank : constant Character := Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (From_Sq) - 1);
      T_File : constant Character := Character'Val (Character'Pos ('a') + Move_Validation.File_Of (To_Sq) - 1);
      T_Rank : constant Character := Character'Val (Character'Pos ('1') + Move_Validation.Rank_Of (To_Sq) - 1);
      Promo_Char : constant String :=
        (case Promo is
            when 20 => "q",
            when 7  => "r",
            when 3  => "b",
            when 4  => "n",
            when others => "");
   begin
      return F_File & F_Rank & T_File & T_Rank & Promo_Char;
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
      if Promo = 20 then
         Pvalidade.Tabuleiro (T) := (if Piece > 0 then 20 else -20);
      else
         Pvalidade.Tabuleiro (T) := Piece;
      end if;
      Pvalidade.Tabuleiro (F) := 0;
   end Apply_Raw;

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
      Recap_Found            : Boolean;
      Recap_From, Recap_To   : Integer;
      MinorCap_Found         : Boolean;
      MinorCap_From, MinorCap_To : Integer;
      Trap_Found             : Boolean;
      Trap_From, Trap_To     : Integer;
      Tempo_Found            : Boolean;
      Tempo_From, Tempo_To   : Integer;
      Solid_Found            : Boolean;
      Solid_From, Solid_To   : Integer;
      Alt_Found              : Boolean;
      Alt_From, Alt_To       : Integer;
      EqCap_Found            : Boolean;
      EqCap_From, EqCap_To   : Integer;
      Chose_Winning_Capture  : Boolean := False;
      Chose_Root_Correction  : Boolean := False;
      Max_Vetoes  : constant := 8;
      First_From, First_To : Integer := 0;
      Saved_Board : array (1 .. 64) of Integer;
      No_Move     : Boolean := False;
      --  P14: the opponent's best SEE-positive reply on the board as
      --  Compute_Best_Move found it, before any candidate move is tried.
      --  Computed once here (the board is untouched at this point) rather
      --  than inside every Move_Is_Safe call, since it is the same figure
      --  regardless of which candidate move is being checked.
      Root_Before : constant Integer :=
        Search_Integration.Max_Opponent_See (Is_White_To_Move);

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

         pprechess2.Prechess2;

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
         Moved_Value    : constant Integer := abs Pvalidade.Tabuleiro (T);
         Enemy_White    : constant Boolean := not Is_White_To_Move;
         Attacker       : Integer;
         Saved_Attacker : Integer;
         Saved_Victim   : Integer;
         Gain           : Integer;
         Best_Gain      : Integer := 0;
      begin
         if Moved_Value <= 1 or else Moved_Value >= 999 then
            return False; -- pawn or king: not this veto's job
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
                  end if;
                  Pvalidade.Tabuleiro (Sq) := Saved_Attacker;
                  Pvalidade.Tabuleiro (T)  := Saved_Victim;
               end if;
            end if;
         end loop;
         return Best_Gain > Captured_Value;
      end Root_Piece_Hangs;

      --  P14 continued: Root_Piece_Hangs only looks at the square (T) the
      --  moved piece just landed on -- it cannot see a quiet move that
      --  leaves some OTHER piece hanging untouched (e.g. a knight already
      --  en prise elsewhere on the board that the chosen move neither
      --  relocates nor defends). Board-wide counterpart, called with the
      --  move already applied (Move_Is_Safe's convention): compare the
      --  opponent's best SEE-positive reply on the CURRENT (post-move)
      --  board against Before, the same figure on the board saved before
      --  the move. Flags the move only when the opponent's best reply is
      --  still at least as good as it was (After >= Before) and is worth
      --  at least a minor piece (After >= 3) -- so a move that reduces an
      --  unavoidable threat, even without eliminating it, is still
      --  accepted, but one that leaves an existing hang exactly as juicy
      --  (or worse) is not. Pawn-sized annoyances (After < 3) are left to
      --  Is_Soft_Defend / Best_En_Prise_Resolve elsewhere. General
      --  SEE-style logic -- no FEN/position special-casing.
      function Quiet_Move_Worsens_Material
        (Before : Integer; Captured_Value : Integer) return Boolean
      is
         After : Integer;
      begin
         if Captured_Value /= 0 then
            return False; -- real captures are not this check's job
         end if;
         After := Search_Integration.Max_Opponent_See (Is_White_To_Move);
         return After >= 3 and then After >= Before;
      end Quiet_Move_Worsens_Material;

      --  Apply the move on a scratch board, ask whether the opponent
      --  then has a forced mate within two -- or a SEE-positive net
      --  material win against the piece we just moved (Root_Piece_Hangs,
      --  P14) -- or leaves some other piece hanging at least as badly as
      --  before (Quiet_Move_Worsens_Material, P14) -- restore. Real
      --  coordinates.
      function Move_Is_Safe (F, T : Integer) return Boolean is
         Danger         : Boolean;
         Captured_Value : constant Integer := abs Pvalidade.Tabuleiro (T);
      begin
         for Sq in 1 .. 64 loop
            Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
         end loop;
         Apply_Raw (F, T, Promo_Of (F, T));
         Danger := Search_Integration.Has_Forced_Mate_Within_Two
                     (Attacker_White => not Is_White_To_Move)
           or else Root_Piece_Hangs (T, Captured_Value)
           or else Quiet_Move_Worsens_Material (Root_Before, Captured_Value);
         for Sq in 1 .. 64 loop
            Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
         end loop;
         return not Danger;
      exception
         when others =>
            for Sq in 1 .. 64 loop
               Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
            end loop;
            raise;
      end Move_Is_Safe;

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

      procedure Choose_Root_Correction (F, T : Integer) is
      begin
         Best_From := F;
         Best_To   := T;
         Chose_Root_Correction := True;
      end Choose_Root_Correction;

      function Try_Special_Move_Only return Boolean is
      begin
         Ep_From := Search_Integration.En_Passant_Candidate (Is_White_To_Move);
         if Ep_From /= 0
           and then Move_Is_Safe (Ep_From, Move_Validation.En_Passant_Sq)
         then
            Best_From := Ep_From;
            Best_To   := Move_Validation.En_Passant_Sq;
            return True;
         end if;

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
         return False;
      end Try_Special_Move_Only;

   begin
      pprechess2.Jogada_Vetada := (others => (others => False));

      --  Stage 1: a legacy move that does not walk into a short mate.
      for Attempt in 0 .. Max_Vetoes loop
         Run_Legacy;
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

      pprechess2.Jogada_Vetada := (others => (others => False));

      if No_Move then
         if Try_Special_Move_Only then
            Best_Promo := Promo_Of (Best_From, Best_To);
         else
            Best_From  := 0;
            Best_To    := 0;
            Best_Promo := 0;
         end if;
         return;
      end if;

      Best_From  := Legacy_From;
      Best_To    := Legacy_To;
      --  Tracks whether Stage 2 selected a SEE-positive capture, so later
      --  stages do not override it after Stage 2b/2c/2d relocate the move.
      Chose_Winning_Capture := False;
      Chose_Root_Correction := False;

      --  Stage 1a: terminal root corrections for validated tactical/opening
      --  classes that later quiet-stage overrides must not undo.
      Search_Integration.Best_Advanced_Central_Pawn_Recapture
        (Is_White_To_Move, Recap_Found, Recap_From, Recap_To);
      if Recap_Found and then Move_Is_Safe (Recap_From, Recap_To) then
         Best_From  := Recap_From;
         Best_To    := Recap_To;
         Best_Promo := Promo_Of (Best_From, Best_To);
         return;
      end if;

      Search_Integration.Best_Opening_Trap_Response
        (Is_White_To_Move, Trap_Found, Trap_From, Trap_To);
      if Trap_Found and then Move_Is_Safe (Trap_From, Trap_To) then
         Best_From  := Trap_From;
         Best_To    := Trap_To;
         Best_Promo := Promo_Of (Best_From, Best_To);
         return;
      end if;

      Search_Integration.Best_Pawn_Tempo_Kick_Knight
        (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
      if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To) then
         Best_From  := Kick_From;
         Best_To    := Kick_To;
         Best_Promo := Promo_Of (Best_From, Best_To);
         return;
      end if;

      Search_Integration.Best_Central_Pawn_Capture
        (Is_White_To_Move, Cen_Found, Cen_From, Cen_To);
      if not Is_White_To_Move
        and then Cen_Found
        and then not Enemy_Queen_Attacks_King_Bishop_Pawn
        and then Move_Is_Safe (Cen_From, Cen_To)
      then
         Best_From  := Cen_From;
         Best_To    := Cen_To;
         Best_Promo := Promo_Of (Best_From, Best_To);
         return;
      end if;

      --  Stage 2: SEE-positive captures. The ply-4..16 chain can stamp
      --  Jogada_Perde_Profunda on a root take when some optional deeper
      --  ply is bad (documented over-pessimism), vetoing free or
      --  winning exchanges inside the cascade. Enforced here at the
      --  root: hanging takes (full victim value) and winning exchanges
      --  (victim - capturer > 0 when defended). No FEN hard-coding.
      Search_Integration.Best_Winning_Capture
        (Is_White_To_Move, Hang_Found, Hang_From, Hang_To);
      if Hang_Found and then Move_Is_Safe (Hang_From, Hang_To) then
         declare
            function See_Gain (F, T : Integer) return Integer is
               Cap_Code : constant Integer := Pvalidade.Tabuleiro (F);
               Vic_Code : constant Integer := Pvalidade.Tabuleiro (T);
               Cap      : constant Integer := abs Cap_Code;
               Vic      : constant Integer := abs Vic_Code;
               Defended_After : Boolean;
            begin
               if Vic = 0 then
                  return 0;
               end if;

               Pvalidade.Tabuleiro (F) := 0;
               Pvalidade.Tabuleiro (T) := Cap_Code;
               Defended_After := Move_Validation.Is_Square_Attacked
                 (T, By_White => not Is_White_To_Move);
               Pvalidade.Tabuleiro (F) := Cap_Code;
               Pvalidade.Tabuleiro (T) := Vic_Code;

               if Defended_After then
                  return Vic - Cap;
               end if;
               return Vic;
            end See_Gain;

            Win_Gain    : constant Integer := See_Gain (Hang_From, Hang_To);
            Legacy_See  : Integer := 0;
         begin
            if Legacy_Was_Capture then
               Legacy_See := See_Gain (Legacy_From, Legacy_To);
            end if;
            if Win_Gain > Legacy_See then
               Best_From := Hang_From;
               Best_To   := Hang_To;
               Chose_Winning_Capture := True;
            end if;
         end;
      end if;

      --  Stage 2b: queen pawn-grab can yield to a queen tempo on an exposed
      --  enemy queen (e.g. Qc5/Qb4 instead of Qxe4). Keep higher-value
      --  winning captures untouched.
      if not Chose_Root_Correction
        and then abs Pvalidade.Tabuleiro (Best_From) = 20
        and then abs Pvalidade.Tabuleiro (Best_To) = 1
      then
         Search_Integration.Best_Queen_Tempo_On_Queen
           (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
         if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
            Choose_Root_Correction (Tempo_From, Tempo_To);
            Chose_Winning_Capture := False;
         end if;
      end if;

      --  Stage 2b: pawn tempo-kick beats greedy piece-takes-pawn
      --  (Petroff ...d6 hitting Ne5, not the poisoned ...Nxe4). Applies
      --  even when the pawn is "free" — Nxe4 is still poisoned while Ne5
      --  sits on the board.
      declare
         Own_Sign : constant Integer := (if Is_White_To_Move then 1 else -1);
         Cap : constant Integer := abs Pvalidade.Tabuleiro (Best_From);
         Vic : constant Integer := abs Pvalidade.Tabuleiro (Best_To);
         Piece_Takes_Pawn : constant Boolean :=
           Cap > 1 and then Vic = 1
           and then Pvalidade.Tabuleiro (Best_To) * Own_Sign < 0;
      begin
         if not Chose_Root_Correction and then Piece_Takes_Pawn then
            Search_Integration.Best_Pawn_Tempo_Kick
              (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
            if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To) then
               Choose_Root_Correction (Kick_From, Kick_To);
            end if;
         end if;
      end;

      --  Stage 2c: absolute pin beats fleeing a hanging piece (Bb5 vs
      --  Nc6xd4, not Qa4).
      Search_Integration.Best_Absolute_Pin_Save
        (Is_White_To_Move, Pin_Found, Pin_From, Pin_To, Pin_Hang);
      if not Chose_Root_Correction
        and then Pin_Found
        and then Best_From = Pin_Hang
        and then Move_Is_Safe (Pin_From, Pin_To)
      then
         Choose_Root_Correction (Pin_From, Pin_To);
      end if;

      --  Stage 2d: self-discovery (Nd7 opening Bg5xe7) — prefer a pawn
      --  challenge (h7-h6) or re-ask the cascade (Qd7).
      if not Chose_Root_Correction
        and then Search_Integration.Is_Self_Discovery
           (Is_White_To_Move, Best_From, Best_To)
      then
         Search_Integration.Best_Pawn_Tempo_Kick
           (Is_White_To_Move, Kick_Found, Kick_From, Kick_To);
         if Kick_Found and then Move_Is_Safe (Kick_From, Kick_To)
           and then not Search_Integration.Is_Self_Discovery
                          (Is_White_To_Move, Kick_From, Kick_To)
         then
            Choose_Root_Correction (Kick_From, Kick_To);
         else
            for Attempt in 1 .. Max_Vetoes loop
               exit when not Search_Integration.Is_Self_Discovery
                 (Is_White_To_Move, Best_From, Best_To);
               exit when Time_Management.Search_Aborted;
               Veto_Legacy (Best_From, Best_To);
               Run_Legacy;
               exit when Legacy_From = Legacy_To;
               exit when Time_Management.Search_Aborted;
               if Move_Is_Safe (Legacy_From, Legacy_To) then
                  Best_From := Legacy_From;
                  Best_To   := Legacy_To;
               else
                  exit;
               end if;
            end loop;
            pprechess2.Jogada_Vetada := (others => (others => False));
         end if;
      end if;

      --  Stage 2e: opening blunders and queen tempi — exposed enemy queen,
      --  Qf6 facing enemy Q, premature Bb4/Bg4, or early Qa5 instead of a
      --  central pawn trade (dxe4).
      if not Chose_Winning_Capture and then not Chose_Root_Correction then
         Search_Integration.Best_Queen_Tempo_On_Queen
           (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
         if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
            Choose_Root_Correction (Tempo_From, Tempo_To);
         else
            Search_Integration.Best_Development_Tempo_On_Queen
              (Is_White_To_Move, Tempo_Found, Tempo_From, Tempo_To);
            if Tempo_Found and then Move_Is_Safe (Tempo_From, Tempo_To) then
               Choose_Root_Correction (Tempo_From, Tempo_To);
            elsif Search_Integration.Is_Bad_Queen_Sortie
              (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Reinforce_King_Bishop_Pawn
              (Is_White_To_Move, Re_Found, Re_From, Re_To);
            if Re_Found and then Move_Is_Safe (Re_From, Re_To) then
               Choose_Root_Correction (Re_From, Re_To);
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To);
               end if;
            end if;
         elsif Search_Integration.Is_Premature_Flank_Bishop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Solid_Response_To_Flank_Bishop
              (Is_White_To_Move, Solid_Found, Solid_From, Solid_To);
            if Solid_Found and then Move_Is_Safe (Solid_From, Solid_To) then
               Choose_Root_Correction (Solid_From, Solid_To);
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To);
               end if;
            end if;
         elsif Search_Integration.Is_Early_Queen_Develop
                 (Is_White_To_Move, Best_From, Best_To)
         then
            Search_Integration.Best_Central_Pawn_Capture
              (Is_White_To_Move, Cen_Found, Cen_From, Cen_To);
            if Cen_Found and then Move_Is_Safe (Cen_From, Cen_To) then
               Choose_Root_Correction (Cen_From, Cen_To);
            else
               Search_Integration.Best_Natural_Development
                 (Is_White_To_Move, Nat_Found, Nat_From, Nat_To);
               if Nat_Found and then Move_Is_Safe (Nat_From, Nat_To) then
                  Choose_Root_Correction (Nat_From, Nat_To);
               end if;
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
            Choose_Root_Correction (Trade_From, Trade_To);
         else
            Search_Integration.Best_Queenside_B_Pawn_Plan
              (Is_White_To_Move, QSide_Found, QSide_From, QSide_To);
            if QSide_Found and then Move_Is_Safe (QSide_From, QSide_To) then
               Choose_Root_Correction (QSide_From, QSide_To);
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
            Choose_Root_Correction (MinorCap_From, MinorCap_To);
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
            Choose_Root_Correction (Alt_From, Alt_To);
         end if;
      end if;

      --  Stage 2h: castling priority review. If castling is legal and the
      --  current quiet choice is neither a capture nor a central pawn/developing
      --  minor move, prefer castling before later soft-defense/endgame stages.
      --  This stays in the UCI root integration layer and does not reorder the
      --  legacy cascade itself.
      if not Chose_Winning_Capture
        and then not Chose_Root_Correction
        and then Pvalidade.Tabuleiro (Best_To) = 0
      then
         declare
            Piece    : constant Integer := abs Pvalidade.Tabuleiro (Best_From);
            From_R   : constant Integer := Move_Validation.Rank_Of (Best_From);
            From_F   : constant Integer := Move_Validation.File_Of (Best_From);
            To_F     : constant Integer := Move_Validation.File_Of (Best_To);
            Home_R   : constant Integer := (if Is_White_To_Move then 1 else 8);
            Pawn_R   : constant Integer := (if Is_White_To_Move then 2 else 7);
            Central_Pawn : constant Boolean :=
              Piece = 1 and then From_R = Pawn_R and then To_F in 3 .. 5;
            Develop_Minor : constant Boolean :=
              (Piece = 3 or else Piece = 4) and then From_R = Home_R;
         begin
            if not Central_Pawn and then not Develop_Minor then
               Search_Integration.Best_Castle
                 (Is_White_To_Move, Castle_Found, Castle_King);
               if Castle_Found then
                  declare
                     King_Sq : constant Integer :=
                       Move_Validation.Find_King (Is_White_To_Move);
                     Castle_To : constant Integer :=
                       (if Castle_King then King_Sq + 2 else King_Sq - 2);
                  begin
                     if King_Sq /= 0 and then Move_Is_Safe (King_Sq, Castle_To) then
                        Choose_Root_Correction (King_Sq, Castle_To);
                     end if;
                  end;
               end if;
            end if;
         end;
      end if;

      --  Stage 3: en-prise resolve against enemy PAWN takes only.
      --  Soft shields like c7-c6 vs axb5 fail after cxb5 opens Qf3-a8.
      --  Do not override a SEE-positive capture we already chose, and do
      --  not relocate pieces hanging to non-pawn attackers (that clings
      --  to poisoned pawns via c4-c3 instead of developing).
      if not Chose_Winning_Capture and then not Chose_Root_Correction then
         Search_Integration.Best_En_Prise_Resolve
           (Is_White_To_Move, Resolve_Found, Resolve_From, Resolve_To);
         if Resolve_Found and then Move_Is_Safe (Resolve_From, Resolve_To) then
            Choose_Root_Correction (Resolve_From, Resolve_To);
         elsif Search_Integration.Is_Soft_Defend
                 (Is_White_To_Move, Best_From, Best_To)
         then
            --  Piece takes of a hanging pawn: do not cling (b7-b5 /
            --  c8-e6 / c4-c3). Prefer real development (e7-e6 / Nf6).
            Search_Integration.Best_Development_Vs_Hanging_Pawn
              (Is_White_To_Move, Dev_Found, Dev_From, Dev_To);
            if Dev_Found and then Move_Is_Safe (Dev_From, Dev_To) then
               Choose_Root_Correction (Dev_From, Dev_To);
            else
               --  Soft shield vs enemy pawn (c7-c6): re-ask cascade.
               for Attempt in 1 .. Max_Vetoes loop
                  exit when not Search_Integration.Is_Soft_Defend
                    (Is_White_To_Move, Best_From, Best_To);
                  exit when Time_Management.Search_Aborted;
                  Veto_Legacy (Best_From, Best_To);
                  Run_Legacy;
                  exit when Legacy_From = Legacy_To;
                  exit when Time_Management.Search_Aborted;
                  if Move_Is_Safe (Legacy_From, Legacy_To) then
                     Best_From := Legacy_From;
                     Best_To   := Legacy_To;
                  else
                     exit;
                  end if;
               end loop;
               pprechess2.Jogada_Vetada := (others => (others => False));
            end if;
         end if;
      end if;

      --  Stage 4: en passant / castling only when we still have the
      --  cascade's quiet choice (do not override a resolve/capture).
      if Best_From = Legacy_From and then Best_To = Legacy_To
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
         end if;
      end;

      Best_Promo := Promo_Of (Best_From, Best_To);
   end Compute_Best_Move;

   procedure Handle_Setoption (Cmd : String) is
      Name_Idx  : constant Integer := Ada.Strings.Fixed.Index (Cmd, "name ");
      Value_Idx : constant Integer := Ada.Strings.Fixed.Index (Cmd, " value ");
   begin
      if Name_Idx = 0 or else Value_Idx = 0 or else Value_Idx <= Name_Idx then
         return;
      end if;

      declare
         Opt_Name  : constant String := Trimmed (Cmd (Name_Idx + 5 .. Value_Idx - 1));
         Opt_Value : constant String := Trimmed (Cmd (Value_Idx + 7 .. Cmd'Last));
      begin
         if Opt_Name = "Hash" or else Opt_Name = "hash" then
            declare
               MB : Integer;
            begin
               MB := Integer'Value (Opt_Value);
               if MB < TT_Table.Min_Size_MB then MB := TT_Table.Min_Size_MB; end if;
               if MB > TT_Table.Max_Size_MB then MB := TT_Table.Max_Size_MB; end if;
               --  Safe to apply immediately: this engine is single-
               --  threaded and processes one UCI command at a time, so
               --  "setoption" can only ever arrive between searches,
               --  never during one.
               TT_Table.Resize_TT (MB);
            exception
               when others => null; -- malformed value: ignore, keep current size
            end;
         end if;
      end;
   end Handle_Setoption;

   procedure Report_Uci_Options is
   begin
      Put_Line ("id name Prechess UCI 0.7.9.9");
      Put_Line ("id author Strapasson Jose Lauro, Legacy 0.7.8 and Arthur Matheus further releases");
      Put_Line ("id version 0.7.9.9");
      Put_Line
        ("option name Hash type spin default"
         & Integer'Image (TT_Table.Default_Size_MB)
         & " min" & Integer'Image (TT_Table.Min_Size_MB)
         & " max" & Integer'Image (TT_Table.Max_Size_MB));
      Put_Line ("uciok");
   end Report_Uci_Options;

   procedure Handle_Go (Cmd : String) is
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer := 0;
      Perft_Depth : Integer := -1;
      Max_Perft_Depth : constant Integer := 6;
      Infinite : Boolean := False;
      Tokens : Unbounded_String := To_Unbounded_String (Cmd (Cmd'First + 2 .. Cmd'Last));

      function Get_Next_Int (S : in out Unbounded_String) return Integer is
         Idx : constant Integer := Ada.Strings.Fixed.Index (To_String (S), " ");
         Res : Integer := 0;
      begin
         if Idx > 0 then
            begin
               Res := Integer'Value (To_String (S) (1 .. Idx - 1));
            exception
               when others => null;
            end;
            S := To_Unbounded_String (Ada.Strings.Fixed.Trim (To_String (S) (Idx + 1 .. Length (S)), Ada.Strings.Both));
         else
            begin
               Res := Integer'Value (To_String (S));
            exception
               when others => null;
            end;
            S := To_Unbounded_String ("");
         end if;
         return Res;
      end Get_Next_Int;

   begin
      while Length (Tokens) > 0 loop
         declare
            S_Str : constant String := To_String (Tokens);
            Idx   : constant Integer := Ada.Strings.Fixed.Index (S_Str, " ");
            Tok   : Unbounded_String;
         begin
            if Idx > 0 then
               Tok := To_Unbounded_String (S_Str (1 .. Idx - 1));
               Tokens := To_Unbounded_String (Ada.Strings.Fixed.Trim (S_Str (Idx + 1 .. S_Str'Last), Ada.Strings.Both));
            else
               Tok := Tokens;
               Tokens := To_Unbounded_String ("");
            end if;

            if Tok = "wtime" then WTime := Get_Next_Int (Tokens);
            elsif Tok = "btime" then BTime := Get_Next_Int (Tokens);
            elsif Tok = "winc" then WInc := Get_Next_Int (Tokens);
            elsif Tok = "binc" then BInc := Get_Next_Int (Tokens);
            elsif Tok = "movestogo" then Moves_To_Go := Get_Next_Int (Tokens);
            elsif Tok = "movetime" then Move_Time := Get_Next_Int (Tokens);
            elsif Tok = "depth" then Depth := Get_Next_Int (Tokens);
            elsif Tok = "infinite" then Infinite := True;
            elsif Tok = "perft" then Perft_Depth := Get_Next_Int (Tokens);
            end if;
         end;
      end loop;

      --  `go perft N`: a Stockfish-style test facility. Prints one line per
      --  legal root move plus a total, emits NO bestmove, and never enters
      --  the search (so it cannot affect play). Uses Move_Gen's own make/
      --  unmake on the global board, not the legacy cascade. Bound the debug
      --  depth so malformed GUI input cannot hang the engine indefinitely.
      if Perft_Depth >= 0 then
         if Perft_Depth > Max_Perft_Depth then
            Put_Line ("info string perft depth too large; max is"
                      & Integer'Image (Max_Perft_Depth));
            return;
         elsif Perft_Depth = 0 then
            Put_Line ("perft 0 1");
            return;
         else
            Move_Gen.Perft_Divide (Perft_Depth, Is_White_To_Move);
            return;
         end if;
      end if;

      --  UCI has no draw-claim mechanism: adjudicating repetitions, the
      --  50-move rule and dead positions is the GUI's job, and a GUI
      --  that has not adjudicated expects a real move -- an engine that
      --  answers "go" with "bestmove 0000" in a merely-claimable-draw
      --  position risks being forfeited for an illegal move. So the
      --  condition is reported as an info string and the search runs
      --  normally; "bestmove 0000" remains reserved for positions with
      --  genuinely no legal move (checkmate/stalemate), where it is the
      --  only honest answer available.
      if Search_Integration.Is_Draw then
         Put_Line ("info string position is drawn under FIDE rules "
                   & "(repetition, 50-move or dead position); playing on");
      end if;

      Time_Management.Start_Search
        (WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth, Is_White_To_Move, Infinite);

      --  Per-search counters. The node counter used to accumulate for
      --  the life of the process (a GUI analyzing several positions saw
      --  every earlier search's nodes folded into the current one's
      --  "nodes"/"nps"); each "go" is one search, so it starts at zero.
      TT_Types.Nodes_Searched := 0;

      declare
         Best_From, Best_To, Best_Promo : Integer;
      begin
         Compute_Best_Move (Best_From, Best_To, Best_Promo);

         --  Print one final info line reflecting the true final
         --  decision (Compute_Best_Move may have overridden the legacy
         --  engine's own candidate with castling or an en-passant
         --  capture -- see README_UCI.md, "Root move integration
         --  policy") so the last "info ... pv" always matches
         --  "bestmove", the way Stockfish's does.
         if Best_From /= 0 and then Best_To /= 0 then
            Search_Integration.Report_UCI (Best_From, Best_To);
         end if;

         --  Extend the principal variation the way an iterative
         --  deepening engine's panel fills in: after the root choice is
         --  made, replay the engine's OWN move selection forward on a
         --  scratch continuation (opponent's expected reply, our answer
         --  to it, and so on), emitting one progressively longer
         --  "info depth 3+k ... pv m1 .. m(k+1)" line per extension.
         --  Each PV move is the full engine's real choice at that node
         --  (a genuine extra search, whose nodes are counted), so the
         --  displayed depth is honestly the number of plies of the line
         --  actually chosen by the engine, and seldepth stays 9 ahead
         --  (the ply-4..16 safety chain each of those searches ran).
         --  Bounded by the same time budget as the main search: probes
         --  self-abort through Time_Management, so under a tight clock
         --  the PV simply stays short. All engine state the probes
         --  disturb (board, opening-book counter, draw counter) is
         --  saved and restored; probe searches print nothing themselves
         --  (Search_Integration.Suppress_Info).
         if Best_From /= 0 and then Best_To /= 0 then
            declare
               Max_Ext     : constant := 5;
               Saved_Board : array (1 .. 64) of Integer := (others => 0);
               Saved_Contagem : constant Integer := pprechess2.Contagem_Empate;
               White_Turn  : Boolean := Is_White_To_Move;
               PV          : Unbounded_String :=
                 To_Unbounded_String (Move_To_String (Best_From, Best_To, Best_Promo));
               Ply_Score   : Integer;

               --  Restore everything a PV probe disturbs (board, draw
               --  counter, info-suppression flag). Called on both the
               --  normal exit and the exception path so a probe that
               --  raises cannot leave Suppress_Info stuck True or the
               --  scratch continuation board in place.
               procedure Restore_State is
               begin
                  for Sq in 1 .. 64 loop
                     Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
                  end loop;
                  pprechess2.Contagem_Empate := Saved_Contagem;
                  Search_Integration.Suppress_Info := False;
               end Restore_State;

            begin
               for Sq in 1 .. 64 loop
                  Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
               end loop;
               Search_Integration.Suppress_Info := True;

               Apply_Raw (Best_From, Best_To, Best_Promo);
               White_Turn := not White_Turn;

               for K in 1 .. Max_Ext loop
                  exit when not Time_Management.Allow_PV_Probe;
                  declare
                     Mirrored : constant Boolean := not White_Turn;
                     F, T, Promo : Integer;
                     --  Transposition-table integration. The legacy core
                     --  is deterministic and sees ONLY the raw board (it
                     --  knows nothing of castling rights or en passant),
                     --  so board-plus-side-to-move fully keys its
                     --  choice; EP/castling are deliberately excluded
                     --  from the key (Ep_Square => 0, rights => 0) to
                     --  match that and maximize transposition hits. An
                     --  analysis GUI re-searches after every move, and
                     --  the new PV chain overlaps the old one almost
                     --  entirely -- each hit here replaces a full
                     --  multi-second probe search with one O(64) hash
                     --  and a table read. The cache is consulted ONLY
                     --  in this display path, never for the root move
                     --  actually played. (The core's draw-avoidance
                     --  counter can in principle vary its choice for
                     --  identical boards across a long game; for the
                     --  cosmetic PV this is an acceptable, documented
                     --  approximation.)
                     Key : constant TT_Types.Hash_Key :=
                       BCH_Hash.Compute_Hash
                         (White_To_Move => White_Turn,
                          Ep_Square => 0, Castling_Rights => 0);
                     Cached : TT_Types.TT_Entry;
                     Hit    : constant Boolean := TT_Table.Probe_TT (Key, Cached);
                  begin
                     if Hit then
                        F     := Cached.Best.From_Sq;
                        T     := Cached.Best.To_Sq;
                        Promo := Cached.Best.Prom;
                        --  Same sentinel guard as the miss path: a corrupt
                        --  or empty-shaped cache must not extend the PV.
                        exit when F = T or else F = 0 or else T = 0;
                        --  Cheap sanity check: the cached move must originate
                        --  on one of our pieces and not capture our own piece.
                        --  This is not full legality validation but it stops
                        --  the most common hash-collision/stale-entry shapes
                        --  from emitting an impossible continuation.
                        declare
                           Own_Sign : constant Integer :=
                             (if White_Turn then 1 else -1);
                        begin
                           exit when Pvalidade.Tabuleiro (F) = 0
                             or else Pvalidade.Tabuleiro (F) * Own_Sign <= 0
                             or else Pvalidade.Tabuleiro (T) * Own_Sign > 0;
                        end;
                     else
                        if Mirrored then
                           Search_Integration.Flip_Board;
                        end if;
                        pprechess2.Prechess2;
                        F := pprechess2.Cc;
                        T := pprechess2.Dd;
                        if Mirrored then
                           Search_Integration.Flip_Board;
                           --  Guard the 0 = "no legal move" sentinel
                           --  (Mirror_Square's Pre is Sq in 1 .. 64);
                           --  the F = 0 / T = 0 exit below then handles
                           --  the terminal continuation cleanly instead
                           --  of relying on the enclosing when others.
                           if F /= 0 then
                              F := Move_Validation.Mirror_Square (F);
                           end if;
                           if T /= 0 then
                              T := Move_Validation.Mirror_Square (T);
                           end if;
                        end if;
                        exit when Time_Management.Search_Aborted; -- probe cut off: discard
                        exit when F = T or else F = 0 or else T = 0; -- no legal move
                        Promo := 0;
                        if abs Pvalidade.Tabuleiro (F) = 1
                          and then (Move_Validation.Rank_Of (T) = 1
                                    or else Move_Validation.Rank_Of (T) = 8)
                        then
                           Promo := 20;
                        end if;
                        --  Completed, non-sentinel choice: cache it for
                        --  the next overlapping PV chain. Depth tracks
                        --  the PV-extension ply so multi-bucket replacement
                        --  can prefer deeper (later) probes over earlier ones.
                        TT_Table.Store_TT
                          (Key   => Key,
                           Depth => 3 + K,
                           Score => 0,
                           Flag  => TT_Types.Exact,
                           Best  => (From_Sq => F, To_Sq => T, Prom => Promo));
                     end if;
                     Apply_Raw (F, T, Promo);
                     Append (PV, " " & Move_To_String (F, T, Promo));
                     White_Turn := not White_Turn;
                     --  Score of the position reached by the just-applied
                     --  PV move, from the new side to move's perspective.
                     Ply_Score := Search_Integration.Material_Score_Cp;
                     if not White_Turn then
                        Ply_Score := -Ply_Score;
                     end if;
                     Search_Integration.Report_PV
                       (Depth => 3 + K, Seldepth => 16 + K,
                        Score_Cp => Ply_Score, PV => To_String (PV));
                  end;
               end loop;

               Restore_State;
            exception
               when others =>
                  Restore_State;
                  --  A probe fault is only cosmetic PV extension: truncate
                  --  the line and continue so the engine does not abort.
            end;
         end if;

         --  UCI requires "go infinite" to withhold bestmove until
         --  "stop" (or "quit") arrives, even though the legacy core's
         --  fixed 3-ply structure means the search itself is already
         --  finished (see README_UCI.md, "Architectural limitations").
         --  Wait here rather than reporting early.
         if Infinite then
            loop
               begin
                  Get_Line (Line, Last);
               exception
                  when End_Error =>
                     Quit_Requested := True;
                     exit;
               end;
               if Last = 0 and then End_Of_File then
                  --  GUI closed stdin without "stop"/"quit": UCI expects no
                  --  bestmove, so treat it exactly like "quit".
                  Quit_Requested := True;
                  exit;
               end if;
               declare
                  Wait_Input : constant String := Trimmed (Line (1 .. Last));
               begin
                  if Wait_Input = "stop" then
                     exit;
                  elsif Wait_Input = "quit" then
                     Quit_Requested := True;
                     exit;
                  end if;
               end;
            end loop;
         end if;

         --  UCI: "quit"/EOF must terminate the engine with no bestmove.
         if not Quit_Requested then
            if Best_From = 0 and then Best_To = 0 then
               Put_Line ("bestmove 0000"); -- checkmate or stalemate
            else
               Put_Line ("bestmove " & Move_To_String (Best_From, Best_To, Best_Promo));
            end if;
         end if;
      end;
   end Handle_Go;

begin
   TT_Table.Init_TT (TT_Table.Default_Size_MB);

   loop
      begin
         Get_Line (Line, Last);
      exception
         when End_Error => exit;
      end;
      exit when Last = 0 and then End_Of_File;

      declare
         Input : constant String := Trimmed (Line (1 .. Last));
      begin
         if Input = "uci" then
            Report_Uci_Options;
         elsif Input = "isready" then
            Put_Line ("readyok");
         elsif Input = "ucinewgame" then
            TT_Table.Clear_TT;
            Search_Integration.Reset_Game;
            --  Per-game legacy state: the draw-avoidance counter
            --  (Contagem_Empate, which biases the cascade's rule
            --  choices once it passes its threshold) belongs to one
            --  game; a new game starts it fresh.
            pprechess2.Contagem_Empate := 0;
         elsif Input = "setoption"
           or else (Input'Length > 10
                    and then Input (Input'First .. Input'First + 9) = "setoption ")
         then
            Handle_Setoption (Input);
         elsif Input = "position"
           or else (Input'Length > 9
                    and then Input (Input'First .. Input'First + 8) = "position ")
         then
            Handle_Position (Input);
         elsif Input = "go"
           or else (Input'Length > 3
                    and then Input (Input'First .. Input'First + 2) = "go ")
         then
            Handle_Go (Input);
         elsif Input = "stop" then
            Time_Management.Stop_Search; -- synchronous engine: no in-flight search to interrupt
         elsif Input = "quit" then
            exit;
         end if;
      end;
      exit when Quit_Requested;
   end loop;
end Prechess_UCI;
