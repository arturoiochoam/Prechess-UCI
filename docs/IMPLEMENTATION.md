# Prechess UCI 0.7.9 — Implementation Notes

This document holds the detailed design rationale behind the 0.7.9 changes:
why each decision was made, what alternatives were rejected, and how each
change was verified. `README_UCI.md` has the at-a-glance changelog; this
file is for anyone maintaining or extending the engine who needs the "why,"
not just the "what."

## Color-mirroring bug: root cause

The legacy engine (`pprechess2.adb`) only ever searches assuming its own
pieces are the "positive" side of the board array. The UCI port re-orients
the board for it by mirroring ranks and negating piece signs when Black is
to move, then maps the resulting move back to real coordinates.

The board-mirroring itself was already close to correct in an earlier draft
of this port, but the *coordinate transform* used to map a move found on
the mirrored board back to real coordinates was wrong by exactly one rank:
it computed `(8 - rank)` where the correct inverse is `(7 - rank)`. A move
chosen while playing Black would land on the wrong square — sometimes
literally off the board. This is the root cause of the historical "engine
can only play Black" symptom (in fact it could only play *White* correctly;
Black's moves were the ones being mis-mapped).

Both directions (real-to-mirrored and mirrored-to-real) now go through one
shared, tested function, `Move_Validation.Mirror_Square`, instead of two
independently hand-derived formulas — eliminating the class of bug where
the two directions drift out of sync.

A second, related bug was introduced and caught during development of the
live-info feature: after adding a final `Report_UCI` call inside
`Compute_Best_Move` (for PV/bestmove consistency), the code flipped the
board back but forgot to reset `Search_Integration.Search_Is_Mirrored` to
`False` afterward. This was caught via the en-passant test case (wrong
output `d5e6` instead of the correct `d4e3`) and fixed by resetting the
flag immediately after the flip-back.

## Root move integration policy

The legacy search (`pprechess2.Prechess2`) has no concept of castling or en
passant at all — it was never taught either rule in twenty-plus years of
development. Rather than weave new special-case branches into its
~1000-line evaluation loop (risking the "preserve legacy behavior"
requirement this project is built on), castling and en passant are layered
on top, at the root, by `Prechess_UCI.Compute_Best_Move`, as a small
deterministic decision rule rather than a second competing evaluation
function:

1. If the legacy engine's own chosen move is already a capture, it is
   trusted as-is — it represents the engine's full heuristic judgement,
   captures included.
2. Otherwise, a legal en passant capture is preferred, if one exists: it is
   a genuine capture the legacy core is structurally unable to see, and
   preferring available captures is already the legacy engine's own general
   bias.
3. Otherwise, a legal castle is played (kingside preferred if both are
   legal): a standard, non-speculative "castle when nothing better is on
   offer."
4. Otherwise, the legacy engine's own choice stands.

## Performance: O(1) running material sum

The legacy search recomputed the *entire* 64-square material sum from
scratch after every trial move, at every one of its three plies — an O(64)
rescan inside loops nested up to four deep. Since a trial move only ever
changes the two squares it touches, each of these is now an O(1) update
(`Soma1l := Soma0l - Temporario2`, and similarly at every deeper ply),
which is exactly the value the full rescan always recomputed. This does
not change any comparison, threshold or branch anywhere in the search —
only how the (identical) running sum is computed — so it is a pure
performance win, not a behavior change.

## Performance: caching the decision cascade's predicates

After the ply-1/2/3 search finishes, `pprechess2.adb` picks the move to
play via a long, strictly ordered sequence of rule-blocks (mate first, then
safe queen capture, then any queen capture, then promotion, then checks
that don't lose material, and on down through minor-piece and pawn trades)
— around thirty of them, each independently scanning all 4096 `(A,B)`
square pairs and, for every pair, calling `Validade(A,B)` and re-checking
`Tabuleiro(A)>0`/`Tabuleiro(B)<=0`.

The board is never written anywhere in this cascade (only read), so those
three predicates give the same answer every single time they're asked
about a given `(A,B)` pair. `Own_Piece`, `Not_Own` and `Valid_Cache` now
precompute all three, once, immediately before the cascade begins — the
same 4096 `Validade` calls one rule-block used to make, done once instead
of once per rule-block — and every rule-block reads the cached answer
instead of recomputing it.

The ascending `A`-then-`B` scan order (which the cascade's "last matching
pair wins" behavior depends on, since none of these loops `exit` early) is
unchanged, and so is every threshold, condition and rule ordering. Verified
via a 20-position scripted diff between the pre- and post-change binaries
(covering openings, midgame captures/threats, castling both sides,
promotion, and won/drawn endgames): byte-identical `bestmove` output in
every case.

## Cleanup: merging the four `*_Protegida` functions

`Dama_Protegida`, `Torre_Protegida`, `Bispo_Protegido` and `Cavalo_Protegido`
were four identical copies of the same loop, differing only in one
threshold constant (`-20`/`-7`/`-3`/`-4`). They are now a single
`Protegida(B, Piece_Threshold)` function; every call site passes the same
constant the corresponding original function used, so behavior at each
site is unchanged.

These functions still deliberately treat a piece defended only by the king
as *undefended* — `"Nao quiz proteger com o Rei so para evitar o pior"` in
the original author's own comment. The merge documents this but does not
change it, since fixing it would flip some `Jogada_Perde*` results and is a
real behavior change, not a cleanup.

## Cleanup: the promotion check that looked misplaced but wasn't

`Analize2` sets `Jogada_Promove_Humano`/`Jogada_Promove_Maquina` by scanning
the back ranks, with a comment claiming it belongs in `Analize1` instead.
It does not: `Analize1` and `Analize2` run against two *different* board
states (ply-1 vs. ply-2, i.e. before vs. after the simulated opponent
reply), so moving the check would examine a different position and could
flag different root moves — a behavior change, not a cleanup. The check is
now wrapped in a named `Check_Promotion_Threat` procedure, called from the
exact same site as before, with a comment explaining why it stays there.

## Removed: the hardcoded two-move opening book

Historical note, in two stages. `pprechess2.adb` originally hardcoded
the engine's first two moves of a game via a `numero_de_meu_movimento`
counter that only asked "how many times has this process been asked to
move" -- never whether the board was actually the starting position. A
UCI GUI handing a fresh process an arbitrary FEN therefore received the
canned reply, reproduced as an illegal `bestmove e2e3` on a board whose
e2 was empty. The first fix *guarded* the book (an `Allow_Opening_Book`
flag, set only for a genuine `position startpos` at the matching move
count). The project spec was then tightened to forbid hardcoded opening
positions outright (mandate H), so the book, its counter, the guard
flag and all UCI-side eligibility tracking were removed in a single
pass; every move of every game now comes from the search and decision
cascade. The first move of a fresh game changed from the canned `e2e3`
to the searched `e2e4`.

## Fixed: systematic edge-pawn-push bias in quiet positions

Reported directly by the user after a real game: `Prechess UCI 0.7.9`
(Black) replied to `1. e4` with `1...h5`, followed `2. d4` with `2...h4`,
and was mated in eight plies (`...f5`, `exf5 gxf5`, `Ng5 Bh6`,
`Qh5+ Kf8`, `Qf7#`) after the kingside pawn structure collapsed. The
`{0.00/3}` evaluation on every one of Black's moves up to the mate showed
this wasn't a missed tactic — the position was genuinely "equal" by the
legacy evaluation's own (material-only) accounting the entire time.

The root cause: once tactics are ruled out, the decision cascade's
"nothing distinguishes these moves" fallback rules scan every `(from,to)`
square pair in a fixed ascending order and, with no `exit`, simply keep
overwriting the chosen move with each further match — the *last* matching
pair in scan order wins, with no regard for whether it is a sound
developing move or a flank pawn push. Reproduced directly: a fresh engine
given `1. e4` and asked for Black's reply chose `h7h5`, matching the real
game exactly.

Fixed with a narrow, additive tie-break, `Quiet_Move_Score`, applied only
inside the specific fallback rule-blocks responsible ("no move here loses
anything," with and without tolerating check exposure, for pawns and for
any piece): among moves that already pass every one of the cascade's
existing safety checks unchanged, the one whose destination square is
closer to the center file is now kept, instead of whichever happens to be
scanned last. Nothing about *what counts as safe* changed — every
existing `Jogada_Perde*`/`Expoem_A_Xeque`/etc. condition is untouched;
only which of several already-equally-safe moves is picked. This is
deliberately not a hardcoded opening book (per the user's explicit
instruction): the same general centrality rule applies in any phase of
the game, wherever these specific fallback rules fire, rather than a
curated list of opening replies.

Verified: `1...h5` is gone (Black now replies `1...e5`; White's first move
is a central pawn push instead of `h2h4`); the `test_moves.adb` regression
suite is unaffected; a 20-position `bestmove` diff against the pre-fix
binary shows 16/20 unchanged, with the 4 differences being exactly this
class of change — `startpos` now opens `e2e4`-ish instead of `h2h4`, and
three endgame positions (`K+R` vs `K`, `K+Q` vs `K`, and one king-and-pawn
ending) shift between king moves/pawn moves that were already equally
"safe" by the legacy engine's own accounting before this fix, i.e. moves
it had no real basis for choosing between either way.

This is intentionally scoped to the specific fallback tier that produced
the reported failure (four rule-blocks: pawn-only and any-piece, each
with and without tolerating check exposure). The many other, more
specific rule-blocks in the same cascade (per-piece capture/threat rules,
and the deeper "loses a pawn/minor piece anyway" tiers) are untouched.

## Fixed: walking into short forced mates (root-level mate veto)

From a reported 8-move loss as Black (Legal's trap): 1.e4 e5 2.Nf3 d6
3.d4 Bg4 4.Bc4 Bh5 5.Nc3 Bg4 6.Nxe5 Bxd1?? 7.Bxf7+ Ke7 8.Nd5#. Two
separate failures, fixed separately.

**The fatal capture.** `6...Bxd1` wins the queen and loses the game:
mate arrives in two moves at no material cost. Neither existing
mechanism could see it -- the legacy `Mate`/`Exequemate` machinery only
detects a mate delivered by the opponent's IMMEDIATE reply (here
`Bxf7+` is check, not mate; the mate is one move later), and the
ply-4..10 chain compares material sums only. The fix follows the same
layering philosophy as the castling/en-passant integration: after the
cascade chooses a move, `Compute_Best_Move` applies it to a scratch
board and asks `Search_Integration.Has_Forced_Mate_Within_Two` whether
the opponent then has a forced mate in at most two of its moves,
starting with a check (quiet-first-move mates in two are outside its
scope; check-first covers the practically occurring short mates,
including every Legal-trap pattern). Move generation for this small
verification tree is the search's own pseudo-legal `Validade` filtered
by real check detection (`Is_In_Check`); castling and en passant are
ignored as escape resources, which can only make the test more
cautious, never less safe; pawns auto-queen. A failing move is vetoed
via `pprechess2.Jogada_Vetada`, folded into `Valid_Cache` -- the one
predicate every cascade tier already consults, so all ~40 rule blocks
respect the veto without touching any of them -- and the search re-runs
for its next-best choice (retry cap 4, time-budget aware; if every
choice mates, the engine is lost anyway and its original preference
stands). En-passant and castling overrides are verified the same way
before they may replace an already-verified legacy move. The veto
array is cleared around root selection and is always empty during PV
probes. Verified: the reported position now avoids `Bxd1`; cost off
the veto path is one scratch verification per move (milliseconds).

**The tempo shuffle.** `4...Bh5` and `5...Bg4` re-earned threat credit
every move: instrumentation showed the "threatens the queen" tier
firing for each hop, because the bishop's PIN-LINE threat against the
d1 queen (through the f3 knight) re-qualifies from every square of the
same diagonal -- `Analize3` flags a threat whenever the ply-3 capture
becomes available after some opponent reply (the knight moving away),
with no notion of "this threat already existed." Fix: a root attack
map (`Raiz_Ja_Ameacado`), computed once per search, marks every enemy
square the computer already attacks -- directly, or by slider X-RAY
through exactly one blocker (an existing pin/skewer). `Analize3` then
credits only threats against squares NOT in that map: maintaining an
existing threat, including sliding along the same pin line, is no
longer a reason to move. Check threats (`Ganho=999`) are exempt,
leaving the mate machinery's inputs untouched. Verified: after 4.Bc4
the engine now plays `Be6` (and `Ne7` a move later) instead of
shuffling; the pin-CREATING `3...Bg4` is still credited and still
played; the 20-position battery changed in exactly one position, where
the old choice re-attacked an already-attacked queen -- the rule
working as intended.

## Special-moves audit (castling / en passant / promotions)

Task-6 review of legal move generation and the three special moves,
with `test_special_moves.adb` (35 cases) as the gate.

**Verified correct as found:** `Is_Castle_Legal` implements the full
FIDE condition set -- rights, rook genuinely home, king not in check,
path squares empty, king's transit and landing squares unattacked, and
the queenside subtlety that b1 must be empty but MAY be attacked;
`Update_Rights_After_Move` revokes on king moves, rook moves, and
captures landing on rook home squares. `En_Passant_Candidate` tests the
capture hypothetically and rejects it when it would expose the mover's
own king (the classic horizontal-pin trap has a dedicated test).
Promotion and underpromotion input (q/r/b/n, both colors), capture-
promotions, and rights revocation by a promotion-capture on a rook home
square all round-trip correctly. The search generator's pawn
double-step correctly refuses to jump over pieces, and the legacy
author's en-passant-avoidance rule ("the computer never plays a double
step that could be EP-captured" -- his original workaround for not
implementing EP) turned out to be alive and working; it is preserved
as legacy behavior and documented here.

**Hardened (lying-FEN defenses):** castling rights claimed by a FEN
whose king is not on its home square are now refused (previously the
"castle" would have moved pieces from squares the king did not occupy);
and `En_Passant_Candidate` now verifies the EP target square is empty
and the bypassed pawn actually exists before its hypothetical
make/unmake, which could otherwise invent a pawn on an empty square or
delete a piece a lying FEN had placed on the EP target.

**Simplified, verified byte-identical:** `Validade` rebuilt the whole
8x8 `Quadro` mirror of the board on every call -- a 64-square copy per
node, tens of millions of times per deep search -- purely so the pawn,
bishop and rook handlers could read `quadro(r,c)`. Since the rebuild
copied from `Tabuleiro` at call entry, every such read equals
`tabuleiro((r-1)*8 + c)` at that moment; the handlers now index the
board directly and the rebuild is gone. Node counts and the 20-position
bestmove battery are identical before and after. Honest measurement:
no speed change (the compiler had effectively vectorized the copy to
insignificance) -- kept as a simplification, not claimed as a win.

**Removed: the hardcoded opening book.** Hardcoded opening positions
are forbidden by the project spec (mandate H). The two canned reply
branches, their `numero_de_meu_movimento` counter, the
`Allow_Opening_Book` eligibility flag and all its UCI-side tracking
were removed in one pass; every move now comes from the search. The
first move of a fresh game changed from the canned `e2e3` to the
searched `e2e4` -- an improvement, as it happens.

## Draw-rules review (threefold / 50-move / insufficient material)

A dedicated re-inspection of the FIDE draw rules and their interaction
with the search, requested by the user. Verified correct as-is:
`Make_Move_UCI`'s halfmove clock (pawn moves and captures reset it,
including en-passant captures and promotions; castling increments), the
`>= 100` half-move threshold, EP-square lifecycle, and the repetition
hash's inclusion of side-to-move, castling rights, en-passant square
and (since the hash-table review) king positions. Four issues found
and fixed:

1. **`bestmove 0000` on claimable draws was a forfeit hazard.** UCI has
   no draw-claim mechanism; GUIs adjudicate. The engine now reports an
   `info string` and plays on; `0000` is reserved for positions with no
   legal move. Verified: a genuine threefold position now yields the
   info string plus a real move; checkmate/stalemate still yield `0000`.
2. **KB-KB was treated as dead for any bishop colors.** With
   opposite-colored bishops a legal helpmate exists (e.g. Black Ka8
   blocked by its own dark-squared Bb8, White Kb6, light-squared white
   bishop checking along b7-a8), so FIDE Article 5.2.2 does not end
   the game; only same-colored KB-KB is dead. Bishop square colors are
   now compared. Related nuance, documented rather than changed:
   KNN-K and KN-KN are kept in the detected set per this project's
   spec, although strictly they too admit helpmates and are
   "unforceable" rather than dead -- harmless now that detection is
   advisory only. Likewise the repetition hash counts the EP square
   whenever a double-step just occurred, even if no EP capture is
   actually legal (strict FIDE compares EP *possibilities*); the
   effect is only ever to miss a claimable repetition, never to
   invent one -- the conservative direction.
3. **Per-game legacy counters leaked across games.**
   `Contagem_Empate` (the legacy draw-avoidance counter that biases
   cascade rule selection past a threshold) was never reset by
   `ucinewgame`; a second game in one process inherited a dead game's
   state. It now resets. (The opening-book counter found at the same
   time was later removed entirely with the book itself -- see
   "Removed: the hardcoded two-move opening book".)
4. **Crash: checkmate position as a fresh process's first search.**
   Found by the gate tests: `Constraint_Error` at `pvalidade.adb:188`.
   In ply-2 trials the opponent's reply can capture the computer's
   king; the per-trial king rescan found no king and left
   `Posicao_Do_Rei` stale -- uninitialized garbage on the very first
   search -- which then indexed `Validade`. Silently masked for years
   by the original script's `-gnatp` (the exact class of bug whose
   discovery led to removing it). The rescan now resets to 0 first and
   the check-exposure test is skipped when the king is absent; the
   sibling `Posicao_Do_Rei_Dele` use is guarded likewise, and both
   spec variables are now initialized.

**Gate suite.** `test_draw_rules.adb` (28 cases, all passing): genuine
threefold via king cycles; NON-repetition when only kings differ, when
castling rights changed (2 equal + 1 different = no claim; a third
equal recurrence = claim), and when EP availability differs; 50-move
boundary at exactly 100 half-moves, with reset checks for pawn moves,
captures, and en-passant captures, and increment checks for castling;
insufficient material for K-K, KB-K/K-KB, KN-K/K-KN, KNN-K/K-KNN,
KN-KN, same-color KB-KB (True) versus opposite-color KB-KB, KQ-K,
KR-K, KP-K, KNN-KN, KBB-K, KBN-K (all False).

## Hash-table review (Zobrist + transposition table)

A dedicated review of `bch_hash` and `tt_table`, requested by the user,
found one severe bug, one robustness gap, one dead subsystem, and --
while gate-testing the fixes -- a time-management quality bug.

**Severe: kings were not hashed.** `Hash_Piece` returned 0 for any code
outside -20..20, and kings are +/-999, so king positions contributed
nothing to the Zobrist hash. Any two positions differing only in king
placement collided; since the hash's single consumer is the
threefold-repetition history, the engine claimed false draws.
Reproduced before the fix: `4k3/8/8/8/8/8/R7/4K3 w` with kings walking
e1-d1-c1-b1 / e8-d8-c8-b8 -- six distinct positions, nothing ever
repeated -- produced an instant "draw by FIDE rule" / `bestmove 0000`
in a trivially won endgame. Kings now have dedicated Zobrist tables;
the false-draw repro plays on normally and the genuine-threefold
regression test (real king-cycle repetition) still detects TRUE.

**Robustness: `setoption name Hash` could kill the engine.** `Allocate`
had no `Storage_Error` handler, so requesting more memory than the
machine can give died on an unhandled exception. It already allocated
the new table before freeing the old; the handler now simply keeps the
old table and size on failure.

**The table was never used.** `Store_TT`/`Probe_TT` had no callers: the
table was allocated at startup, resized by `setoption`, cleared by
`ucinewgame` -- and never consulted. It now backs a cache for the
PV-extension probes: the legacy core is deterministic and sees only the
raw board (it knows nothing of castling or en passant), so
board-plus-side fully keys its choice; EP/castling are deliberately
excluded from the key to match that and maximize transposition hits.
An analysis GUI re-searches after every move with heavily overlapping
PV chains -- measured: a repeat analysis of the same position served
its entire 5-move PV extension from the table (~800 ms of probe
searches replaced by table reads), byte-identical PV. The cache is
never consulted for the root move actually played, so played-move
behavior is untouched (20/20 on the `bestmove` battery). One
documented approximation: the core's draw-avoidance counter can in
principle vary its choice for an identical board across a long game,
and the key does not include it -- acceptable for the cosmetic PV.

**Found while gate-testing: abort artifacts under a short clock.** At
`movetime` values below the deep chain's cost, the engine's move
flipped between runs and tiers inconsistently. Three mechanisms, all
fixed: (1) the mate/check-exposure scanner (`S_Lance`) had a time-abort
that left `Exequemate`/`Expoem_A_Xeque` computed for early root moves
and missing for later ones -- removed; the full ply-1..3 pass costs
tens of milliseconds and now always completes, with the clock enforced
by the expensive ply-4..10 chain instead. (2) `Quarto_Lance` treated
`Recovered=False` from a clock-interrupted `Quinto_Lance` as a genuine
"unrecoverable" verdict, spuriously flagging whichever move was being
vetted when time ran out -- now detected and discarded. (3) Even
honest partial deep flags bias the cascade (an unvetted bad move
passes strict tiers that correctly excluded vetted moves), so an
interrupted ply-4..10 pass is now discarded wholesale before the
cascade runs. Net effect: below the deep chain's time threshold the
engine plays the shallow (3-ply) engine's consistent choice; above it,
the deep choice -- a clean, reproducible degradation instead of an
arbitrary artifact of where the clock landed.

## Fixed: threat detection counted empty threats

Reported from a real game: after 1.e4 e5 2.Nf3 the engine (Black) played
`Qd8-f6`. Instrumenting the decision cascade showed the "threatens a
knight, may expose to check" tier chose it: `Analize3` set
`Jogada_AmeacaC` because the queen's ply-3 follow-up could capture the
f3 knight — without asking whether that capture would be *good*. The
knight is pawn-defended; queen takes knight, pawn takes queen. The
original author's own comment below `Analize2` concedes the point
("nem sempre que der true ai voce efetivamente vai perder…" — a True
here doesn't always mean the piece is really lost).

The fix is at the semantic root, in `Analize3`, applying to every
threat tier at once: a material threat now counts only if the target
square is undefended by the person (`Person_Defends`, the mirror of
`Protegida` for the other side — `Validade` itself supplies the
person's capture geometry, since the target square holds a computer
piece at the moment it is asked), **or** the capturing piece's value is
at most the captured piece's value (an even trade or a trade-up is a
real threat even against a defended piece). Check threats
(`Ganho=999`) always pass the value test, so their behavior is
untouched.

Verified: the engine now answers 2.Nf3 with `d7-d6` (one of
Stockfish's top choices in the user's reference dump), the
castling/en-passant/draw regression suite is unaffected, and the
20-position `bestmove` battery is 20/20 identical — the guard only
changes positions where a bogus threat was actually decisive.

## Multi-move principal variation (deepening `info` lines)

The user asked for Stockfish-style analysis output: progressively
deeper lines with a real multi-move PV, instead of a single static
`3/8` line with a one-move pv. The legacy core has no iterative
deepening to expose, so the PV is built the only honest way available:
after the root move is chosen, `Handle_Go` **replays the engine's own
move selection forward** on a scratch continuation — apply the root
move, ask the full engine (mirrored appropriately) what the opponent
would play, apply that, ask again, up to five extensions — emitting one
`info depth 3+k seldepth 8+k … pv m1 … m(k+1)` line per extension.
Every PV move is the engine's genuine choice at that node from a full
search (whose nodes are counted in the live `nodes` figure), so
`depth` honestly states the length of the line actually chosen, and
`seldepth` stays seven ahead for the ply-4..10 safety chain each of
those searches ran. In the reference position (after 1.e4 e5 2.Nf3)
the first extensions produce `d7d6 f1b5 c7c6` — the same line
Stockfish's own depth-3 iteration printed.

Details that matter:

- **Probe searches print nothing themselves**
  (`Search_Integration.Suppress_Info`): their internal candidate churn
  concerns a future position, not live root progress.
- **All disturbed state is saved and restored**: the board (the scratch
  continuation applies moves to `Tabuleiro` directly, including the
  root castle's rook hop, root en-passant removal, and auto-queen
  promotions), the opening-book counter (`numero_de_meu_movimento`,
  which every `Prechess2` call advances), the book-eligibility flag,
  and the draw-avoidance counter (`Contagem_Empate`, which every call
  updates). Verified by searching the same position twice in one
  process: identical results.
- **Score on deepening lines is the root score**, perspective-corrected,
  the way an iterating engine reports its root evaluation per
  iteration — not the drifting material sum of the mutated scratch
  board.
- **Time policy** (`Time_Management.Allow_PV_Probe`): under
  `go infinite`, `go depth` and `go movetime` the time is explicitly
  the engine's to spend, so probes may fill the budget (each still
  self-aborts through `Check_Time`); under real game clocks
  (`wtime`/`btime`) probes are permitted only inside the first quarter
  of the allocated span, so the engine keeps its fast-moving habit
  rather than burning clock on display cosmetics. An aborted probe's
  half-chosen move is discarded, and the PV simply stays short under
  time pressure.

## Plies 4 through 10: design rationale

The legacy 3-ply structure only ever asks "does this root move's *own*
reply lose material" (`Analize2`'s `Jogada_PerdeX`, one ply after the root
move). It never asks whether the computer's own *follow-up* plan
(`Terceiro_Lance`'s ply-3 move) walks a piece into a square the opponent
can immediately take, nor whether the computer could simply take it right
back. `Quarto_Lance` (ply 4) and `Quinto_Lance` (ply 5) close that gap
together, added at the user's explicit request, as a deliberate, scoped
*behavior* change rather than a refactor — a root move the 3-ply structure
considered "safe" can now be passed over if it isn't safe after both
sides' best replies two and three moves out.

**Design.**

- `Quarto_Lance` simulates every legal reply the opponent has to the
  computer's ply-3 move (mirroring `Segundo_Lance`'s shape); `Analize4`
  records, per piece type, whether that reply recaptures material
  (`Jogada_Perde2P/B/C/T/D/R` — informational bookkeeping only, not read
  anywhere in the decision cascade).
- For each such opponent reply, `Quinto_Lance` then simulates every legal
  follow-up the *computer* has (mirroring `Terceiro_Lance`'s shape), and
  sets `Recovered := True` the moment any of them brings the running
  material sum back to at least what it was just before the ply-3 move
  started this exchange. All three running-sum updates (ply 3/4/5) are the
  same O(1) delta pattern used by every other ply in this file.
- `Quarto_Lance` sets the single combined flag `Jogada_Perde_Profunda` for
  a root move only if it finds an opponent ply-4 reply for which
  `Quinto_Lance` found **no** recovering ply-5 continuation — i.e. a
  properly minimax-shaped check (the opponent's move is fixed, the
  computer's answer is chosen optimally), not a blanket "any recapture is
  bad" flag. `Jogada_Perde_Profunda(A,B)=False` is required by every
  decision-cascade rule that already checks `Expoem_A_Xeque(A,B)=False` —
  the codebase's own marker for its cautious/"safe" rule variants, as
  opposed to the deliberate "podendo expor a Xeque" risk-accepting fallback
  variants, which are left untouched — mirroring exactly how
  `Jogada_PerdeR(A,B)=False` is already used as a blanket one-ply-deep
  safety screen throughout the same cascade.

**Why not stop at ply 4.** A `Quarto_Lance`-only version (shipped briefly
during development) flagged *any* ply-4 recapture as unsafe, which is too
pessimistic: winning a knight (value 4) and having a bishop (value 3)
recaptured back is a *good* trade, not a loss, but the ply-4-only check
couldn't tell the difference. Ply 5 (`Recovered`) is exactly the check
that tells the difference, so once it existed the ply-4 logic was
corrected to use it rather than shipping two slightly-inconsistent
notions of "safe" side by side.

**Early exit, both directions.** Both `Quinto_Lance` and `Quarto_Lance` use
a named-loop `exit ... when` the instant they have the answer they need
(one recovering ply-5 move is enough; one unrecoverable ply-4 reply is
enough), and `Quarto_Lance` returns immediately on entry if
`Jogada_Perde_Profunda` is already set for this root move from an earlier
`Terceiro_Lance` trial. In practice this makes the ply-4/5 pair *faster*
than the ply-4-only version it replaced: most real replies have a quick
recapture, so `Recovered` usually flips true within the first few ply-5
tries.

**Reported as `seldepth 8`, not `depth 8`.** None of plies 4-8 repeat
the mate/check-exposure detection the first three plies perform — this
is a targeted material-safety check, not a full 8-ply search — so
`seldepth` (selective depth) is the correct UCI field, the same way a
real engine's `seldepth` exceeds its nominal `depth` during capture or
check extensions.

**Extended to 8, then 10 plies (`Sexto_Lance`/`Setimo_Lance`/
`Oitavo_Lance`, then `Nono_Lance`/`Decimo_Lance`).**
At the user's request the same matched-pair pattern was carried three
plies further: when `Quinto_Lance` finds a candidate ply-5 recovery
(quick material test passes), the candidate is now *verified* before it
counts —

- `Sexto_Lance` (ply 6, opponent): scans the opponent's replies to the
  applied ply-5 move, but examines only those that drop the running sum
  back **below** `Soma2l` — replies that keep the exchange at or above
  break-even need no answer, and skipping them is what keeps the deep
  chain cheap (usually zero to a handful of genuine counter-captures).
- `Setimo_Lance` (ply 7, computer): for each such counter-capture, looks
  for one computer answer that restores the sum to at least `Soma2l`
  **and** survives ply 8.
- `Oitavo_Lance` (ply 8, opponent): originally the pessimistic leaf;
  since plies 9/10 were added (at the user's request, same pattern
  carried two plies further) it verifies instead of assuming, exactly
  as `Sexto_Lance` does one exchange up: a ply-8 counter-capture below
  `Soma2l` only refutes if `Nono_Lance` finds no surviving answer.
- `Nono_Lance` (ply 9, computer): mirror of `Setimo_Lance` — one
  answer restoring the sum to at least `Soma2l` that survives ply 10.
- `Decimo_Lance` (ply 10, opponent): the leaf. Any opponent reply
  dropping the sum below `Soma2l` refutes the ply-9 answer under test.
  Deliberately pessimistic — a ply-11 recapture is beyond the horizon,
  the same limitation the ply-4-only version had — but six plies
  deeper, where the error is far less consequential; any fixed-depth
  check must cut off somewhere.

Early exit at every level (one refutation / one surviving answer / one
unanswerable counter-reply is always enough), and `Sexto_Lance` and
`Oitavo_Lance` check the time budget on entry: on abort they return
with the deeper verification skipped, so under time pressure the check
degrades gracefully to the shallower verdict instead of spuriously
flagging moves it never finished analyzing.

**Cost (measured, native build, same 20-position battery plus sharp
tactical middlegames):** at 8 plies, typical quiet positions ran
~40-120 ms with a ~200 ms sharpest case; at 10 plies, ~80 ms-1.1 s
across the same set — a further ~2-5x, still fine for analysis and for
blitz-with-increment (the time-abort guards cap it under a real
clock). The 20-position `bestmove` diff came back **20/20 identical**
at each extension (5→8 and 8→10 plies): at this battery's depth the
extra plies confirm the shallower verdicts rather than overturn them,
which is exactly what a verification layer should do. A tight
`movetime 60` test answered on time with the same move, confirming the
graceful-degradation path.

**Extending further.** An 11th ply (or beyond) would need this same
cost/behavior exercise repeated: there is no natural "search one ply
deeper" knob, since this is not alpha-beta with a numeric evaluation,
and the cost roughly multiplies with each opponent/computer pair added
— the 10-ply chain already reaches ~1 s on sharp middlegames, so the
next pair is likely to need pruning smarter than early-exit alone.

## Verification methodology

Every change above (except where explicitly called out as an intended
behavior change) was verified as behavior-preserving via:

1. **A scripted 20-position `bestmove` diff** between the pre-change and
   post-change binaries, covering openings, midgame captures/threats,
   castling both sides, promotion, and won/drawn endgames.
2. **The existing castling/en-passant/promotion/repetition/50-move
   regression suite** (`test_moves.adb`), a throwaway direct unit-test
   harness that drives `Search_Integration.Make_Move_UCI` directly and
   dumps board/rights state, run after every change in this document.
3. **Cross-compilation and execution** of the actual Win64 binary (via a
   MinGW cross-compiler and Wine) to confirm the shipped artifact, not
   just a native Linux build, behaves as expected.

For the two changes marked as deliberate behavior changes (ply 4 and ply
5), the same 20-position diff was used to characterize *what* changed
(2 of 20 positions, both benign king-shuffle tie-breaks in bare endgames)
rather than to prove nothing changed.

## Fixed: three `info`-line reporting defects

All three were display/reporting defects only — none affected which move
the engine actually played — but together they made the GUI's analysis
panel actively misleading:

1. **Score perspective flipped between intermediate and final lines when
   Black was to move** (previously documented here as a known issue, now
   fixed). UCI defines `score cp` from the side to move. While the board
   is mirrored for a Black search, the raw material sum is already
   side-to-move-positive, so the *intermediate* lines were right — it
   was the *final* line, printed after the board flips back to
   White-positive, that reported from the wrong perspective. Fixed with
   `Search_Integration.Report_For_Black`, which (unlike
   `Search_Is_Mirrored`, cleared at flip-back) stays set through the
   final report; `Report_UCI` negates the raw sum exactly when the board
   is unmirrored and the search was for Black. Verified with
   queen-odds positions in all four color/side combinations:
   intermediate and final lines now always agree, from the side to
   move's perspective.
2. **The quiet-move fallback flooded the GUI with candidates it wasn't
   keeping.** When the centrality tie-break was first added, the
   `Report_UCI` call stayed where the legacy code had it — after every
   *match* — while `cc`/`dd` only updated on tie-break *acceptance*, so
   the GUI received a `pv` line for every scanned quiet move (20 lines
   in the user's reported dump), most of which were never the actual
   candidate. `Report_UCI` now sits inside the acceptance branch: only
   retained candidates are announced, matching the documented "refreshed
   every time the search improves its root candidate" behavior.
3. **`nodes` (and therefore `nps`) accumulated across searches for the
   life of the process.** `TT_Types.Nodes_Searched` was never reset, so
   a GUI analyzing several positions saw earlier searches' nodes folded
   into the current line (the user's dump showed ~5M nodes for a
   ~0.5M-node position). Reset to zero at the start of every `go`.

One further note from the same report: a GUI dump showing internal
(mirrored, White-side) coordinates like `Nb1-a3` for a Black-to-move
position matches the behavior of a build *before* the display
un-mirroring in `Report_UCI`; the current binary was re-verified on both
the `position fen` and `position startpos moves` paths and prints real
board coordinates in every line. If mirrored coordinates appear in the
GUI, the loaded engine executable is stale — compare its SHA-256 against
`distribution/prechess-0.7.9-checksums.txt`.
