# Prechess UCI 0.7.9

Prechess is an Ada chess engine originally written around 2001–2002 as a
graphical Windows program (`prechess.adb` + `adagraph2000.dll`). Version
0.7.9 turns it into a standard text-based **UCI** engine
(`prechess_uci.adb`) that any UCI GUI can drive, while deliberately
preserving the legacy move-ordering and evaluation heuristic in
`pprechess2.adb`.

> **Authorship**
> - **José Lauro Strapasson** — original *Prechess 0.7.8*: the legacy engine
>   and its search, which 0.7.9 preserves.
> - **Arthur Matheus** — all changes and fixes after 0.7.8 (the UCI front
>   end, FIDE rules, time management, legal-move corrections, and the
>   additive search improvements described below).

`IMPLEMENTATION.md` is the companion document with the full design rationale
and verification for every change; this file states each change once and does
not repeat those details.

---

## Version 0.7.8 (legacy baseline)

- Core search and evaluation in `pprechess2.adb`: a fixed, non-recursive
  3-ply look-ahead over every from/to square pair, driven by hand-tuned
  heuristics (capture priority, hanging-piece detection, simple mate-in-1/2
  checks) rather than minimax or alpha-beta.
- Pseudo-legal move-shape checking in `pvalidade.adb`, with **no castling**
  and en passant handled only by *forbidding* the double pawn step that would
  allow it.
- A **rudimentary xboard implementation** and an Adagraph2000 Windows GUI
  (`prechess.adb`, `papresentacao.adb`, `adagraph2000.dll`). Two significant
  defects: the engine **played correctly only as Black**, and **time
  management was broken**.
- No FEN parsing and no draw-rule detection.

---

## Architecture of 0.7.9, and why the legacy search was kept

The project requirement was to modernise Prechess into a UCI engine **without
replacing** its original search — that search *is* Prechess's playing
character, and rewriting it would both lose that identity and risk broad,
unverifiable regressions. So 0.7.9 keeps `pprechess2.adb` (the ~40-tier
decision cascade and the 3-ply trial search) as the move-choosing core and
adds everything else as clean layers around it:

- `prechess_uci.adb` — the UCI front end and command loop.
- `move_validation.adb` — castling rights, en-passant state, and the derived
  legality rules (attacked-square and check detection, castling legality) the
  legacy core never had.
- `search_integration.adb` — FEN parsing, the Zobrist hash and draw-rule
  logic, `info`/score reporting, and the root-level move helpers.
- `time_management.adb`, `tt_table.adb`, `bch_hash.adb` — clock handling,
  transposition table, Zobrist keys.

The design rule is that **new behaviour sits at the root or as a tie-break,
never inside the cascade**. Castling and en passant are chosen at the root;
the forced-mate veto, retreat improver, and deferred-tactic booster inspect
and, when justified, override the legacy choice at the root; the
piece-square-table term only breaks ties the cascade already left open. Where
a change touched the core for performance, it was verified byte-identical
against a 20-position bestmove battery. This is why the legacy engine's move
choices are preserved everywhere the improvements do not deliberately, and
verifiably, intervene.

---

## Version 0.7.9 changelog

### UCI, FEN, and reporting
- Full UCI front end (`uci`/`isready`/`ucinewgame`/`position`/`go`/`stop`/
  `quit`/`setoption`), replacing the Adagraph GUI loop; no dependency on
  `adagraph2000.dll`.
- FEN parsing now reads all six fields (was: board only).
- Real live `info`: genuine time, node count, side-to-move `score cp`, current
  move. Fixed three display defects (Black score sign, quiet-move info
  flooding, per-`go` node reset).
- Dynamic `Hash` option (`setoption name Hash value N`, 1–4096 MB); a failed
  reallocation keeps the old table instead of crashing.
- Stockfish-style deepening multi-move `pv`, built by replaying the chosen
  line forward (each a genuine extra search), time-budget aware.

### Correct both colours, and correct time management
- **Fixed the Black-only bug:** a one-rank error in the board-mirroring
  transform is gone; both colours now go through one shared, tested function.
- **Reworked time management:** all standard UCI shapes (`movetime`, fixed
  depth, tournament `wtime`/`btime`+`movestogo`, sudden death, `infinite`)
  are parsed and honoured, with a fixed overhead reserved so the engine always
  returns control in time. An interrupted search now degrades cleanly instead
  of playing a half-computed move.

### Legal moves and special moves
- **Castling**, both sides and directions, with full FIDE legality (rights,
  empty path, king not moving through or into check).
- **En passant**, both sides, including the self-check test.
- **Promotions/underpromotions** are now reported correctly in `bestmove`
  (auto-queen is the engine's own choice).
- Hardened against lying FENs (castling claimed with a displaced king; an
  unplayable EP square). Gate: `test_special_moves.adb`, 35 cases.

### FIDE draw rules
- **Threefold repetition** and the **50-move rule** wired up via a real
  Zobrist hash and the FEN halfmove clock (kings are now hashed — previously
  they collided, causing false repetition draws).
- **Insufficient material** (K-K, KB-K, KN-K, KNN-K, KB-KB with same-coloured
  bishops, KN-KN — FIDE Art. 5.2.2 dead positions).
- Draws are reported as an `info string` and the engine plays on; `bestmove
  0000` is reserved for genuine checkmate/stalemate (UCI has no draw claim).
- Gate: `test_draw_rules.adb`, 28 cases.

### Search improvements (all additive; the cascade is untouched)
- **Plies 4–10 tactical safety chain** (`Quarto_Lance`…`Decimo_Lance`): a root
  move can be declined if its follow-up loses material further out; reported
  as `seldepth 10` alongside the unchanged `depth 3`.
- **Forced-mate veto:** the chosen move is rejected if it walks into a short
  forced mate that begins with a check (fixes the reported Légal's trap,
  `6...Bxd1?? 7.Bxf7+ Ke7 8.Nd5#`).
- **Threat realism:** an empty "threat" (e.g. a queen eyeing a pawn-defended
  knight) no longer drives the move (fixed the reported `Qd8-f6`); and
  re-creating a pre-existing pin/x-ray threat no longer wastes tempo (fixed
  the reported `Bh5/Bg4` shuffle).
- **Minor-piece retreat improver:** a bishop/knight *fleeing an attack* is
  redirected from a low-mobility rim square to a safe, more-mobile one (fixes
  the reported `Bb4/Ba5/Bb6` rim trap; the engine now plays `Bd6`).
- **Piece-square-table tie-break:** the existing quiet-move tie-break is now
  piece-aware (central files/ranks, off the rim and off the back rank for
  minors). Pure tie-break among already-safe quiet moves.
- **Deferred-tactic booster:** a node-bounded root forcing search that plays a
  material-winning fork/skewer the legacy chain declined as an even first
  move (e.g. a knight fork winning a rook where the legacy engine retreated).
  ~10 ms worst-case overhead.

### Performance and cleanup
- O(1) running material sum; the cascade caches `Validade` and two board
  predicates; the per-node `Quadro` rebuild in `Validade` removed — all
  verified byte-identical.
- Removed the hardcoded two-move opening book (forbidden by spec); every move,
  including the first, now comes from the search.
- Removed blanket `-gnatp` runtime-check suppression (which had masked a real
  out-of-range constant and a `Constraint_Error` on a first-move mate
  position, both now fixed); merged duplicated `*_Protegida` helpers; new code
  uses Ada 2022 conventions.

---

## UCI options

The engine advertises exactly one option:

```
option name Hash type spin default 16 min 1 max 4096
```

`setoption name Hash value N` reallocates the transposition table to N MB
immediately; it is safe to send between searches (the engine is
single-threaded, so no search is ever in progress while a command is read),
and a failed reallocation keeps the previous table rather than crashing. Note
that the transposition table backs only the PV-extension probes (see
Architecture), not the main legacy search, so `Hash` affects analysis-probe
memory, not primary playing strength. No other options (threads, ponder,
contempt, etc.) are exposed, because the underlying legacy engine is
single-threaded and has no numeric evaluation to tune.

## Time management

Confirmed against `time_management.adb` and the `go` parser — **every** shape
below is parsed and honoured. `go` reads `wtime`, `btime`, `winc`, `binc`,
`movestogo`, `movetime`, `depth`, and `infinite`; `Start_Search` then selects
a control and a per-move budget (a fixed 20 ms overhead is always reserved so
the engine returns before its deadline).

- **`go infinite`** — searches and withholds `bestmove` until `stop`/`quit`,
  as the protocol requires. *Implemented.*
- **Fixed depth (`go depth N`)** — parsed and treated as "no time limit."
  *Implemented as a control, with one honest caveat:* the legacy core is
  structurally fixed at 3 plies (plus the ply-4–10 safety chain), so it
  cannot actually search to an arbitrary depth N; the reported `depth` stays
  truthful rather than fabricated.
- **Time per move (`go movetime N`)** — the search is given N ms (minus
  overhead). *Implemented.*
- **Tournament controls (e.g. 40 moves in X minutes, then a new period)** —
  when `movestogo` is present, the remaining clock is divided across the
  moves-to-go; the "then rest" of a later period is handled naturally because
  the GUI resends the fresh clock and `movestogo` on every move, so the budget
  is recomputed each move. *Implemented.*
- **All-in / sudden-death controls (`wtime`/`btime`, no `movestogo`)** — with
  no replenishment assumed, the clock is divided over a fixed estimate of 30
  remaining moves. *Implemented.*
- **Blitz controls** — not a distinct protocol shape: blitz is the all-in
  (or tournament) path played on a short clock, so it runs through the same
  code. *Implemented (via the all-in/tournament path).*
- **Increment / bonus per move (`winc`/`binc`)** — the side-to-move's
  increment is added to each per-move budget. *Implemented.*

Every budget is also never allowed to exceed the time actually left on the
clock, and `Is_Draw` is checked before the search starts.

---

## Limitations

**Architectural** (inherited from preserving the legacy core): fixed 3-ply
selection with the ply-4–10 safety check rather than alpha-beta over a numeric
evaluation (no "search one ply deeper" knob); no true iterative deepening (the
deepening `pv` lines are forward PV extensions, not root re-searches);
single-threaded.

**No positional evaluation:** the engine scores by material plus the tactical
chain, with only the piece-square-table tie-break and the deferred-tactic
booster as positional inputs. Consequences, all measured rather than assumed:

- **Opening choices are theory-neutral.** Among equally safe, non-tactical
  moves it has no basis to prefer book theory; the tie-break biases toward
  central development but cannot override a higher-priority cascade tier (a
  pin or check). These moves do not lose material — they are just not always
  "book."
- **Slow entrapment is only partly covered.** The retreat improver catches a
  minor piece fleeing onto a dead square, but a squeeze developing over three
  or more quiet opponent moves, or trapping a rook/queen, is still invisible.
- **Deferred tactics are partly covered.** The booster catches the common
  "even trade then fork" pattern, bounded by its node budget; a win needing a
  long or partly-quiet sequence can still be missed.
- **Forced-mate veto is narrow by design:** only mates that start with a
  check, within two of the engine's own moves.
- **Non-standard, structurally fixed piece values** (P1 B3 N4 R7 Q20): the
  board encoding uses a piece's value *as* its identity, so `Validade`, the
  material sum, and ~40 cascade comparisons all depend on these exact numbers.
  Moving to the modern ≈1/3/3/5/9 scale (where B=N) would require decoupling
  identity from value across the whole core — a rewrite, not a tweak — so the
  values are left as-is. The ordering P<B<N<R<Q<K, which the logic relies on,
  is correct.

---

## Build & packaging

`build_uci.bat` compiles `engine/prechess_uci.adb` and its dependencies with
`gnatmake` (`-O3 -gnatn -gnat2012 -gnatW8`, `-largs -O3`), doing a clean build
and gating that every required file is staged before archiving. Output:

- `compilation/prechess-0.7.9-win64.exe` — build artefact
- `distribution/prechess-0.7.9-win64.exe` — final executable
- `distribution/prechess-0.7.9-win64.zip` — flat ZIP: the Win64 executable,
  `README_UCI.md`, `IMPLEMENTATION.md`, `license.txt`, and a `source/` folder
  with the complete active engine source
- `distribution/prechess-0.7.9-build.log` — compiler log
- `distribution/prechess-0.7.9-checksums.txt` — SHA-256 of the above

---

## License

Released under the MIT License — see `license.txt` for the full text.

Copyright (c) 2026 José Lauro Strapasson & Arthur Matheus.
