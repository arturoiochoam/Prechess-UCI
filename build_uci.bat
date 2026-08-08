@echo off
setlocal enabledelayedexpansion

rem -----------------------------------------------------------------------
rem  Prechess UCI 0.7.9.9  -  Build + Package Script (LTO + PGO)
rem  Output:
rem    compilation\prechess-0.7.9.9-win64.exe        (build artefact)
rem    distribution\prechess-0.7.9.9-win64.exe        (final exe)
rem    distribution\prechess-0.7.9.9-win64.zip        (exe/docs at root, sources under SRC\)
rem    distribution\prechess-0.7.9.9-build.log        (full compiler log)
rem    distribution\prechess-0.7.9.9-checksums.txt    (SHA-256)
rem -----------------------------------------------------------------------

set "GNAT_PATH=C:\msys64\mingw64\bin"
set "PATH=%GNAT_PATH%;%PATH%"

set ROOT=%~dp0
set SRC=%ROOT%src
set OBJ=%ROOT%compilation
set DIST=%ROOT%distribution
set VERSION=0.7.9.9
set BIN=prechess-%VERSION%-win64.exe
set TARGET_ZIP=%DIST%\prechess-%VERSION%-win64.zip
set BUILD_LOG=%DIST%\prechess-%VERSION%-build.log
set CHECKSUMS=%DIST%\prechess-%VERSION%-checksums.txt
set STAGE=%OBJ%\zip-stage
set PGO_TRAIN=%OBJ%\pgo_train.uci
set PGO_INSTR=%OBJ%\prechess-pgo-instr.exe

if not exist "%OBJ%"  mkdir "%OBJ%"
if not exist "%DIST%" mkdir "%DIST%"

rem ---- clean previous build artefacts ------------------------------------
del /q "%OBJ%\*" 2>nul
for /d %%D in ("%OBJ%\*") do rd /s /q "%%D" 2>nul
if not exist "%OBJ%" mkdir "%OBJ%"
if not exist "%OBJ%\tmp" mkdir "%OBJ%\tmp"
rem  Drop stale gcov profiles that escape compilation\ (e.g. the binder
rem  unit b~*.gcda written to the work dir on a prior manual run). Left
rem  around they raise "overwriting profile data with a different
rem  checksum" and can mis-merge PGO data.
del /q "%ROOT%*.gcda" "%ROOT%*.ali" "%ROOT%*.o" 2>nul
del /q "%ROOT%b~*"   2>nul

where gnatmake >nul 2>nul
if errorlevel 1 (
    echo ERROR: gnatmake not found on PATH ^(expected at %GNAT_PATH%^).
    exit /b 1
)

echo ========================================================
echo  Prechess UCI %VERSION% Ada x64 - Clean Build ^(LTO+PGO^)
echo ========================================================
echo  Source  : %SRC%
echo  Objects : %OBJ%
echo  Output  : %DIST%\%BIN%
echo ========================================================

rem  Short TEMP avoids MinGW LTO @C:\WINDOWS\TEMP response-file breakage.
set "TEMP=%OBJ%\tmp"
set "TMP=%OBJ%\tmp"

rem  Base release profile: Ada 2022 + LTO + dead-code elimination.
rem  PGO flags are layered per pass (see PGO_GEN / PGO_USE below).
rem  -gnat2022   : Ada 2022 standard (mandated).
rem  -gnatn2     : full cross-unit inlining (replaces deprecated -gnatN).
rem  -ffunction-sections -fdata-sections : one section per fn/object; paired
rem                with -Wl,--gc-sections at link for dead-code elimination.
rem  -ffat-lto-objects : required for gnatlink + -flto on this MinGW.
set BASE_AFLAGS=-O3 -gnatn2 -gnat2022 -flto -ffat-lto-objects -ffunction-sections -fdata-sections -funroll-loops -fomit-frame-pointer -ffast-math -gnatW8
set BASE_LFLAGS=-O3 -flto -ffat-lto-objects -Wl,--gc-sections -funroll-loops -fomit-frame-pointer -ffast-math
rem  No absolute -fprofile-generate=DIR on Windows: GCC nests drive letters
rem  under the profile root and skips .gcda writes. Profiles land next to .o.
set PGO_GEN=-fprofile-generate
set PGO_USE=-fprofile-use -fprofile-correction

> "%BUILD_LOG%" echo Prechess UCI %VERSION% build log
>> "%BUILD_LOG%" echo Production compile flags: %BASE_AFLAGS%
>> "%BUILD_LOG%" echo Checked test compile flags: -gnat2022 -gnata -gnatVa -gnato -gnatW8 -O0
>> "%BUILD_LOG%" echo.

rem =====================================================================
rem  PASS 1 — instrumented binary (-fprofile-generate)
rem =====================================================================
echo PASS 1/2: instrumented compile ^(profile-generate^)...
>> "%BUILD_LOG%" echo ===== PASS 1: -fprofile-generate =====
rem  Explicitly compile the leaf spec TT_Types: gnatmake sometimes skips
rem  pure specs (no body) even when other units with them, leaving the
rem  binder without the required .ali file.
gcc -c -I"%SRC%" -I"%SRC%" %BASE_AFLAGS% %PGO_GEN% -I- -o "%OBJ%\tt_types.o" "%SRC%\tt_types.ads" >> "%BUILD_LOG%" 2>&1
if errorlevel 1 ( echo ERROR: tt_types.ads compile failed. & type "%BUILD_LOG%" & exit /b 1 )
gnatmake -D "%OBJ%" -I"%SRC%" %BASE_AFLAGS% %PGO_GEN% "%SRC%\prechess_uci.adb" -o "%PGO_INSTR%" -largs %BASE_LFLAGS% %PGO_GEN% >> "%BUILD_LOG%" 2>&1
if errorlevel 1 ( echo ERROR: PGO instrumented build failed. & type "%BUILD_LOG%" & exit /b 1 )
if not exist "%PGO_INSTR%" (
    echo ERROR: instrumented executable was not produced.
    exit /b 1
)

rem ---- training workload: hot path = cascade search + UCI I/O + TT ----
> "%PGO_TRAIN%" (
    echo uci
    echo isready
    echo setoption name Hash value 64
    echo ucinewgame
    echo position startpos
    echo go movetime 1200
    echo position startpos moves e2e4 e7e5 g1f3
    echo go movetime 1200
    echo position fen rn1qkbnr/ppp2ppp/3p4/4p3/2BPP1b1/5N2/PPP2PPP/RNBQK2R b KQkq - 2 4
    echo go movetime 1200
    echo position fen rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2
    echo go movetime 800
    echo ucinewgame
    echo position startpos moves d2d4 d7d5
    echo go movetime 800
    echo quit
)

echo PASS 1/2: running PGO training workload...
>> "%BUILD_LOG%" echo ===== PGO training =====
rem  Two robustness points for running the instrumented binary:
rem   * Invoke via the ABSOLUTE path (%PGO_INSTR%). cmd in this env does
rem     not search the current directory for a bare command name, so a
rem     bare "prechess-pgo-instr.exe" fails with 9009 / not-recognized.
rem   * Feed the workload via stdin redirection (< file), NOT a pipe.
rem     A pipe whose right side fails aborts the whole batch (exit 255);
rem     a redirection just sets errorlevel, so the retry loop can run.
rem  pushd compilation\ so the .gcda profiles land beside the .o units
rem  (and the binder unit b~*.gcda lands here too). A freshly linked
rem  binary can also be briefly AV-scanned, hence the retry.
pushd "%OBJ%"
set TRAIN_TRY=0
:train_retry
set /a TRAIN_TRY+=1
"%PGO_INSTR%" < "%PGO_TRAIN%" >> "%BUILD_LOG%" 2>&1
if !errorlevel! equ 0 goto train_done
if !TRAIN_TRY! geq 6 goto train_fail
echo    training attempt !TRAIN_TRY! did not run cleanly, retrying...
>> "%BUILD_LOG%" echo (retry !TRAIN_TRY!)
ping -n 4 127.0.0.1 >nul
goto train_retry

:train_fail
popd
echo ERROR: PGO training run failed after !TRAIN_TRY! attempts.
type "%BUILD_LOG%"
exit /b 1

:train_done
popd

rem  Gate: at least one .gcda profile file must exist next to objects.
set GCDA_COUNT=0
for %%G in ("%OBJ%\*.gcda") do set /a GCDA_COUNT+=1
if %GCDA_COUNT%==0 (
    echo ERROR: no .gcda profiles written under %OBJ%
    exit /b 1
)
echo PASS 1/2: collected %GCDA_COUNT% profile file^(s^).
>> "%BUILD_LOG%" echo PGO profiles: %GCDA_COUNT% .gcda file^(s^)

rem ---- wipe objects/ali for a clean profile-use rebuild; keep .gcda ----
del /q "%OBJ%\*.o" "%OBJ%\*.ali" "%OBJ%\*.stdout" "%OBJ%\*.stderr" 2>nul
del /q "%PGO_INSTR%" 2>nul
del /q "%OBJ%\%BIN%" 2>nul

rem =====================================================================
rem  PASS 2 — optimised binary (-fprofile-use)
rem =====================================================================
echo PASS 2/2: optimised compile ^(profile-use + LTO^)...
>> "%BUILD_LOG%" echo ===== PASS 2: -fprofile-use =====
rem  Re-compile TT_Types spec after the .ali wipe between passes.
gcc -c -I"%SRC%" -I"%SRC%" %BASE_AFLAGS% %PGO_USE% -I- -o "%OBJ%\tt_types.o" "%SRC%\tt_types.ads" >> "%BUILD_LOG%" 2>&1
if errorlevel 1 ( echo ERROR: tt_types.ads compile failed. & type "%BUILD_LOG%" & exit /b 1 )
gnatmake -D "%OBJ%" -I"%SRC%" %BASE_AFLAGS% %PGO_USE% "%SRC%\prechess_uci.adb" -o "%OBJ%\%BIN%" -largs %BASE_LFLAGS% %PGO_USE% >> "%BUILD_LOG%" 2>&1
if errorlevel 1 ( echo ERROR: PGO optimised build failed. & type "%BUILD_LOG%" & exit /b 1 )

if not exist "%OBJ%\%BIN%" (
    echo ERROR: executable was not produced.
    type "%BUILD_LOG%"
    exit /b 1
)

echo BUILD SUCCEEDED >> "%BUILD_LOG%"
echo Build PASSED ^(LTO+PGO^).

rem  Release-facing artefacts are deleted before the gate and recreated ONLY
rem  after all tests pass; a failed gate must not leave a fresh ungated exe in
rem  distribution beside stale ZIP/checksums.
del /q "%DIST%\%BIN%" "%TARGET_ZIP%" "%CHECKSUMS%" 2>nul

rem =====================================================================
rem  TEST GATE  (replaces the former no-op "Test gate: PASS" echo)
rem =====================================================================
rem  Two real gates, both must pass before the build is packaged:
rem    (1) Ada unit tests  : test_draw_rules / test_special_moves /
rem                          test_tt_multibucket  (built standalone,
rem                          Ada 2022, in a separate object dir so they
rem                          do not collide with the PGO objects).
rem    (2) Regression battery: test\test_positions.py compares Stockfish
rem                          vs 0.7.9.1 vs the just-built 0.7.9.9; exit 0
rem                          means 0.7.9.9 >= 0.7.9.1 on expected moves
rem                          (zero move regression).
echo Running test gate...

set "TEST_OBJ=%OBJ%\tests_obj"
if exist "%TEST_OBJ%" rd /s /q "%TEST_OBJ%"
mkdir "%TEST_OBJ%"
rem  -- (1) Build + run the Ada unit tests --------------------------------
rem  Checked test profile (-gnata -gnatVa -gnato, no -gnatp); no PGO/LTO
rem  needed for tests.
rem  Pre-compile EVERY engine unit (spec + body) into TEST_OBJ before binding
rem  any test. gnatmake's incremental body tracking otherwise misses a body in
rem  a fresh object dir (it built test_tt_multibucket but failed
rem  test_draw_rules / test_special_moves at bind with "...adb must be
rem  compiled"). Hand it a complete, consistent .ali set and let gnatmake only
rem  bind+link each test. A failure raises via the _gate_failed sentinel
rem  (checked at the end), not a TEST_FAIL accumulator, because the for-loop
rem  set/!var! interaction proved unreliable.
for %%U in (tt_types pvalidade move_validation bch_hash tt_table time_management pprechess2 search_integration) do (
    if exist "%SRC%\%%U.ads" gcc -c -I"%SRC%" -gnat2022 -gnata -gnatVa -gnato -gnatW8 -O0 -o "%TEST_OBJ%\%%U.o" "%SRC%\%%U.ads" >> "%BUILD_LOG%" 2>&1
    if exist "%SRC%\%%U.adb" gcc -c -I"%SRC%" -gnat2022 -gnata -gnatVa -gnato -gnatW8 -O0 -o "%TEST_OBJ%\%%U.o" "%SRC%\%%U.adb" >> "%BUILD_LOG%" 2>&1
)
rem  Build each test with gcc + gnatbind + gnatlink, NOT gnatmake. gnatmake
rem  flakes on these ("move_validation.ads has been modified" / "...
rem  must be compiled") because of its stamp/dependency analysis across the
rem  pre-compiled bodies; gcc+bind+link is deterministic. Run from inside
rem  TEST_OBJ so the .ali/.o land there and gnatlink finds them.
pushd "%TEST_OBJ%"
for %%T in (test_draw_rules test_special_moves test_tt_multibucket test_endgame test_hashfull test_pst_tapered test_uci_replay test_time_management) do (
    gcc -c -I"%SRC%" -gnat2022 -gnata -gnatVa -gnato -gnatW8 -O0 "%SRC%\%%T.adb" >> "%BUILD_LOG%" 2>&1
    if not errorlevel 1 gnatbind -aO"%TEST_OBJ%" -I"%SRC%" "%%T" >> "%BUILD_LOG%" 2>&1
    if not errorlevel 1 gnatlink "%%T" -O0 -o "%%T.exe" >> "%BUILD_LOG%" 2>&1
    if errorlevel 1 (
        echo ERROR: unit test build failed: %%T
        echo failed> "%TEST_OBJ%\_gate_failed"
    )
)
popd

"%TEST_OBJ%\test_draw_rules.exe" > "%TEST_OBJ%\draw.out" 2>&1
findstr /c:"ALL DRAW-RULE TESTS PASSED" "%TEST_OBJ%\draw.out" >nul
if errorlevel 1 ( echo ERROR: test_draw_rules FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

"%TEST_OBJ%\test_special_moves.exe" > "%TEST_OBJ%\special.out" 2>&1
findstr /c:"ALL SPECIAL-MOVE TESTS PASSED" "%TEST_OBJ%\special.out" >nul
if errorlevel 1 ( echo ERROR: test_special_moves FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

"%TEST_OBJ%\test_tt_multibucket.exe" > "%TEST_OBJ%\tt.out" 2>&1
findstr /c:"TEST_TT_MULTIBUCKET: PASS" "%TEST_OBJ%\tt.out" >nul
if errorlevel 1 ( echo ERROR: test_tt_multibucket FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  test_endgame: self-checking endgame override API gate.
"%TEST_OBJ%\test_endgame.exe" > "%TEST_OBJ%\endgame.out" 2>&1
findstr /c:"TEST_ENDGAME: PASS" "%TEST_OBJ%\endgame.out" >nul
if errorlevel 1 ( echo ERROR: test_endgame FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  test_hashfull: the UCI hashfull metric (TT occupancy counter).
"%TEST_OBJ%\test_hashfull.exe" > "%TEST_OBJ%\hashfull.out" 2>&1
findstr /c:"TEST_TT_HASHFULL: PASS" "%TEST_OBJ%\hashfull.out" >nul
if errorlevel 1 ( echo ERROR: test_hashfull FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  test_pst_tapered: tapered positional tie-break phase/interpolation.
"%TEST_OBJ%\test_pst_tapered.exe" > "%TEST_OBJ%\pst_tapered.out" 2>&1
findstr /c:"TEST_PST_TAPERED: PASS" "%TEST_OBJ%\pst_tapered.out" >nul
if errorlevel 1 ( echo ERROR: test_pst_tapered FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  test_uci_replay: illegal UCI replay tokens must not corrupt board/history.
"%TEST_OBJ%\test_uci_replay.exe" > "%TEST_OBJ%\uci_replay.out" 2>&1
findstr /c:"TEST_UCI_REPLAY: PASS" "%TEST_OBJ%\uci_replay.out" >nul
if errorlevel 1 ( echo ERROR: test_uci_replay FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  test_time_management: boundary values in UCI time controls must not overflow.
"%TEST_OBJ%\test_time_management.exe" > "%TEST_OBJ%\time_management.out" 2>&1
findstr /c:"TEST_TIME_MANAGEMENT: PASS" "%TEST_OBJ%\time_management.out" >nul
if errorlevel 1 ( echo ERROR: test_time_management FAILED & echo failed> "%TEST_OBJ%\_gate_failed" )

rem  -- (2) Regression battery (skipped with a warning if the python
rem         toolchain or the reference exe/Stockfish oracle is absent) ----
set RUN_BATTERY=1
where python >nul 2>nul || set RUN_BATTERY=0
if not exist "%ROOT%test\test_positions.py"   set RUN_BATTERY=0
if not exist "%ROOT%test\stockfish-windows-x86-64-universal.exe" set RUN_BATTERY=0
if not exist "%DIST%\prechess-0.7.9.1-win64.exe" set RUN_BATTERY=0

if "!RUN_BATTERY!"=="0" (
    echo ERROR: regression battery prerequisites missing ^(python, test_positions.py, Stockfish oracle, or 0.7.9.1 reference exe^).
    echo failed> "%TEST_OBJ%\_gate_failed"
) else (
    echo Running regression battery ^(Stockfish / 0.7.9.1 / 0.7.9.9, movetime 1000ms^)...
    python "%ROOT%test\test_positions.py" --movetime 1000 >> "%BUILD_LOG%" 2>&1
    if errorlevel 1 (
        echo ERROR: regression battery test_positions.py FAILED ^(move regression detected^)
        echo failed> "%TEST_OBJ%\_gate_failed"
    )
)

if exist "%TEST_OBJ%\_gate_failed" (
    echo ERROR: TEST GATE FAILED. See %BUILD_LOG% and %TEST_OBJ%\*.out
    exit /b 1
)
echo Test gate: PASS

rem ---- publish gated exe + docs -------------------------------------------
copy /Y "%OBJ%\%BIN%"        "%DIST%\%BIN%"        >nul
copy /Y "%SRC%\license.txt"  "%DIST%\license.txt"  >nul
copy /Y "%SRC%\README.md"    "%DIST%\README.md"    >nul

rem ---- stage ZIP contents ------------------------------------------------
rem  Release ZIP root: prechess-%VERSION%-win64.exe, README.md, license.txt.
rem  Source files are under SRC\ and only .adb/.ads are copied there.
set "ZIP_ROOT_EXE=%BIN%"
set "RELEASE_SRCS=prechess_uci.adb pvalidade.ads pvalidade.adb pprechess2.ads pprechess2.adb move_validation.ads move_validation.adb move_gen.ads move_gen.adb tt_types.ads bch_hash.ads bch_hash.adb tt_table.ads tt_table.adb search_integration.ads search_integration.adb time_management.ads time_management.adb test_draw_rules.adb test_special_moves.adb test_tt_multibucket.adb test_endgame.adb test_hashfull.adb test_pst_tapered.adb test_uci_replay.adb test_time_management.adb"

if exist "%STAGE%" rd /s /q "%STAGE%"
mkdir "%STAGE%"
mkdir "%STAGE%\SRC"

for %%S in (!RELEASE_SRCS!) do (
    copy /Y "%SRC%\%%S" "%STAGE%\SRC\" >nul
)
copy /Y "%SRC%\README.md"    "%STAGE%\README.md"    >nul
copy /Y "%SRC%\license.txt"  "%STAGE%\license.txt"  >nul
copy /Y "%DIST%\%BIN%"       "%STAGE%\%ZIP_ROOT_EXE%" >nul

for %%F in (README.md license.txt %ZIP_ROOT_EXE%) do (
    if not exist "%STAGE%\%%F" (
        echo ERROR: required file missing from ZIP stage: %%F
        exit /b 1
    )
)
for %%F in (!RELEASE_SRCS!) do (
    if not exist "%STAGE%\SRC\%%F" (
        echo ERROR: required source file missing from ZIP stage SRC\%%F
        exit /b 1
    )
)

rem ---- create ZIP --------------------------------------------------------
if exist "%TARGET_ZIP%" del /q "%TARGET_ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%TARGET_ZIP%' -Force"
if errorlevel 1 (
    echo ERROR: ZIP creation failed.
    exit /b 1
)

rem ---- checksums (SHA-256) -----------------------------------------------
echo Generating checksums...
> "%CHECKSUMS%" (
    echo Prechess UCI %VERSION% ^| SHA-256 Checksums
    echo Generated: %DATE% %TIME%
    echo.
)
for %%F in ("%DIST%\%BIN%" "%TARGET_ZIP%" "%DIST%\license.txt") do (
    for /f "skip=1 tokens=* delims=" %%H in ('certutil -hashfile "%%~F" SHA256 ^| findstr /v "CertUtil"') do (
        echo %%H  %%~nxF>> "%CHECKSUMS%"
    )
)
if not exist "%CHECKSUMS%" (
    echo ERROR: checksum generation failed.
    exit /b 1
)

rem  Keep a build-log copy with the compilation artefacts as required by the
rem  final directory contract; distribution remains the release-facing copy.
copy /Y "%BUILD_LOG%" "%OBJ%\prechess-%VERSION%-build.log" >nul

rem ---- summary -----------------------------------------------------------
echo.
echo ========================================================
echo  BUILD COMPLETE ^(LTO + PGO^)
echo ========================================================
echo  Executable : %DIST%\%BIN%
echo  ZIP        : %TARGET_ZIP%
echo  Build log  : %BUILD_LOG%
echo  Checksums  : %CHECKSUMS%
echo  PGO data   : %OBJ%\*.gcda  ^(%GCDA_COUNT% files^)
echo ========================================================
echo  ZIP contents:
powershell -NoProfile -Command "Get-ChildItem '%STAGE%' -Recurse | ForEach-Object { '    ' + $_.FullName.Substring('%STAGE%'.Length + 1) + '  (' + $_.Length + ' bytes)' }"
echo ========================================================
echo Test gate: PASS ^(real gate ran above^)

endlocal
exit /b 0
