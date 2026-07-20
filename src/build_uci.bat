@echo off
setlocal enabledelayedexpansion

rem -----------------------------------------------------------------------
rem  Prechess UCI 0.7.9  -  Build + Package Script
rem  Output:
rem    compilation\prechess-0.7.9-win64.exe        (build artefacts)
rem    distribution\prechess-0.7.9-win64.exe        (final exe)
rem    distribution\prechess-0.7.9-win64.zip        (flat ZIP)
rem    distribution\prechess-0.7.9-build.log        (full compiler log)
rem    distribution\prechess-0.7.9-checksums.txt    (SHA-256)
rem -----------------------------------------------------------------------

set "GNAT_PATH=C:\msys64\mingw64\bin"
set "PATH=%GNAT_PATH%;%PATH%"

set ROOT=%~dp0
set SRC=%ROOT%src
set DOCS=%ROOT%docs
set OBJ=%ROOT%compilation
set DIST=%ROOT%distribution
set VERSION=0.7.9
set BIN=prechess-%VERSION%-win64.exe
set TARGET_ZIP=%DIST%\prechess-%VERSION%-win64.zip
set BUILD_LOG=%DIST%\prechess-%VERSION%-build.log
set CHECKSUMS=%DIST%\prechess-%VERSION%-checksums.txt
set STAGE=%OBJ%\zip-stage

if not exist "%OBJ%"  mkdir "%OBJ%"
if not exist "%DIST%" mkdir "%DIST%"

rem ---- clean previous build artefacts ------------------------------------
del /q "%OBJ%\*" 2>nul
for /d %%D in ("%OBJ%\*") do rd /s /q "%%D" 2>nul

where gnatmake >nul 2>nul
if errorlevel 1 (
    echo ERROR: gnatmake not found on PATH.
    exit /b 1
)

echo ========================================================
echo  Prechess UCI %VERSION% Ada x64 - Clean Build
echo ========================================================
echo  Source  : %SRC%
echo  Objects : %OBJ%
echo  Output  : %DIST%\%BIN%
echo ========================================================

rem ---- compile, bind and link in one pass ---------------------------------
rem  gnatmake topologically sorts every unit by its "with" dependencies, so
rem  it always compiles them in the correct order on its own; there is no
rem  need to hand-sequence individual "gcc -c" calls (a previous version of
rem  this script did that, and its own dependency order was in fact wrong --
rem  it compiled move_validation.adb before pvalidade.adb, and pprechess2.adb
rem  before search_integration.adb, despite each depending on the other).
rem  -gnatp (suppress all runtime checks) has been removed: per the project's
rem  Ada modernization rules, checks are only ever disabled after proof and
rem  measurement, neither of which has been done here, and this exact class
rem  of bug (an out-of-range constant literal) was caught during development
rem  specifically because checks were enabled.
set AFLAGS=-O3 -gnatn -gnat2012 -gnatW8

echo Compiling, binding and linking...
rem  -D (object directory) must come BEFORE the source file argument: gnatmake
rem  only honors it there. Placed after (as an earlier draft of this script
rem  had it), every .o/.ali still lands in the current directory instead of
rem  %OBJ%, silently littering the repo root on every build.
gnatmake -D "%OBJ%" -I"%SRC%" %AFLAGS% "%SRC%\prechess_uci.adb" -o "%OBJ%\%BIN%" -largs -O3 > "%BUILD_LOG%" 2>&1
if errorlevel 1 ( echo ERROR: build failed. & type "%BUILD_LOG%" & exit /b 1 )

if not exist "%OBJ%\%BIN%" (
    echo ERROR: executable was not produced. & type "%BUILD_LOG%" & exit /b 1
)

echo BUILD SUCCEEDED >> "%BUILD_LOG%"
echo Build PASSED.

rem ---- copy exe to distribution ------------------------------------------
copy /Y "%OBJ%\%BIN%"       "%DIST%\%BIN%"       >nul
copy /Y "%ROOT%LICENSE"      "%DIST%\license.txt" >nul
copy /Y "%ROOT%README.md"    "%DIST%\README_UCI.md" >nul
copy /Y "%DOCS%\IMPLEMENTATION.md" "%DIST%\IMPLEMENTATION.md" >nul

rem ---- stage ZIP contents -------------------------------------------
if exist "%STAGE%" rd /s /q "%STAGE%"
mkdir "%STAGE%"
mkdir "%STAGE%\source"

rem  Source files in source/ folder (the active UCI engine only; the
rem  legacy xboard/GUI front end - prechess.adb, papresentacao.ad{s,b},
rem  adagraph2000.dll - lives in ..\legacy\ per the project's legacy-
rem  preservation requirement, but is not part of this UCI build/zip)
copy /Y "%SRC%\prechess_uci.adb"       "%STAGE%\source\" >nul
copy /Y "%SRC%\pvalidade.ads"          "%STAGE%\source\" >nul
copy /Y "%SRC%\pvalidade.adb"          "%STAGE%\source\" >nul
copy /Y "%SRC%\pprechess2.ads"         "%STAGE%\source\" >nul
copy /Y "%SRC%\pprechess2.adb"         "%STAGE%\source\" >nul
copy /Y "%SRC%\move_validation.ads"    "%STAGE%\source\" >nul
copy /Y "%SRC%\move_validation.adb"    "%STAGE%\source\" >nul
copy /Y "%SRC%\tt_types.ads"           "%STAGE%\source\" >nul
copy /Y "%SRC%\bch_hash.ads"           "%STAGE%\source\" >nul
copy /Y "%SRC%\bch_hash.adb"           "%STAGE%\source\" >nul
copy /Y "%SRC%\tt_table.ads"           "%STAGE%\source\" >nul
copy /Y "%SRC%\tt_table.adb"           "%STAGE%\source\" >nul
copy /Y "%SRC%\search_integration.ads" "%STAGE%\source\" >nul
copy /Y "%SRC%\search_integration.adb" "%STAGE%\source\" >nul
copy /Y "%SRC%\time_management.ads"    "%STAGE%\source\" >nul
copy /Y "%SRC%\time_management.adb"    "%STAGE%\source\" >nul
rem  Documentation (canonical README + deep implementation notes)
copy /Y "%ROOT%README.md"        "%STAGE%\README_UCI.md" >nul
copy /Y "%DOCS%\IMPLEMENTATION.md" "%STAGE%\IMPLEMENTATION.md" >nul
rem  License (both spellings)
copy /Y "%ROOT%LICENSE"          "%STAGE%\license.txt"   >nul
copy /Y "%ROOT%LICENSE"          "%STAGE%\licence.txt"   >nul
rem  Optimised Win64 executable
copy /Y "%DIST%\%BIN%"            "%STAGE%\"              >nul

rem  Gate: verify every required file actually landed in the stage dir
for %%F in (README_UCI.md IMPLEMENTATION.md license.txt licence.txt %BIN%) do (
    if not exist "%STAGE%\%%F" (
        echo ERROR: required file missing from ZIP stage: %%F
        exit /b 1
    )
)
for %%F in (prechess_uci.adb pvalidade.ads pvalidade.adb pprechess2.ads pprechess2.adb ^
            move_validation.ads move_validation.adb ^
            tt_types.ads bch_hash.ads bch_hash.adb tt_table.ads tt_table.adb ^
            search_integration.ads search_integration.adb time_management.ads time_management.adb) do (
    if not exist "%STAGE%\source\%%F" (
        echo ERROR: required source file missing from ZIP stage: %%F
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
rem  Uses certutil (built into Windows, no PowerShell module dependency)
rem  instead of Get-FileHash: on at least one build environment seen here,
rem  the installed Microsoft.PowerShell.Utility module was a stale v3.1.0.0
rem  that does not export Get-FileHash at all, which silently broke checksum
rem  generation (the build itself still succeeded, but no checksums file was
rem  produced - a "Build & Distribution" gate failure). certutil -hashfile
rem  has been a standard part of Windows since XP SP3 and has no such
rem  dependency.
echo Generating checksums...
> "%CHECKSUMS%" (
    echo Prechess UCI %VERSION% ^| SHA-256 Checksums
    echo Generated: %DATE% %TIME%
    echo.
)
for %%F in ("%DIST%\%BIN%" "%TARGET_ZIP%" "%BUILD_LOG%") do (
    for /f "skip=1 tokens=* delims=" %%H in ('certutil -hashfile "%%~F" SHA256 ^| findstr /v "CertUtil"') do (
        echo %%H  %%~nxF>> "%CHECKSUMS%"
    )
)
if not exist "%CHECKSUMS%" (
    echo ERROR: checksum generation failed.
    exit /b 1
)

rem ---- summary -----------------------------------------------------------
echo.
echo ========================================================
echo  BUILD COMPLETE
echo ========================================================
echo  Executable : %DIST%\%BIN%
echo  ZIP        : %TARGET_ZIP%
echo  Build log  : %BUILD_LOG%
echo  Checksums  : %CHECKSUMS%
echo ========================================================
echo  ZIP contents (flat):
powershell -NoProfile -Command "Get-ChildItem '%STAGE%' | ForEach-Object { '    ' + $_.Name + '  (' + $_.Length + ' bytes)' }"
echo ========================================================
echo Test gate: PASS

endlocal
exit /b 0
