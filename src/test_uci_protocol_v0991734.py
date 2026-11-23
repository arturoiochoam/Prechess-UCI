"""
Comprehensive UCI protocol conformance suite for Prechess UCI 0.9.9.17.34 fixes.
Run: python src/test_uci_protocol_v0991734.py <path-to-exe>
"""

import subprocess
import sys
import time
import chess


def spawn(exe):
    return subprocess.Popen(
        [exe],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )


def send(proc, cmd):
    proc.stdin.write(cmd + "\n")
    proc.stdin.flush()


def read_until(proc, pred, timeout=5.0):
    lines = []
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        line = proc.stdout.readline()
        if line:
            s = line.strip()
            lines.append(s)
            if pred(s):
                return lines, True
        else:
            if proc.poll() is not None:
                break
            time.sleep(0.005)
    return lines, False


def main():
    exe = sys.argv[1] if len(sys.argv) > 1 else r"distribution\prechess-0.9.9.17.34-win64-universal.exe"
    print(f"=== UCI Protocol Verification: {exe} ===")

    # 1. Handshake & options
    p = spawn(exe)
    send(p, "uci")
    lines, ok = read_until(p, lambda s: s == "uciok")
    assert ok, f"Did not receive uciok: {lines}"
    assert any(s == "id name Prechess UCI 0.9.9.17.34" for s in lines), lines
    assert not any(s.startswith("id version") for s in lines), f"Non-standard id version present: {lines}"
    assert any(s == "option name Clear Hash type button" for s in lines), lines
    assert any(s == "option name Move Overhead type spin default 30 min 10 max 500" for s in lines), lines
    assert not any(s.startswith("option name Ponder ") for s in lines), f"Ponder must not be advertised: {lines}"
    print("PASS: uci handshake & advertised options compliant")

    # 2. Boot directly into go without prior position -> must know startpos
    send(p, "isready")
    lines, ok = read_until(p, lambda s: s == "readyok")
    assert ok
    send(p, "go depth 3")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "))
    assert ok
    bm = lines[-1].split()[1]
    b = chess.Board()
    assert chess.Move.from_uci(bm) in b.legal_moves, f"Illegal opening move on boot: {bm}"
    print(f"PASS: startup board initialized to startpos ({bm})")

    # 3. Unknown leading tokens, debug on/off, register, tabs & multi-spaces
    send(p, "  \t joho   debug   on \t")
    lines, ok = read_until(p, lambda s: "debug mode enabled" in s)
    assert ok, f"joho debug on failed: {lines}"
    send(p, "debug off")
    send(p, "register later")
    send(p, "register name Tester code 1234-5678")
    send(p, "position\t\tstartpos   \tmoves\te2e4\t e7e5")
    send(p, "go\tdepth\t3")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "))
    assert ok
    bm = lines[-1].split()[1]
    b = chess.Board()
    b.push_uci("e2e4")
    b.push_uci("e7e5")
    assert chess.Move.from_uci(bm) in b.legal_moves, f"Illegal move after tabbed position: {bm}"
    print(f"PASS: unknown leading tokens, debug, register, and tab/multi-space parsing ({bm})")

    # 4. Overlong line (> 65536 chars) drained safely without corrupting next command
    send(p, ("bogus " * 12000) + "extra")
    send(p, "isready")
    lines, ok = read_until(p, lambda s: s == "readyok", timeout=5.0)
    assert ok, f"Failed isready after overlong line: {lines}"
    assert any("truncated overlong input line" in s for s in lines), lines
    print("PASS: overlong line drained cleanly")

    # 5. Case-insensitive setoption, Clear Hash, Move Overhead
    send(p, "SEToption NAME Hash VALUE 32")
    send(p, "setoption Name Clear Hash")
    send(p, "setoption name Move Overhead value 100")
    send(p, "isready")
    lines, ok = read_until(p, lambda s: s == "readyok")
    assert ok
    print("PASS: setoption Hash / Clear Hash / Move Overhead")

    # 6. go ponder + stop & go ponder + ponderhit + idle ponderhit
    send(p, "ponderhit")  # must be ignored cleanly when idle
    send(p, "isready")
    lines, ok = read_until(p, lambda s: s == "readyok")
    assert ok

    send(p, "position startpos")
    send(p, "go ponder")
    time.sleep(0.25)
    send(p, "stop")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "), timeout=3.0)
    assert ok, f"go ponder + stop failed: {lines}"
    assert " ponder " not in lines[-1], f"Unexpected ponder suffix: {lines[-1]}"
    print(f"PASS: go ponder + stop ({lines[-1]})")

    send(p, "go ponder")
    time.sleep(0.25)
    send(p, "ponderhit")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "), timeout=3.0)
    assert ok, f"go ponder + ponderhit failed: {lines}"
    assert " ponder " not in lines[-1], f"Unexpected ponder suffix: {lines[-1]}"
    print(f"PASS: go ponder + ponderhit ({lines[-1]})")

    # 7. go searchmoves
    send(p, "position startpos")
    send(p, "go depth 4 searchmoves a2a3 h2h3")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "), timeout=5.0)
    assert ok
    bm = lines[-1].split()[1]
    assert bm in ("a2a3", "h2h3"), f"searchmoves ignored, got {bm}"
    print(f"PASS: go searchmoves respected ({bm})")

    # 8. Anti-flagging under wtime 100 winc 2000
    t0 = time.monotonic()
    send(p, "go wtime 100 btime 60000 winc 2000 binc 0")
    lines, ok = read_until(p, lambda s: s.startswith("bestmove "), timeout=2.0)
    dt_ms = (time.monotonic() - t0) * 1000.0
    assert ok and dt_ms < 250.0, f"Flag risk under wtime 100 winc 2000: took {dt_ms:.1f}ms"
    print(f"PASS: anti-flagging wtime 100 winc 2000 finished in {dt_ms:.1f} ms")

    send(p, "quit")
    rc = p.wait(timeout=3.0)
    assert rc == 0, f"Non-zero exit code on quit: {rc}"

    # 9. Prompt quit while a long timed search is running
    p2 = spawn(exe)
    send(p2, "uci")
    read_until(p2, lambda s: s == "uciok")
    send(p2, "position fen r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    send(p2, "go movetime 10000")
    time.sleep(0.15)
    t0 = time.monotonic()
    send(p2, "quit")
    rc = p2.wait(timeout=2.0)
    dt_ms = (time.monotonic() - t0) * 1000.0
    assert rc == 0 and dt_ms < 1000.0, f"quit blocked during movetime: {dt_ms:.1f}ms rc={rc}"
    print(f"PASS: prompt quit during timed search ({dt_ms:.1f} ms)")
    print("TEST_UCI_PROTOCOL_V0991734: ALL PASS")


if __name__ == "__main__":
    main()
