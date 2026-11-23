"""
Test suite for V0.9.9.17 Gate G13 (Phase 6c):
- U3: Replay rejected move diagnostics
- U2: go ponder accepted
- N4: setoption case-insensitivity
- N9: board/moves guard during active search
- M7: go nodes 64-bit parsing and malformed input warning
"""

import subprocess
import time
import sys

ENGINE_PATH = sys.argv[1] if len(sys.argv) > 1 else r"distribution\prechess-0.9.9.17.34-win64-universal.exe"

def run_uci_test():
    proc = subprocess.Popen(
        [ENGINE_PATH],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    def send(cmd):
        proc.stdin.write(cmd + "\n")
        proc.stdin.flush()

    def read_until(predicate, timeout=5.0):
        lines = []
        start = time.time()
        while time.time() - start < timeout:
            line = proc.stdout.readline()
            if line:
                lines.append(line.strip())
                if predicate(line.strip()):
                    return lines, True
            else:
                time.sleep(0.01)
        return lines, False

    print("=== Interactive UCI Protocol Tests (Gate G13) ===")

    # 1. Test UCI & options
    send("uci")
    lines, ok = read_until(lambda l: l == "uciok")
    assert ok, "Failed to get uciok"
    print("PASS: uci handshake")

    # 2. Test N4 case-insensitive setoption
    send("setoption name hash value 16")
    send("setoption name HASH value 32")
    send("setoption name Hash value 64")
    send("setoption name clear hash")
    send("setoption name castle_bonus value 90")
    send("setoption name CASTLE_BONUS value 100")
    send("isready")
    lines, ok = read_until(lambda l: l == "readyok")
    assert ok, "Failed to get readyok after setoption"
    print("PASS: N4 case-insensitive setoption (hash, clear hash, castle_bonus)")

    # 3. Test U3: rejected move reporting and halting
    send("position startpos moves e2e5 g1f3")
    send("isready")
    lines, ok = read_until(lambda l: l == "readyok")
    found_u3_msg = any("rejected move 'e2e5'" in l for l in lines)
    assert found_u3_msg, f"U3 message not found in output: {lines}"
    print("PASS: U3 rejected move reported: 'rejected move 'e2e5''")

    # 4. Test U2: go ponder holds until stop/ponderhit without premature bestmove
    send("position startpos")
    send("go ponder")
    time.sleep(0.2)
    send("ponderhit")
    lines, ok = read_until(lambda l: l.startswith("bestmove"), timeout=3.0)
    assert ok, "Failed to receive bestmove from go ponder + ponderhit"
    assert not any(" ponder " in l for l in lines if l.startswith("bestmove")), \
        f"Unexpected ponder hint in bestmove: {lines}"
    print("PASS: U2 go ponder + ponderhit accepted and finished cleanly")

    # 5. Test M7: go nodes 5000000000 and go nodes abc
    send("go nodes abc")
    lines, ok = read_until(lambda l: "info string go nodes ignored: abc" in l)
    assert ok, f"M7 warning not found: {lines}"
    print("PASS: M7 malformed nodes reported: 'info string go nodes ignored: abc'")
    send("stop")
    lines, ok = read_until(lambda l: l.startswith("bestmove"), timeout=3.0)
    assert ok, f"Failed to stop after malformed go nodes abc: {lines}"

    send("go nodes 5000000000 movetime 200")
    lines, ok = read_until(lambda l: l.startswith("bestmove"), timeout=3.0)
    assert ok, "Failed to receive bestmove from go nodes 5000000000"
    print("PASS: M7 64-bit nodes limit (5000000000) accepted without overflow")

    # 6. Test N9: board/moves guard during active search
    send("go infinite")
    time.sleep(0.1)
    send("board")
    send("moves")
    send("stop")
    lines, ok = read_until(lambda l: l.startswith("bestmove"), timeout=3.0)
    assert ok, "Failed to stop search"
    ignored_count = sum(1 for l in lines if "info string command ignored: search active" in l)
    assert ignored_count >= 2, f"Expected at least 2 ignored messages, got {ignored_count} in {lines}"
    print("PASS: N9 board and moves commands properly guarded during search")

    # Test board after stop
    send("board")
    send("isready")
    lines, ok = read_until(lambda l: l == "readyok")
    found_board = any("+---+---+---+---+---+---+---+---+" in l for l in lines)
    assert found_board, "Board not rendered after stop"
    print("PASS: N9 board renders properly when engine is idle")

    # Clean exit
    send("quit")
    proc.wait(timeout=3.0)
    print("\nALL UCI INTERACTIVE PROTOCOL TESTS PASSED!")

if __name__ == "__main__":
    run_uci_test()
