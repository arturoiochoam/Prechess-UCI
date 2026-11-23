#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# test_prechess_uc.py -- UCI regression harness for Prechess UCI 0.9.9.16.x
#
# Companion to the code-review canvas "prechess-code-review" (Addendum VII,
# section 37 regression battery). Runs the engine as a UCI subprocess on
# your Windows / MSYS64 host and checks the emitted bestmove against the
# expected move list for each documented position.
#
# Usage:
#   python test_prechess_uc.py --engine ./prechess.exe
#   python test_prechess_uc.py --engine ./prechess.exe --movetime 2000
#   python test_prechess_uc.py --engine ./prechess.exe --only PT
#   python test_prechess_uc.py --engine ./prechess.exe --verbose
#
# --engine accepts a full command line (quoted if it contains spaces),
# e.g. --engine "python3 /path/to/adapter.py".
#
# Pure standard library; works under MSYS2 Python or native Windows Python.
# Exit code = number of failed cases (0 = all pass).
# ---------------------------------------------------------------------------

import argparse
import shlex
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Test battery.
# Each case: (id, description, fen, accepted_bestmoves, related_findings)
# A case PASSES if the engine's bestmove is in the accepted set.
# ---------------------------------------------------------------------------
CASES = [
    {
        "id": "PT-1",
        "desc": "Pawn-tension move 10: development vs entering tension "
                "(Addendum VII s34; expected Rf8-e8, c5-c4 also sound)",
        "fen": "rn1q1rk1/pb2bppp/3p1n2/1pp1p3/4P3/2PP1N1P/PPBN1PP1/R1BQ1RK1 b - - 1 10",
        "accept": ["f8e8", "c5c4"],
        "findings": "K1/S1 ordering (no gate failure by design)",
    },
    {
        "id": "PT-2",
        "desc": "Pawn-tension move 11: the equal recapture b5xc4 -- "
                "the N11 equal-trade blind-spot case (Addendum VII s35.2)",
        "fen": "rn1q1rk1/pb2bppp/3p1n2/1p2p3/2P1P3/2P2N1P/PPBN1PP1/R1BQ1RK1 b - - 0 11",
        "accept": ["b5c4"],
        "findings": "N11 (HIGH): every stage filters SEE=0 recaptures; "
                    "C6 Net_Cp gate is the systemic fix",
    },
    {
        "id": "PT-3",
        "desc": "Pawn-tension move 12: recovery moves; a7-a5 additionally "
                "proves the N12 pawn-branch fix (Addendum VII s35.3)",
        "fen": "rn1q1rk1/pb2bppp/3p1n2/4p3/1PP1P3/5N1P/PPBN1PP1/R1BQ1RK1 b - - 0 12",
        "accept": ["n8d7", "n8a6", "a7a5"],
        "findings": "N12: a7-a5 is vetoed pre-fix (rook defense invisible)",
    },
    {
        "id": "BL-1",
        "desc": "blunders.md Position 1: attacked knight must stay active "
                "(scored-destination selector case)",
        "fen": "r1bqkbnr/ppp1pppp/2n5/3P4/2p1P3/8/PP3PPP/RNBQK2R b KQkq - 0 4",
        "accept": ["c6e5"],
        "findings": "B-C1/C3 family; verified 0.9.9.16.1 pass claim",
    },
    {
        "id": "BL-2",
        "desc": "blunders.md Position 2: development move; also compare the "
                "reported score against Stockfish cp -14",
        "fen": "rnbqk2r/ppppbppp/5n2/4p3/2P5/2NP1N2/PP2PPPP/R1BQKB1R b KQkq - 4 4",
        "accept": ["b8c6"],
        "findings": "PV inflation fix (L4); score should be near cp -33",
    },
    {
        "id": "BL-3a",
        "desc": "blunders.md Position 3 (pre-move): bishop must not stay "
                "en prise to the c3 pawn",
        "fen": "r1bqk2r/pppp1ppp/2n2n2/4p3/1bB1P3/2PP1N2/PP3PPP/RNBQK2R b KQkq - 0 5",
        "accept": ["b4c5"],
        "findings": "Stage 3 en-prise resolve; verified pass claim",
    },
    {
        "id": "BL-3b",
        "desc": "blunders.md Position 3 (post-blunder, White to move): "
                "the hanging bishop must be taken",
        "fen": "r1bq1rk1/pppp1ppp/2n2n2/4p3/1bB1P3/2PP1N2/PP3PPP/RNBQK2R w KQ - 2 7",
        "accept": ["c3b4"],
        "findings": "Stage 2 Best_Winning_Capture (raw-code Gain > 0)",
    },
]


class UCIEngine:
    """Minimal UCI client: spawn, handshake, position, go, collect bestmove."""

    def __init__(self, path, verbose=False):
        self.path = path
        self.verbose = verbose
        self.proc = None
        self.start()
        self.handshake()

    def start(self):
        # --engine may be a full command line; split it when it contains
        # spaces (quoted paths are handled by shlex).
        if " " in self.path:
            cmd = shlex.split(self.path)
        else:
            cmd = [self.path]
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )

    def send(self, cmd):
        if self.verbose:
            print(f"    > {cmd}")
        try:
            self.proc.stdin.write(cmd + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise RuntimeError(f"engine pipe broken: {exc}")

    def read_until(self, token, timeout):
        """Read lines until one starts with `token`; None on timeout."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if line == "":  # EOF: engine died
                raise RuntimeError("engine closed its output (crashed?)")
            line = line.strip()
            if not line:
                continue
            if self.verbose:
                print(f"    < {line}")
            if line.startswith(token):
                return line
        return None

    def restart(self):
        try:
            self.proc.kill()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=3)
        except Exception:
            pass
        self.start()
        self.handshake()

    def handshake(self):
        self.send("uci")
        if self.read_until("uciok", 15) is None:
            raise RuntimeError("no uciok: engine is not speaking UCI")
        self.send("isready")
        if self.read_until("readyok", 15) is None:
            raise RuntimeError("no readyok during handshake")
        # Small warm-up hash allocation, mirrors GUI behaviour.
        self.send("setoption name Hash value 16")
        self.send("isready")
        if self.read_until("readyok", 15) is None:
            raise RuntimeError("no readyok after setoption")

    def sync(self, timeout=15):
        self.send("isready")
        return self.read_until("readyok", timeout)

    def close(self):
        try:
            self.send("quit")
            self.proc.wait(timeout=5)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def run_case(engine, case, movetime, go_timeout):
    engine.send("ucinewgame")
    engine.sync()
    engine.send(f"position fen {case['fen']}")
    engine.sync()
    engine.send(f"go movetime {movetime}")

    bestmove = None
    last_info = ""
    deadline = time.time() + go_timeout
    while time.time() < deadline:
        line = engine.proc.stdout.readline()
        if line == "":
            raise RuntimeError("engine closed its output mid-search")
        line = line.strip()
        if not line:
            continue
        if engine.verbose:
            print(f"    < {line}")
        if line.startswith("info "):
            last_info = line
        elif line.startswith("bestmove"):
            bestmove = line.split()[1] if len(line.split()) > 1 else "0000"
            break

    if bestmove is None:
        # Engine hung: stop it, then restart for the remaining cases.
        try:
            engine.send("stop")
        except RuntimeError:
            pass
        engine.read_until("bestmove", 5)
        engine.restart()
        return None, last_info

    return bestmove, last_info


def main():
    ap = argparse.ArgumentParser(description="Prechess UCI regression harness")
    ap.add_argument("--engine", default="./prechess.exe",
                    help="path to the engine executable (full command line "
                         "allowed if quoted)")
    ap.add_argument("--movetime", type=int, default=1000,
                    help="movetime in ms per position (default 1000)")
    ap.add_argument("--go-timeout", type=float, default=30.0,
                    help="seconds to wait for bestmove (default 30)")
    ap.add_argument("--only", default=None,
                    help="run only cases whose id contains this substring")
    ap.add_argument("--verbose", action="store_true",
                    help="echo the full UCI dialogue")
    args = ap.parse_args()

    cases = [c for c in CASES
             if args.only is None or args.only.lower() in c["id"].lower()]
    if not cases:
        print(f"no case matches --only {args.only!r}")
        return 2

    print("=" * 74)
    print("Prechess UCI regression harness -- review Addendum VII battery")
    print(f"engine: {args.engine}   movetime: {args.movetime} ms")
    print("=" * 74)

    try:
        engine = UCIEngine(args.engine, args.verbose)
    except Exception as exc:
        print(f"FATAL: cannot start/handshake engine: {exc}")
        return 1

    failures = 0
    try:
        for case in cases:
            print(f"\n[{case['id']}] {case['desc']}")
            print(f"  FEN: {case['fen']}")
            try:
                bestmove, info = run_case(engine, case,
                                          args.movetime, args.go_timeout)
            except RuntimeError as exc:
                print(f"  ERROR: {exc}")
                failures += 1
                engine.restart()
                continue

            if bestmove is None:
                print(f"  FAIL: no bestmove within {args.go_timeout:g}s "
                      f"(engine restarted)")
                failures += 1
                continue

            ok = bestmove in case["accept"]
            status = "PASS" if ok else "FAIL"
            expected = " or ".join(case["accept"])
            print(f"  bestmove: {bestmove}   expected: {expected}")
            if info:
                # Show the final info line for score diagnostics.
                print(f"  last info: {info}")
            print(f"  {status}   [{case['findings']}]")
            if not ok:
                failures += 1
    finally:
        engine.close()

    print("\n" + "=" * 74)
    total, passed = len(cases), len(cases) - failures
    print(f"RESULT: {passed}/{total} passed, {failures} failed")
    print("=" * 74)
    return failures if failures else 0


if __name__ == "__main__":
    sys.exit(main())
