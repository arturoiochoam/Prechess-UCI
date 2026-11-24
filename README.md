# Prechess UCI 0.9.9.17.34

Prechess is a chess engine written in Ada. Originally developed around 2001–2002 as a graphical Windows application (`prechess.adb` with `adagraph2000.dll`), it relied on a custom three-ply heuristic search cascade ('prechess2.adb'). In version 0.7.9, the program was converted into a standard text-based Universal Chess Interface (UCI) engine (`prechess_uci.adb`) compatible with all chess GUIs, adding side-to-move orientation handling so the engine plays both White and Black pieces.

Development from version 0.7.9 through version 0.9.9.17.34 added complete FIDE rule validation, a legal move generator with perft baselines, draw detection, tournament time controls, and a multi-bucket transposition table. Outer layers added tapered piece-square tables, static exchange evaluation, and an auxiliary alpha-beta verification search (`tactical_search.adb`) breaking positional ties while preserving the original playing character. All modern extensions operate at the root or as post-search verification, leaving the internal legacy cascade intact.

Because the legacy search cascade relies on unpruned nested procedural loops, deep tactical calculation is structurally bound by its three-ply horizon. Technical descriptions of each successive release, including tactical vetoes, protocol adjustments, and test suites, are documented in the changelog section below.

> **Authorship**
> - **José Lauro Strapasson** — original *Prechess 0.7.8*: the legacy engine
>   and its search, which 0.7.9 preserves.
> - **Arthur Matheus** — all changes and fixes after 0.7.8 (the UCI front
>   end, FIDE rules, time management, legal-move corrections, and the
>   additive search improvements described below).

## Language: Ada 2022

## License

Released under the MIT License — see `license.txt` for the full text.
Copyright (c) 2026 José Lauro Strapasson & Arthur Matheus.

## Changelog

### v0.7.9.9 (consolidated release, v0.7.9.1–v0.7.9.9)

Added
- Full legal move generator in `src/move_gen.ads/.adb` supporting castling, en passant, and pawn promotions with perft divide validation.
- Standard draw rule enforcement covering fifty-move limits, threefold repetition, and insufficient material dead positions.
- Multi-bucket transposition table layout in `src/tt_table.ads/.adb` with 4 buckets per cluster and depth-preferred replacement.
- Dual-phase tapered PeSTO piece-square tables in `src/eval_terms.ads/.adb` providing positional tie-breaks across game phases.
- Deep material safety verification chain (`Jogada_Perde_Profunda`) extended up to ply 16 in `src/pprechess2.adb`.
- Root opening-blunder filter and positional safety rules screening known early tactical traps.

Improved
- Move validation speed: verified candidate move legality through direct generation rather than trial execution.
- Move selection among equal material candidates: broke heuristic ties using positional piece placement and central control bonuses.
- Transposition table hit rates: reduced hash collision overwrites through multi-bucket clustering and occupancy tracking (`hashfull`).
- Code modernised across all packages for Ada 2022 language standard compliance.
- Build pipeline reliability: integrated compiler diagnostic checks, automated regression scripts, and clean warnings under `-gnatwa`.

Tested
- Perft verification up to depth 5 across standard benchmark positions (initial position and Kiwipete).
- Unit test suites (`test_draw_rules.adb`, `test_tt_multibucket.adb`, `test_pst_tapered.adb`, `test_hashfull.adb`) passing with zero failures.
- 33-position legacy expected-move battery evaluation verifying move stability against baseline Prechess 0.7.8.

Fixed
- Illegal moves generated in check evasion, absolute pins, and pawn promotion positions.
- Missing draw claims on threefold repetition and fifty-move rule thresholds.
- Early game piece blunders and aimless piece shuffling when material balance remained unchanged.
- Premature overwriting of deep search results in transposition table buffers.
- Late endgame piece misplacement caused by static opening-biased square preferences.

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
