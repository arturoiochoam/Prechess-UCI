with TT_Types; use TT_Types;

package Search_Integration is

   --  FIDE Draw Rules State
   Fifty_Move_Counter : Integer := 0;

   --  History of Zobrist hashes for 3-fold repetition. Every call to
   --  Make_Move_UCI (and the initial Parse_FEN) pushes exactly one
   --  entry, so this reflects the true game history instead of relying
   --  on a caller to remember to feed it.
   History_Max : constant := 4096;
   type Hash_Array is array (1 .. History_Max) of Hash_Key;
   History : Hash_Array := (others => 0);
   History_Count : Integer := 0;

   --  True while the legacy engine is searching a mirrored (color-
   --  swapped) board on Black's behalf. Report_UCI consults this to
   --  un-mirror the squares it prints, since it is called from deep
   --  inside the legacy search where coordinates are always in the
   --  engine's own "positive side to move" frame.
   Search_Is_Mirrored : Boolean := False;

   --  True when the search now in progress (or just finished) is on
   --  Black's behalf. Unlike Search_Is_Mirrored, this stays set through
   --  the final post-flip-back Report_UCI call, which is exactly the
   --  call that used to report the material score from the wrong
   --  (White's) perspective when Black was to move: UCI's "score cp" is
   --  defined from the side to move, and the raw board sum is
   --  White-positive once the board has been flipped back. Report_UCI
   --  negates the raw sum when this is set and the board is unmirrored,
   --  making every info line -- intermediate and final -- agree.
   Report_For_Black : Boolean := False;

   --  True while Prechess_UCI is running extra "PV probe" searches to
   --  extend the principal variation after the real root search has
   --  finished (see Handle_Go). Those probes are searches of FUTURE
   --  positions along the PV, so their internal candidate churn must
   --  not be reported as if it were live progress on the root position;
   --  Report_UCI returns immediately while this is set.
   Suppress_Info : Boolean := False;

   --  Print one Stockfish-style deepening info line for an extended
   --  principal variation: explicit depth/seldepth and an
   --  already-perspective-corrected score, with live time/nodes/nps.
   procedure Report_PV (Depth, Seldepth, Score_Cp : Integer; PV : String);

   procedure Reset_Game;
   procedure Push_State (H : Hash_Key; Half_Move : Integer);
   function Is_Threefold_Repetition return Boolean;
   function Is_Fifty_Move_Rule return Boolean;
   function Is_Insufficient_Material return Boolean;

   function Is_Draw return Boolean;

   --  UCI loop integration. Parse_FEN reports the side to move (FEN
   --  field 2) so the UCI front end never has to re-derive it itself.
   procedure Parse_FEN (FEN : String; White_To_Move : out Boolean);

   --  Applies one move already known to be legal (supplied by the GUI
   --  in "position ... moves ...", or chosen by the engine itself) to
   --  Pvalidade.Tabuleiro: castling's rook hop, en-passant's removal of
   --  the passed pawn, promotion, castling-rights and en-passant-square
   --  maintenance, the 50-move counter and the repetition history --
   --  one call site, used uniformly for both sides and both origins.
   procedure Make_Move_UCI (Move_Str : String);

   --  Live search info, called by the legacy engine every time it
   --  improves its root candidate. Reports genuine elapsed time, a
   --  real node count and a real material-based score; the promotion
   --  suffix (the engine's own choice always promotes to queen -- see
   --  README, "Root move integration policy") is appended when the
   --  move is a pawn reaching the last rank.
   procedure Report_UCI (From_Sq, To_Sq : Integer);

   --  Re-orients Pvalidade.Tabuleiro for the legacy engine, which only
   --  ever searches assuming its own pieces are the positive side (see
   --  Move_Validation.Mirror_Square). Self-inverse: calling it twice
   --  restores the real board. Deliberately kept outside Move_Validation
   --  itself since it mutates Pvalidade.Tabuleiro, not just state.
   procedure Flip_Board;

   --  From-square of a legal en-passant capture for White_To_Move
   --  against the *real* (unmirrored) board, or 0 if none is available.
   --  The legacy core has no concept of en passant at all, so this is
   --  consulted by the UCI front end's root move selection rather than
   --  by the legacy search itself.
   function En_Passant_Candidate (White_To_Move : Boolean) return Integer;

   --  True when the side given by Attacker_White has a forced mate in
   --  at most two of its own moves, starting with a CHECKING move,
   --  against the current Tabuleiro. Used by Prechess_UCI to verify the
   --  search's chosen move before playing it: the legacy mate machinery
   --  only sees a mate delivered by the opponent's immediate reply, and
   --  the ply-4..10 chain is material-only, so a mate that arrives one
   --  move later at no material cost (the classic Legal-trap pattern:
   --  ...Bxd1?? Bxf7+ Ke7 Nd5#) was invisible. Restricting the first
   --  move to checks keeps this cheap and covers the practically
   --  occurring short mates; quiet-first-move mates in two are outside
   --  its scope. Move generation is the search's own pseudo-legal
   --  Validade filtered by real check detection; castling and en
   --  passant are ignored as escape resources, which can only make the
   --  test MORE cautious (a vetoed move that had an exotic escape),
   --  never less safe. Pawns reaching the last rank are auto-queened.
   function Has_Forced_Mate_Within_Two (Attacker_White : Boolean) return Boolean;

   --  Picks a legal castle for White_To_Move against the real board, if
   --  any (kingside preferred when both are legal).
   procedure Best_Castle
     (White_To_Move : Boolean; Found : out Boolean; Kingside : out Boolean);

   --  Root-level deferred-tactic booster. Runs a small, node-bounded
   --  forcing search (the mover's captures and checks, with FULL legal
   --  replies for the opponent so evasions are never missed, plus a
   --  stand-pat option for a side not in check) and returns the mover's
   --  first move that forces the most material within a few plies, along
   --  with the net material it wins over simply standing pat, both in the
   --  legacy piece-value scale (P1 B3 N4 R7 Q20). From/To are 0 and Gain
   --  is 0 when no forcing move wins material. Purely additive: the caller
   --  (Prechess_UCI) uses it only to override the legacy choice when the
   --  legacy move wins clearly less material and the forcing move is
   --  itself safe -- it never edits the legacy search. Catches the class
   --  where a capture is materially even on the square but a follow-up
   --  fork/skewer wins (reported game: 5.Nexc6 then Nd6+ winning the
   --  bishop, which the material-only ply-4..10 chain rated as an even
   --  trade and declined).
   procedure Best_Forcing_Move
     (Mover_White : Boolean; From, To : out Integer; Gain : out Integer);

   --  Net material (mover's view, positive = winning) that playing the
   --  single move (From, To) and then best forcing play yields over simply
   --  standing pat, in the legacy value scale. Used to compare the legacy
   --  choice against Best_Forcing_Move so the booster overrides only a
   --  move that forces strictly less material. Returns a large negative if
   --  (From, To) is not a legal move for the mover.
   function Forced_Gain_Of
     (Mover_White : Boolean; From, To : Integer) return Integer;

   --  Root-level retreat improver. Given the move (From, To) the legacy
   --  search chose, returns a possibly-better destination for the SAME
   --  piece, or To unchanged. It only ever acts when ALL of these hold,
   --  and returns To otherwise:
   --    * the piece is a bishop or knight (only minor pieces get trapped
   --      on the rim this way; rooks/queens/kings are left alone),
   --    * From is currently attacked by the opponent -- i.e. the move is
   --      a FLIGHT, not a developing move, so redirecting it cannot lose
   --      a tempo the engine wasn't already spending,
   --    * To is a quiet square (empty), so a capture the legacy chose is
   --      never overridden.
   --  Among the piece's materially-safe quiet destinations (squares that
   --  are empty and not attacked by the opponent after the move), it
   --  picks the one with the greatest DURABLE mobility: onward squares
   --  that are empty, unattacked, and not one near-term enemy pawn push
   --  away from being attacked. Ties break toward the more central
   --  square. The legacy's own choice is the baseline, so a strictly
   --  better square must exist to change anything.
   --
   --  Motivation (reported game): playing Black, after 1.d4 e6 2.e4 Bb4+
   --  3.c3 the legacy cascade retreats 3...Ba5 -- its highest tier values
   --  the pin the bishop makes on c3 against the king above the equally
   --  safe central retreats -- and 4.a4 .. 5.b4 Bb6 6.a5 then traps the
   --  bishop with quiet pawn moves the tactical chain never sees (nothing
   --  is captured or checked). Ba5's durable mobility is zero (every
   --  onward square is a pawn push away from attack); Bd6/Be7 keep real
   --  mobility, so this redirects the retreat and the trap never starts.
   --  Caller must still pass the result through the forced-mate check.
   function Improved_Minor_Retreat (From, To : Integer) return Integer;

   --  Material balance of the current Tabuleiro in centipawns, signed
   --  from the perspective of whichever side is currently "positive"
   --  (the side to move, once mirroring has been applied). Used only
   --  for the UCI "score cp" display -- it never feeds back into the
   --  legacy search's own move choice.
   function Material_Score_Cp return Integer;

end Search_Integration;
