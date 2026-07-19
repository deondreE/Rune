@echo off
setlocal enabledelayedexpansion

set PROJ_NAME=rune
set SRC_DIR=src
set BUILD_DIR=build

where cl >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] cl.exe not found in PATH.
    echo Please run this from a 'Developer Command Prompt' or 'Developer PowerShell'.
    exit /b 1
)

set BUILD_MODE=debug
set MODE_FLAGS=/Zi /Od /DDEBUG /MDd
set LINKER_SUBSYSTEM=/SUBSYSTEM:WINDOWS

if "%1"=="--release" (
    set BUILD_MODE=release
    set MODE_FLAGS=/O2 /DNDEBUG /MD
)

if not exist %BUILD_DIR% mkdir %BUILD_DIR%
set SRCS=
for /r "%SRC_DIR%" %%f in (*.cpp) do (
    set "filename=%%~nxf"
    
    set "skip="
    echo !filename! | findstr /I "^linux_ ^macos_" >nul
    if !errorlevel! equ 0 set skip=1

    if not defined skip (
        set SRCS=!SRCS! "%%f"
    )
)

:: 5. Compilation
:: /std:c++20 : Enable C++20 features
:: /W4        : High warning level
:: /EHsc      : Standard C++ exception handling
:: /Fe:       : Rename output executable
:: /Fo:       : Direct object files to build directory
echo Compiling %PROJ_NAME% (%BUILD_MODE%) for Windows...

cl /std:c++20 /W4 /EHsc %MODE_FLAGS% /I%SRC_DIR% %SRCS% ^
   /Fe%BUILD_DIR%\%PROJ_NAME%.exe /Fo%BUILD_DIR%\ ^
   /link %LINKER_SUBSYSTEM% user32.lib gdi32.lib shell32.lib

if %errorlevel% equ 0 (
    echo ----------------------------------------
    echo Build Successful: %BUILD_DIR%\%PROJ_NAME%.exe
    echo ----------------------------------------
) else (
    echo ----------------------------------------
    echo Build Failed
    echo ----------------------------------------
    exit /b 1
)