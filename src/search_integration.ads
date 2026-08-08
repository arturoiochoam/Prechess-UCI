with TT_Types; use TT_Types;

package Search_Integration is

   --  FIDE Draw Rules State
   Fifty_Move_Counter : Integer := 0;

   --  History of Zobrist hashes for 3-fold repetition. Every call to
   --  Make_Move_UCI (and the initial Parse_FEN) pushes exactly one
   --  entry, so this reflects the true game history instead of relying
   --  on a caller to remember to feed it. The legacy search never
   --  calls Push_State (it works on Pvalidade.Tabuleiro with its own
   --  make/unmake), so search-tree nodes do NOT pollute this history:
   --  Is_Threefold_Repetition therefore sees the full pre-search game
   --  history at the root, not just the search tree.
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

   --  UCI loop integration. Try_Parse_FEN validates and commits a FEN
   --  atomically; Parse_FEN is the legacy convenience wrapper used by tests
   --  that only feed trusted FEN strings.
   function Try_Parse_FEN (FEN : String; White_To_Move : in out Boolean) return Boolean;
   procedure Parse_FEN (FEN : String; White_To_Move : out Boolean);

   --  Applies one replay move from UCI input to Pvalidade.Tabuleiro,
   --  updating castling/en-passant state, 50-move counter, and repetition
   --  history when (and only when) the move is legal and actually applied.
   --  The turn-explicit overload is used by the UCI loop while replaying
   --  "position ... moves ..." so wrong-side tokens are rejected instead of
   --  desynchronizing board/turn/history state.
   procedure Make_Move_UCI
     (Move_Str               : String;
      Expected_White_To_Move : Boolean;
      Applied                : out Boolean);
   procedure Make_Move_UCI (Move_Str : String; Applied : out Boolean);
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
   --  the ply-4..16 chain is material-only, so a mate that arrives one
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

   --  Best SEE-positive capture on the real board: pseudo-legal, does not
   --  leave the mover in check, and static exchange gain > 0. Gain is
   --  abs(victim) when the target is undefended, else abs(victim) -
   --  abs(capturer) (one forced recapture). Used at the UCI root to
   --  override the cascade when Jogada_Perde_Profunda falsely vetoes a
   --  winning take. No FEN/position special-casing.
   procedure Best_Winning_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Best legal SEE-neutral-or-better capture. Used only as a cautious root
   --  repair when the legacy cascade otherwise chooses a quiet move; winning
   --  captures remain handled by Best_Winning_Capture first.
   procedure Best_Non_Losing_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  One-ply SEE of capturer From -> victim To for the given side.
   --  Positive means that side wins material on the capture (+recapture).
   function See_Gain
     (White_Captures : Boolean; From_Sq, To_Sq : Integer) return Integer;

   --  Best (highest) one-ply SEE gain the opponent of White_To_Move has
   --  anywhere on the current board. 0 means no SEE-positive capture is
   --  available to the opponent at all.
   function Max_Opponent_See (White_To_Move : Boolean) return Integer;

   --  Same as Max_Opponent_See, but computed on the hypothetical board
   --  that results from playing (From_Sq, To_Sq) first. Used by root
   --  callers to compare the opponent's best reply before vs. after a
   --  candidate quiet move, so a move that leaves an existing hang
   --  unaddressed (or creates a new one) can be told apart from one that
   --  actually improves the position. Returns 999 if (From_Sq, To_Sq) is
   --  not even pseudo-legal.
   function Max_Opponent_See_After
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Integer;

   --  When the opponent has a SEE-positive capture of our piece, prefer
   --  relocating that piece or capturing its attacker over a "soft
   --  defend" (adding a defender while leaving the piece on the square).
   --  Soft pawn shields often fail one ply later (e.g. axb5 / Qf3-a8
   --  after c7-c6). No FEN hard-coding.
   procedure Best_En_Prise_Resolve
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  True when Move (F,T) clings to a hanging pawn instead of developing:
   --  soft shields (c7-c6 vs axb5; b7-b5 / c8-e6 vs Bxc4) or quiet
   --  advances of a pawn hanging to a piece (c4-c3 vs Bxc4). Capturing
   --  the attacker or relocating a hanging *piece* is not soft.
   function Is_Soft_Defend
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  When a *piece* (not pawn) has SEE > 0 on our pawn, cascade cling
   --  moves (shield / push the pawn) are wrong — accept the pawn and
   --  develop. Prefers e-pawn one step, then Nf6/Nf3, then Nc6/Nc3.
   --  No FEN hard-coding.
   procedure Best_Development_Vs_Hanging_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Equal-or-better trade that removes an enemy minor/slider attacking
   --  our king-bishop pawn (f7/f2). This covers bishop-on-b3/c4 pressure
   --  without treating every equal capture as mandatory. No FEN hard-coding.
   procedure Best_King_Bishop_Pawn_Attacker_Trade
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  When our b-pawn has advanced two squares in the opening queenside
   --  structure, prefer the natural c-bishop fianchetto to b7/b2, else the
   --  a-pawn support push. No FEN hard-coding.
   procedure Best_Queenside_B_Pawn_Plan
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Quiet pawn push that newly attacks an enemy piece (tempo kick),
   --  e.g. ...d7-d6 hitting Ne5. Used at root to prefer the kick over
   --  a greedy piece-takes-pawn (Petroff ...Nxe4??). No FEN hard-coding.
   procedure Best_Pawn_Tempo_Kick
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Narrow general-purpose tempo kick: quiet pawn push newly attacking an
   --  enemy knight. Used before quiet retreats/development, but avoids broad
   --  pawn lunges against bishops/queens that regress opening gates.
   procedure Best_Pawn_Tempo_Kick_Knight
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  When an enemy piece has SEE > 0 on our unit, prefer a quiet move
   --  that absolutely pins that attacker to their king (Bb5 vs Nc6xd4)
   --  over fleeing the hanging piece. No FEN hard-coding.
   procedure Best_Absolute_Pin_Save
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer;
      Hang_Sq       : out Integer);

   --  True when Move vacates a square that was blocking an enemy slider
   --  from capturing one of our units with SEE >= 0 (self-discovery),
   --  e.g. Nd7 opening Bg5 onto Be7. No FEN hard-coding.
   function Is_Self_Discovery
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  Quiet queen move onto a square where the enemy queen has SEE >= 0
   --  (early Qf6 facing Qf3). No FEN hard-coding.
   function Is_Bad_Queen_Sortie
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  Home-rank bishop to the b- or g-file while both knights are still
   --  on the back rank (Italian …Bb4 / …Bg4 instead of Nc6/Nf6/Be7).
   --  No FEN hard-coding.
   function Is_Premature_Flank_Bishop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  Quiet queen leaving the d-file home square (early …Qa5 / Qh5).
   function Is_Early_Queen_Develop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  Natural opening develops: Nf6/Nc6, Bc5/Bc4, Qd7/Qe7. Used when the
   --  cascade picks a bad queen sortie or premature flank bishop.
   procedure Best_Natural_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Opening/middlegame quiet non-central pawn shove (not d/e file) that
   --  creates no immediate tempo on an enemy piece. Captures, promotions,
   --  central pawn play, tempo kicks, and pawn-only endgames are excluded.
   function Is_Opening_Non_Tempo_Flank_Pawn_Push
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  General central/development alternative for the above class.
   procedure Best_Opening_Quiet_Alternative
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  SEE >= 0 pawn takes enemy pawn on the d/e files (…dxe4 / exd5).
   --  Prefer over early queen sorties in open centre positions.
   procedure Best_Central_Pawn_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Equal-or-better recapture of an enemy d/e pawn that has reached our
   --  third rank (rank 6 for White to move, rank 3 for Black to move).
   --  Prefers queen/pawn recaptures so quiet retreats do not ignore the pawn.
   procedure Best_Advanced_Central_Pawn_Recapture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Equal-or-better minor-piece capture of an enemy d/e pawn advanced to the
   --  contested fourth/fifth rank. This catches free central pawns like ...Nxd5
   --  before the cascade spends a tempo pushing a pawn instead.
   procedure Best_Advanced_Central_Pawn_Minor_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);


   --  Recognized reported-trap antidotes expressed as board motifs, not exact
   --  FENs: Légal/Damiano/Elephant/Caro/Siberian/Rauzer/Ruy/Blackburne-style
   --  openings plus submitted defended-material middlegame motifs where the
   --  cascade's material heuristics pick the poisoned move.
   procedure Best_Opening_Trap_Response
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  When f7/f2 is under-defended against a Q+B (or multi-piece) battery,
   --  prefer reinforcing (Qd7/Qe7) or blocking the file (Nf6) over Qf6.
   procedure Best_Reinforce_King_Bishop_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Opening queen-tempo helpers. If an enemy queen is exposed, prefer a
   --  legal queen counter-tempo from an already-developed queen, else a natural
   --  developing move (especially Nc6/Nc3) that attacks it. No FEN hard-coding.
   procedure Best_Queen_Tempo_On_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Development_Tempo_On_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  When the cascade picks a premature home-rank bishop sortie to b/g file,
   --  prefer a solid bishop develop to e-file, else c/f-pawn support.
   procedure Best_Solid_Response_To_Flank_Bishop
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Material balance of the current Tabuleiro in centipawns, signed
   --  from the perspective of whichever side is currently "positive"
   --  (the side to move, once mirroring has been applied). Used only
   --  for the UCI "score cp" display -- it never feeds back into the
   --  legacy search's own move choice. As of Phase P9 this also layers
   --  a general endgame overlay on top of the raw material sum: a
   --  recognized forced draw returns 0 outright, and a recognized
   --  mating endgame (KQ-K / KR-K / KBB-K / KP-K) adds a geometry
   --  bonus (drive the enemy king rimward, confine it, advance the
   --  pawn). See Endgame_Bonus_Cp / Endgame_Is_Draw below.
   function Material_Score_Cp return Integer;

   --  Phase P9 endgame overlay -- GENERAL endgame knowledge (N1: every
   --  rule is expressed over an arbitrary position by counting piece
   --  TYPES only, never naming a specific square or FEN. Each rule
   --  applies to ANY position whose material signature matches).

   --  Bonus in centipawns from the position, signed WHITE-POSITIVE so it
   --  composes with Material_Score_Cp's convention. Adds the attacker's
   --  geometry bonus for KQ-K / KR-K / opposite-colour KBB-K / KP-K and
   --  a defender bonus for the rook-pawn draw. Returns 0 in any position whose
   --  material signature does not match a recognized regime, so calling
   --  it is always safe. Endgame_Is_Draw takes precedence (drawn
   --  positions report 0 unconditionally).
   function Endgame_Bonus_Cp return Integer;

   --  True when the position is a RECOGNIZED forced draw that
   --  Material_Score_Cp collapses to 0. Currently fires for:
   --    * One side has K + a single rook pawn (a/h-pawn) and the lone
   --      defender king stands on that file's promotion corner (a1/h1
   --      for a Black pawn promoting on rank 1, a8/h8 for a White pawn
   --      promoting on rank 8) -- the classic "wrong rook pawn" draw
   --      where the defending king reaches the queening corner.
   --    * Same-coloured KBB-vs-K is handled by the insufficient-material
   --      rule; opposite-coloured KBB-vs-K remains a mating regime.
   function Endgame_Is_Draw return Boolean;

   --  Root-level endgame move override, mirroring Best_Castle /
   --  Best_Winning_Capture / Best_En_Prise_Resolve. Returns a legal move
   --  that STRICTLY IMPROVES Side_Endgame_Bonus_Cp for the side to move in
   --  a recognized mating regime (KQ-K / KR-K / opposite-colour KBB-K /
   --  KP-K), while rejecting stalemate unless the move gives check.
   --  Found = False means no recognized regime, no improving move, or
   --  stalemate risk; the caller keeps the legacy cascade choice.
   procedure Best_Endgame
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

end Search_Integration;
