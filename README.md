# Prechess UCI 0.7.9.9

Prechess is an Ada chess engine originally written around 2001–2002 as a
graphical Windows program (`prechess.adb` + `adagraph2000.dll`). Version
0.7.9 wraps the original engine in a standard text-based **UCI** front end
(`prechess_uci.adb`) that any UCI GUI can drive, while deliberately
preserving the legacy fixed-priority move-ordering and evaluation cascade in
`pprechess2.adb`. Every release since 0.7.8 has added correctness fixes or
root-level heuristics *around* that legacy cascade, never rewritten it. See
the changelog below for what changed release by release, and the Architecture
section for how the legacy core and the newer layers fit together.

> **Authorship**
> - **José Lauro Strapasson** — original *Prechess 0.7.8*: the legacy engine
>   and its search, which 0.7.9 preserves.
> - **Arthur Matheus** — all changes and fixes after 0.7.8 (the UCI front
>   end, FIDE rules, time management, legal-move corrections, and the
>   additive search improvements described below).

## License

Released under the MIT License — see `license.txt` for the full text.
Copyright (c) 2026 José Lauro Strapasson & Arthur Matheus.

## Changelog

Newest first. Each entry lists only the substantive, verified change and
result for that release — see the gate files under `implementation/gates/`
for full process detail if needed.

### v0.7.9.9

- Stage-1 code review: 15 findings (3 high, 9 medium, 2 low, 1 info), no
  blockers.
- Replay hardening: malformed move tokens (bad length/suffix, invalid
  castling/en-passant shape) are now rejected before board/history mutation.
- `go perft 0` reports `perft 0 1` instead of falling into a normal search;
  `go perft` rejects depths above the local bound 6.
- Several test harnesses now set a failing exit status on failure instead of
  only printing a message (`test_hashfull`, `test_time_management`,
  `test_tt_multibucket`, `test_uci_replay`); `test_endgame` is now
  self-checking with an explicit `PASS` marker.
- Five move-selection trials (castling root-priority, flank-pawn tie-break,
  a root-correction candidate, a `W:R|B:K` endgame overlay, and a
  determinism/state-repeatability check) were all tried and rejected —
  none improved the focused or full 732-position regression set, which
  stayed neutral at `335/732` with a byte-identical result CSV.
- **Post-release hotfix — root safety veto:** added
  `Quiet_Move_Worsens_Material`, which vetoes a quiet root move when the
  opponent's best reply anywhere on the board becomes at least as good as
  before and is worth at least a minor piece — closing a gap where the
  existing `Root_Piece_Hangs` check only looked at the moved piece's own
  destination square. Fixed 4 user-reported positions from `0/4` to `3/4`;
  full regression improved to `345/732`.

### v0.7.9.8

- Added a Prechess-only expected-move regression workflow
  (`tester/prechess_expected_moves.py`) sourcing positions and
  Stockfish-validated expected moves from `tester/regresion.py`.
- Targeted root corrections: non-tempo flank-pawn shove suppression,
  a castling-priority review, and `Best_Non_Losing_Capture` (SEE-neutral-or-
  better non-pawn captures only).
- Added `Best_Opening_Trap_Response`, recognizing 15 named opening/middlegame
  traps and playing the correct non-poisoned response: Légal's trap,
  Giuoco Piano pinned knight, Damiano Defense, QGD Elephant Trap, Caro-Kann
  `Nd6#` trap, Scotch Siberian Trap, Sicilian Richter-Rauzer, Italian
  premature-bishop/b7 motif, Blackburne Shilling Gambit, Ruy Lopez Exchange,
  French `Nb5` trick, and several defended-pawn/rook-coordination motifs.
- Full expected-move result improved `293/665` → `300/665`.
- Two trials rejected for regressing the full set: an opening
  central-duo heuristic (`295/665` → `290/665`) and a KQ-vs-KR endgame
  overlay (`296/665` → `295/665`). Confirms the project rule against
  FEN-specific patches or lookup tables.

### v0.7.9.7

- Replaced the single-phase piece-square tables with tapered PeSTO
  middlegame/endgame tables (all piece types) in `pprechess2.adb`, driven by
  a root game-phase calculation (0–256) with interpolation.
- Preserved the proven 0.7.9.6 opening pawn tie-break at pure middlegame
  phase so PeSTO alone couldn't re-rank flank shuffles above central play.
- Ada 2022 cleanup: renamed core types to `Square`/`Board_Array` in
  `pvalidade.ads`. Added `test_pst_tapered.adb`.
- Perft remained exact (startpos `4,865,609`; Kiwipete `193,690,690`).

### v0.7.9.6

- Requested-position release: three generic root corrections — a black
  central-pawn capture rule (unless the enemy queen directly attacks
  f7/f2), a knight pawn-tempo kick, and an advanced central-pawn recapture.
- Regression battery held `15/15`; perft and the plies 4–16 safety chain
  unchanged from 0.7.9.5.

### v0.7.9.5

- Extended the legacy deep tactical safety chain (`Jogada_Perde_Profunda`)
  from plies 4–10 to **plies 4–16**; `seldepth 16` now reported.
- Code-review fixes: the release build only publishes after every gate
  passes; the regression test is now mandatory (a missing
  Python/Stockfish/reference binary fails the build, it no longer skips
  silently); unit tests run on a checked profile (no `-gnatp`); fixed the
  `hashfull` gate; special-move fallback now checks en passant/castling
  before emitting `bestmove 0000`; corrected FIDE dead-position handling
  (KNN-K/KN-KN are no longer auto-drawn since mate is still possible;
  KNN-KP no longer collapses; same-color-bishop KBB-K is dead, opposite-
  color KBB-K can still mate).
- Simplification cleanup: removed redundant code, reused helpers, avoided
  expensive endgame scoring on illegal trial moves.
- Still no alpha-beta/quiescence/iterative-deepening/minimax — the original
  fixed-priority cascade, just with a deeper safety chain.

### v0.7.9.4

- Added the UCI `hashfull` metric: an O(1) exact occupancy counter in
  `tt_table`, gated by `test_hashfull.adb`.
- Root-layer opening-blunder filter added alongside (not inside) the legacy
  cascade: `Is_Bad_Queen_Sortie`, `Is_Premature_Flank_Bishop`,
  `Is_Early_Queen_Develop`, `Best_Central_Pawn_Capture`,
  `Best_Reinforce_King_Bishop_Pawn`, `Best_Natural_Development`.
- Behavior-preserving code-quality cleanup: `bch_hash`'s catch-all now
  raises instead of silently returning 0; hoisted repeated reads and merged
  guards in `move_gen`/`search_integration`/`pprechess2`; early-exit added
  to the hot loop in `Protegida`.

### v0.7.9.3

- Engineering-hardening and verification release; legacy cascade preserved
  byte-for-byte versus 0.7.9.2.
- **Technique audit:** confirmed the engine has no alpha-beta, iterative
  deepening, quiescence search, LMR, null-move pruning, futility pruning,
  razoring, killer/history heuristics, or SMP — it is a fixed 3-ply
  priority cascade plus the plies 4–16 safety chain plus a PST tie-break;
  the transposition table is a PV-display cache only.
- Removed dead code (`Comerei`, `Jogada_Perde2*`/`Analize4`, `Quadro`, the
  `adagraph2000.dll` dependency from the UCI build).
- New `move_gen` package: a real legal move generator (en passant, castling,
  promotions) plus `go perft N`. Exact perft confirmed: startpos depth 5 =
  `4,865,609`; Kiwipete depth 4 = `4,085,603`.
- Draw rules made explicit: threefold repetition requires a true third
  occurrence; only *capturable* en-passant targets affect repetition
  identity; fixed KNN/KN dead-position misclassification.
- Endgame heuristics added: KQ/KR/opposite-color-KBB/KP-vs-K confinement
  bonuses, rook-pawn corner-draw detection, and a `Best_Endgame` root
  override.
- Regression: 2/7 opening positions passed against Stockfish; the remaining
  5 share one root cause (deep-chain over-pessimism, see Legacy limitations
  below). ~160M nodes/sec with PGO+LTO.

### v0.7.9.2

- Transposition table rewritten from always-replace single-entry to a
  **4-bucket-per-cluster** layout with generation-tagged replacement
  (refresh exact key → empty bucket → shallowest depth, ties broken by age).
  Gated by `test_tt_multibucket.adb`.
- Added root-layer heuristics for winning captures and en-prise resolution:
  `Best_Winning_Capture`, `Best_En_Prise_Resolve`, `Is_Soft_Defend`,
  `Best_Development_Vs_Hanging_Pawn`, `Best_Pawn_Tempo_Kick`,
  `Best_Absolute_Pin_Save`, `Is_Self_Discovery`.
- Fixed `Is_Soft_Defend` misclassifying a fully-defended piece (SEE = 0) as
  a soft cling; it now requires the threat to still exist after the move.
- Introduced the real build test gate in `build_uci.bat` (previously a
  no-op `echo`): the build now runs the Ada unit tests plus the
  Stockfish/0.7.9.1 regression battery and refuses to package on any
  failure or regression — this gate is what caught the `Is_Soft_Defend` bug.
- UCI hardening: guarded garbled bestmove tokens and overlong FEN ranks,
  raised the input buffer from 1024 to 65,536 bytes, `go infinite` now
  exits cleanly on EOF/quit.
- Post-release fix: `Mirror_Square(0)` no longer crashes on a terminal
  Black mate/stalemate.

### v0.7.9.1

- **Headline fix:** replaced the 0.7.9 fallback tie-break (destination-file
  centrality only) with real per-piece piece-square tables
  (`PST_Pawn/Knight/Bishop/Rook/Queen/King`), made side-relative via
  `Flip_Board` mirroring.
- Verified against Stockfish `dev-20260720`: the king no longer walks into
  the center, knights/bishops avoid the rim/back rank; battery improved
  from `0/6` to `3/6`.
- The remaining `3/6` failures (an even-trade admission and a positional
  pawn sacrifice) regress other positions when attempted — documented as a
  known limitation rather than forced.
- Repaired `build_uci.bat` (it referenced non-existent `docs/`/`LICENSE`
  paths); renamed `README_UCI.md` to `README.md`; the distribution now
  ships the correct MIT `license.txt` (the prior ZIP had stale BSD text).
- Confirmed single-threaded: no Ada tasking anywhere in the engine.

### v0.7.9

- Full UCI front end (`uci`/`isready`/`ucinewgame`/`position`/`go`/`stop`/
  `quit`/`setoption`), replacing the legacy Adagraph GUI loop.
- FEN parsing now reads all six fields (previously board-only); live `info`
  reporting; fixed the Black score sign, quiet-move info flooding, and
  per-`go` node-count reset.
- **Fixed the "Black-only" bug** — a one-rank board-mirroring error; both
  colors now share one tested move-application path.
- Reworked time management: every standard UCI time-control shape is parsed
  and honored, with fixed overhead reserved.
- Added castling (full FIDE legality), en passant (with a self-check test),
  and correct promotion/underpromotion reporting; hardened against lying
  FENs. Gated by `test_special_moves.adb` (35 cases).
- Wired up FIDE draw rules: threefold repetition and the fifty-move rule via
  a real Zobrist hash (kings are now hashed, fixing a false-repetition bug);
  insufficient material per FIDE Art. 5.2.2.
- Added the plies 4–16 tactical safety chain and a forced-mate veto (fixes
  Légal's trap).
- Removed the hardcoded two-move opening book (out of spec) and the
  blanket `-gnatp` suppression that had been masking a real
  `Constraint_Error`.

### v0.7.8 (legacy baseline)

- Core search/eval in `pprechess2.adb`: a fixed, non-recursive 3-ply
  look-ahead over every from/to square pair, with hand-tuned heuristics
  (capture priority, hanging-piece detection, simple mate-in-1/2) — not
  minimax or alpha-beta.
- Pseudo-legal move-shape checking in `pvalidade.adb`: no castling; en
  passant handled only by forbidding the double pawn step that would allow
  it (never actually implemented).
- Rudimentary xboard support plus an Adagraph2000 Windows GUI
  (`prechess.adb`, `papresentacao.adb`, `adagraph2000.dll`).
- Two significant defects, both fixed in 0.7.9: the engine played
  correctly **only as Black**, and time management was broken.
- No FEN parsing, no draw-rule detection.

## Architecture

### Overview

The legacy 3-ply fixed-priority cascade in `pprechess2.adb` is the engine's
playing character and has been preserved unchanged in its move-ordering
logic since 0.7.8. Every later release adds behavior *around* it rather than
inside it: a UCI protocol front end, real move/game-state tracking the
legacy core never had (castling rights, en passant, draw rules), and a small
number of root-level heuristics and safety checks that can override the
cascade's choice at the root only, never during its own trial search. There
is no alpha-beta, minimax, quiescence search, or iterative deepening
anywhere in the engine.

### FIDE rules

All draw-rule logic lives in `search_integration.adb`:

- **Threefold repetition** — `Is_Threefold_Repetition`, driven by a
  Zobrist-hash history (`History`/`History_Count`, up to 4096 plies) pushed
  on every move and FEN load. Only a *capturable* en-passant target affects
  the repetition identity of a position.
- **Fifty-move rule** — `Is_Fifty_Move_Rule`: true once the half-move clock
  reaches 100 (50 full moves).
- **Insufficient material** — `Is_Insufficient_Material`, implementing FIDE
  Art. 5.2.2 exactly: K-K, KB-K, KN-K, and same-color-bishop KB-KB are dead
  positions; KNN-K, KN-KN, and KNN-KP are explicitly *not* treated as dead
  since mate or promotion is still legally possible.
- **Combined draw check** — `Is_Draw` ORs the three checks above and reports
  the result as an `info string` (UCI has no draw-claim command, so the
  engine keeps playing).
- **Stalemate / checkmate** — detected at the UCI root in
  `prechess_uci.adb`: when the legacy cascade plus the en-passant/castling
  fallback finds no legal move at all, the engine emits `bestmove 0000`. A
  matching stalemate guard also exists in `search_integration.adb` for the
  post-move board.

### Endgame handling

Also in `search_integration.adb`, additive root-layer overlays (never a
replacement for the legacy cascade's own choice):

- `Side_Endgame_Bonus_Cp` — recognizes two mating regimes: KQ-K / KR-K /
  opposite-color-bishop KBB-K (rewards driving the defending king to the
  edge and shrinking its escape squares; same-color KBB-K is excluded since
  it cannot force mate), and KP-K (rewards pawn advancement, the attacking
  king escorting its pawn, and an opposition term).
- `Endgame_Is_Draw` — detects the classic "wrong rook pawn" corner draw
  (lone king sitting on the promotion corner of the defender's own a-/h-file
  pawn).
- `Best_Endgame` — the root override that fires only once a recognized
  endgame bonus is active, and picks whichever legal move most improves it.

There is no true tablebase (no exact KPK/KRK solver) — this is heuristic
scoring only. A KQ-vs-KR overlay trial (0.7.9.8) and a `W:R|B:K` overlay
trial (0.7.9.9) were both tried and rejected for regressing the full
regression set.

### Legacy engine limitations

- **Fixed, non-recursive 3-ply search** with hand-tuned heuristics — not a
  general search algorithm, so it cannot be deepened or pruned the way a
  conventional engine can.
- **Non-standard piece values** (P=1, B=3, N=4, R=7, Q=20): the board
  encoding uses a piece's value as its identity, so `Validade`, material
  sums, and roughly 40 cascade comparisons all depend on these exact
  numbers. Moving to a modern 1/3/3/5/9 scale would require decoupling
  identity from value — a rewrite, not a tweak.
- **Deep-chain over-pessimism**: `Jogada_Perde_Profunda` flags a move as a
  deep loss whenever the opponent wins material in *any* computer ply-3
  reply, even if the engine would simply avoid that reply — in open
  positions this over-flags nearly every move. A minimax rework was tried
  for 0.7.9.1 but regressed other positions, so it remains deferred.
  This is the shared root cause behind most of the engine's known
  regression-test misses (see the Opening development and Middlegame
  groups in the regression tooling under `tester/`).
- **No positional evaluation** beyond material, the tactical safety chain,
  and the PST/PeSTO tie-break: openings are theory-neutral, slow
  entrapment and quiet preparatory tactics are only partially covered, and
  the forced-mate veto only catches mates starting with a check within two
  of the engine's own moves.

## Compilation and build

The distributable build is always produced by `build_uci.bat` at the repo
root — never by ad hoc compiler invocations. Prerequisites: GNAT/MinGW on
`PATH` (script aborts if `gnatmake` isn't found), Ada 2022 mode
(`-gnat2022`) throughout.

1. **Clean** — wipe `compilation\` and any stray build artifacts, recreate
   `compilation\` and `distribution\`.
2. **PASS 1 — instrumented build** (`-fprofile-generate`) into
   `prechess-pgo-instr.exe`.
3. **PGO training run** — a fixed UCI workload (startpos, an opening line,
   two custom FENs) fed to the instrumented binary via stdin redirection;
   retried up to 6 times for scan/timing flakiness. Requires at least one
   `.gcda` profile to proceed.
4. **Wipe objects** (keep the `.gcda` profiles).
5. **PASS 2 — optimized build** (`-fprofile-use -fprofile-correction`) into
   `compilation\prechess-<VERSION>-win64.exe`.
6. **Clear stale release artifacts** in `distribution\` before gating, so a
   failed gate never leaves an ungated exe next to stale archives.
7. **Test gate, part 1 — Ada unit tests**: all 8 tests
   (`test_draw_rules`, `test_special_moves`, `test_tt_multibucket`,
   `test_endgame`, `test_hashfull`, `test_pst_tapered`, `test_uci_replay`,
   `test_time_management`) compiled on a checked profile (`-gnata -gnatVa
   -gnato -O0`, no `-gnatp`/PGO/LTO) and run; each must print its own
   `PASS` marker.
8. **Test gate, part 2 — regression battery**: when Python, the test
   positions, the Stockfish oracle, and the 0.7.9.1 reference binary are
   all present, compares Stockfish / 0.7.9.1 / the freshly built binary;
   any failure (including a missing prerequisite) blocks packaging.
9. **Publish** — only on full gate success: copy the exe, `license.txt`,
   and `README.md` into `distribution\`.
10. **Stage and zip** — exe + `README.md` + `license.txt` at the ZIP root,
    the shipped `.adb`/`.ads` + test sources under `SRC\`.
11. **Checksums** — SHA-256 of the exe, ZIP, and `license.txt`.
12. **Build logs** copied into both `compilation\` and `distribution\`.

Final outputs (version 0.7.9.9): `compilation\prechess-0.7.9.9-win64.exe`,
`distribution\prechess-0.7.9.9-win64.exe`,
`distribution\prechess-0.7.9.9-win64.zip`,
`distribution\prechess-0.7.9.9-build.log`,
`distribution\prechess-0.7.9.9-checksums.txt`.

## UCI options

The engine exposes exactly one option:

- **`Hash`** (`spin`, default `16`, min `1`, max `4096`, megabytes) — resizes
  the transposition table via `setoption name Hash value <MB>`. Out-of-range
  values are clamped; malformed values are ignored and the current size is
  kept. Safe to change between searches since the engine is single-threaded.
  No `Threads`, `Ponder`, or `Contempt` options exist.

## Source files

**UCI front-end**
- `prechess_uci.adb` — the UCI protocol loop and command dispatch
  (`uci`/`isready`/`ucinewgame`/`position`/`go`/`setoption`/`stop`/`quit`,
  plus `go perft N`); wires together move validation, search integration,
  the legacy engine, the transposition table, hashing, and time management;
  also holds the root safety-veto and trap-response helpers.

**Legacy engine (0.7.8-era, preserved)**
- `pprechess2.ads` / `pprechess2.adb` — the fixed-priority decision cascade
  and 3-ply trial search; the plies 4–16 safety chain; the tapered PeSTO
  piece-square tables (0.7.9.7).
- `prechess.adb` — the original graphical/xboard entry point; not part of
  the UCI build.
- `papresentacao.ads` / `papresentacao.adb` — the legacy Adagraph2000 GUI
  presentation layer.

**Move generation / validation**
- `pvalidade.ads` / `pvalidade.adb` — the legacy per-piece pseudo-legal
  shape checker (`Validade`); owns the global board array. No castling/en
  passant/promotion concept.
- `move_gen.ads` / `move_gen.adb` — a complete legal move generator plus
  `Perft`/`Perft_Divide`, kept separate from the cascade so `go perft`
  cannot affect move-selection semantics.
- `move_validation.ads` / `move_validation.adb` — castling rights, the
  en-passant target square, and derived legality (attacked-square/check
  detection, castling legality) layered on top of the legacy board.

**Search integration / rules / evaluation**
- `search_integration.ads` / `search_integration.adb` — FEN parsing,
  Zobrist-backed game history and draw rules, `info`/score reporting, the
  endgame overlay, and the accumulated root-level move helpers (winning
  captures, trap responses, the root safety veto, etc.).

**Transposition table / hashing**
- `tt_types.ads` — shared types (`Hash_Key`, `Score_Type`, `TT_Flag`,
  `Move_Type`, `TT_Entry`) and the node counter.
- `tt_table.ads` / `tt_table.adb` — the 4-bucket-per-cluster transposition
  table (`Init_TT`/`Resize_TT`/`Clear_TT`/`Probe_TT`/`Store_TT`,
  `Hash_Full_Permille`).
- `bch_hash.ads` / `bch_hash.adb` — Zobrist hashing, including dedicated
  king hash arrays.

**Time management**
- `time_management.ads` / `time_management.adb` — all UCI time-control
  shapes (`Fixed_Depth`, `Time_Per_Move`, `Tournament`, `All_In`,
  `Infinite`); sudden-death assumes 30 remaining moves; 20 ms overhead
  reserved per budget.

**Tests**
- `test_draw_rules.adb` — repetition, fifty-move, insufficient-material.
- `test_special_moves.adb` — castling, en passant, promotion boundaries.
- `test_endgame.adb` — endgame bonus scoring and `Best_Endgame` selection.
- `test_hashfull.adb` — `hashfull` occupancy counter correctness.
- `test_pst_tapered.adb` — tapered PeSTO phase/interpolation correctness.
- `test_tt_multibucket.adb` — multi-bucket TT replacement policy.
- `test_uci_replay.adb` — illegal/legal move-token replay handling.
- `test_time_management.adb` — UCI time-control boundary cases.
