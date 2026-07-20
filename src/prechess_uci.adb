with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Search_Integration;
with Move_Validation;
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
   Line : String (1 .. 1024);
   Last : Natural;

   --  Whose move it really is, in absolute (unmirrored) terms. This is
   --  the single source of truth Search_Integration.Parse_FEN reports
   --  and Handle_Position maintains while replaying "moves".
   Is_White_To_Move : Boolean := True;

   --  (The hardcoded opening book was removed from pprechess2; no
   --  book-eligibility tracking remains.)

   function Trimmed (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trimmed;

   procedure Replay_Moves (Moves_Str : String) is
      Start_Pos : Integer := Moves_Str'First;
      End_Pos   : Integer;
   begin
      while Start_Pos <= Moves_Str'Last loop
         End_Pos := Ada.Strings.Fixed.Index (Moves_Str (Start_Pos .. Moves_Str'Last), " ");
         if End_Pos = 0 then
            Search_Integration.Make_Move_UCI (Moves_Str (Start_Pos .. Moves_Str'Last));
            Is_White_To_Move := not Is_White_To_Move;
            exit;
         else
            Search_Integration.Make_Move_UCI (Moves_Str (Start_Pos .. End_Pos - 1));
            Is_White_To_Move := not Is_White_To_Move;
            Start_Pos := End_Pos + 1;
         end if;
      end loop;
   end Replay_Moves;

   procedure Handle_Position (Cmd : String) is
   begin
      Search_Integration.Reset_Game;

      if Cmd'Length >= 17 and then Cmd (Cmd'First .. Cmd'First + 16) = "position startpos" then
         Search_Integration.Parse_FEN
           ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Is_White_To_Move);

         declare
            Moves_Idx : constant Integer := Ada.Strings.Fixed.Index (Cmd, " moves ");
         begin
            if Moves_Idx > 0 then
               Replay_Moves (Trimmed (Cmd (Moves_Idx + 7 .. Cmd'Last)));
            end if;
         end;

      elsif Cmd'Length >= 13 and then Cmd (Cmd'First .. Cmd'First + 12) = "position fen " then
         declare
            Fen_Str    : constant String := Trimmed (Cmd (Cmd'First + 13 .. Cmd'Last));
            Moves_Idx  : constant Integer := Ada.Strings.Fixed.Index (Fen_Str, " moves ");
            Actual_Fen : constant String :=
              (if Moves_Idx > 0 then Fen_Str (Fen_Str'First .. Moves_Idx - 1) else Fen_Str);
         begin
            Search_Integration.Parse_FEN (Actual_Fen, Is_White_To_Move);
            if Moves_Idx > 0 then
               Replay_Moves (Trimmed (Fen_Str (Moves_Idx + 7 .. Fen_Str'Last)));
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
         declare
            R : constant Integer := Move_Validation.Rank_Of (F);
         begin
            if Move_Validation.File_Of (T) = 7 then
               Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 6)) :=
                 Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 8));
               Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 8)) := 0;
            else
               Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 4)) :=
                 Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 1));
               Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, 1)) := 0;
            end if;
         end;
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
      Max_Vetoes  : constant := 4;
      First_From, First_To : Integer := 0;
      Saved_Board : array (1 .. 64) of Integer;
      No_Move     : Boolean := False;

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
            Legacy_From := Move_Validation.Mirror_Square (Legacy_From);
            Legacy_To   := Move_Validation.Mirror_Square (Legacy_To);
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

      --  Apply the move on a scratch board, ask whether the opponent
      --  then has a forced mate within two, restore. Real coordinates.
      function Move_Is_Safe (F, T : Integer) return Boolean is
         Danger : Boolean;
      begin
         for Sq in 1 .. 64 loop
            Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
         end loop;
         Apply_Raw (F, T, Promo_Of (F, T));
         Danger := Search_Integration.Has_Forced_Mate_Within_Two
                     (Attacker_White => not Is_White_To_Move);
         for Sq in 1 .. 64 loop
            Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
         end loop;
         return not Danger;
      end Move_Is_Safe;

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
         Best_From  := 0;
         Best_To    := 0;
         Best_Promo := 0;
         return;
      end if;

      Best_From  := Legacy_From;
      Best_To    := Legacy_To;

      --  Stage 1.5: minor-piece retreat improvement. If the vetted legacy
      --  choice is a bishop/knight fleeing an attack to a low-mobility
      --  square, redirect it to a safe destination with more durable
      --  mobility (the reported Bb4-Ba5-Bb6 rim-trap fix). The improved
      --  square is itself re-verified against short forced mates; only a
      --  genuinely different, safe square replaces the original.
      declare
         Alt_To : constant Integer :=
           Search_Integration.Improved_Minor_Retreat (Best_From, Best_To);
      begin
         if Alt_To /= Best_To and then Move_Is_Safe (Best_From, Alt_To) then
            Best_To := Alt_To;
            Legacy_Was_Capture := False; -- redirected to a quiet square
         end if;
      end;

      --  Stage 1.6: deferred-tactic booster. If a forcing capture/check
      --  sequence wins clearly more material (>= a minor piece) than the
      --  legacy choice forces, and the first move of it is safe, play it.
      --  Catches combinations that are materially even on the first move
      --  but win via a follow-up fork/skewer, which the material-only
      --  ply-4..10 chain declines (reported game: 5.Nexc6 .. Nd6+).
      declare
         BF, BT, BG : Integer;
         Legacy_Gain : Integer;
      begin
         --  Node-bounded (see Node_Budget), so its worst-case cost is a
         --  small fixed overhead the time manager's reserve already covers.
         Search_Integration.Best_Forcing_Move (Is_White_To_Move, BF, BT, BG);
         if BF /= 0 and then BG >= 3 and then (BF /= Best_From or else BT /= Best_To)
         then
            Legacy_Gain :=
              Search_Integration.Forced_Gain_Of (Is_White_To_Move, Best_From, Best_To);
            if BG > Legacy_Gain and then Move_Is_Safe (BF, BT) then
               Best_From := BF;
               Best_To   := BT;
               Legacy_Was_Capture := Pvalidade.Tabuleiro (BT) /= 0;
            end if;
         end if;
      end;

      --  Stage 2: root integration policy (en passant / castling),
      --  each override itself verified before it replaces a move that
      --  already passed the mate check.
      if not Legacy_Was_Capture then
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
                  if Move_Is_Safe (King_Sq, Castle_To) then
                     Best_From := King_Sq;
                     Best_To   := Castle_To;
                  end if;
               end;
            end if;
         end if;
      end if;

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
      Put_Line ("id name Prechess UCI 0.7.9");
      Put_Line ("id author Strapasson Jose Lauro, Legacy 0.7.8 and Arthur Matheus further releases");
      Put_Line
        ("option name Hash type spin default"
         & Integer'Image (TT_Table.Default_Size_MB)
         & " min" & Integer'Image (TT_Table.Min_Size_MB)
         & " max" & Integer'Image (TT_Table.Max_Size_MB));
      Put_Line ("uciok");
   end Report_Uci_Options;

   procedure Handle_Go (Cmd : String) is
      WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer := 0;
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
            end if;
         end;
      end loop;

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
         --  actually chosen by the engine, and seldepth stays 7 ahead
         --  (the ply-4..10 safety chain each of those searches ran).
         --  Bounded by the same time budget as the main search: probes
         --  self-abort through Time_Management, so under a tight clock
         --  the PV simply stays short. All engine state the probes
         --  disturb (board, opening-book counter, draw counter) is
         --  saved and restored; probe searches print nothing themselves
         --  (Search_Integration.Suppress_Info).
         if Best_From /= 0 and then Best_To /= 0 then
            declare
               Max_Ext     : constant := 5;
               Saved_Board : array (1 .. 64) of Integer;
               Saved_Contagem : constant Integer := pprechess2.Contagem_Empate;
               White_Turn  : Boolean := Is_White_To_Move;
               PV          : Unbounded_String :=
                 To_Unbounded_String (Move_To_String (Best_From, Best_To, Best_Promo));
               Root_Score  : Integer := Search_Integration.Material_Score_Cp;

            begin
               if Search_Integration.Report_For_Black then
                  Root_Score := -Root_Score;
               end if;
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
                     else
                        if Mirrored then
                           Search_Integration.Flip_Board;
                        end if;
                        pprechess2.Prechess2;
                        F := pprechess2.Cc;
                        T := pprechess2.Dd;
                        if Mirrored then
                           Search_Integration.Flip_Board;
                           F := Move_Validation.Mirror_Square (F);
                           T := Move_Validation.Mirror_Square (T);
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
                        --  the next overlapping PV chain.
                        TT_Table.Store_TT
                          (Key   => Key,
                           Depth => 3,
                           Score => 0,
                           Flag  => TT_Types.Exact,
                           Best  => (From_Sq => F, To_Sq => T, Prom => Promo));
                     end if;
                     Apply_Raw (F, T, Promo);
                     Append (PV, " " & Move_To_String (F, T, Promo));
                     White_Turn := not White_Turn;
                     Search_Integration.Report_PV
                       (Depth => 3 + K, Seldepth => 10 + K,
                        Score_Cp => Root_Score, PV => To_String (PV));
                  end;
               end loop;

               for Sq in 1 .. 64 loop
                  Pvalidade.Tabuleiro (Sq) := Saved_Board (Sq);
               end loop;
               pprechess2.Contagem_Empate := Saved_Contagem;
               Search_Integration.Suppress_Info := False;
            end;
         end if;

         --  UCI requires "go infinite" to withhold bestmove until
         --  "stop" (or "quit") arrives, even though the legacy core's
         --  fixed 3-ply structure means the search itself is already
         --  finished (see README_UCI.md, "Architectural limitations").
         --  Wait here rather than reporting early.
         if Infinite then
            loop
               Get_Line (Line, Last);
               declare
                  Wait_Input : constant String := Trimmed (Line (1 .. Last));
               begin
                  exit when Wait_Input = "stop" or else Wait_Input = "quit";
               end;
            end loop;
         end if;

         if Best_From = 0 and then Best_To = 0 then
            Put_Line ("bestmove 0000"); -- checkmate or stalemate
         else
            Put_Line ("bestmove " & Move_To_String (Best_From, Best_To, Best_Promo));
         end if;
      end;
   end Handle_Go;

begin
   TT_Table.Init_TT (TT_Table.Default_Size_MB);

   loop
      Get_Line (Line, Last);
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
         elsif Input'Length >= 9 and then Input (Input'First .. Input'First + 8) = "setoption" then
            Handle_Setoption (Input);
         elsif Input'Length >= 8 and then Input (Input'First .. Input'First + 7) = "position" then
            Handle_Position (Input);
         elsif Input'Length >= 2 and then Input (Input'First .. Input'First + 1) = "go" then
            Handle_Go (Input);
         elsif Input = "stop" then
            Time_Management.Stop_Search; -- synchronous engine: no in-flight search to interrupt
         elsif Input = "quit" then
            exit;
         end if;
      end;
   end loop;
end Prechess_UCI;
