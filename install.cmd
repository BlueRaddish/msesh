@echo off
rem install.cmd - the Windows-side door to install.sh.
rem
rem install.sh is a bash script, and a Windows user who has just cloned this
rem repo is standing in PowerShell or cmd, where `./install.sh` is not a thing
rem you can run. This finds the MSYS2 bash that msesh needs anyway and hands
rem the invocation over, so `install` works from the shell you are already in.
rem
rem Arguments are forwarded unchanged: install --check, install --prefix D:\bin,
rem install --uninstall all behave as documented for install.sh.
rem
rem MSESH_BASH points at a bash.exe outright; MSESH_MSYS_ROOT points at an
rem MSYS2 install root when it is somewhere unusual.

setlocal

set "MSESH_SETUP=%~dp0install.sh"
set "MSESH_RUNNER="

if defined MSESH_BASH if exist "%MSESH_BASH%" set "MSESH_RUNNER=%MSESH_BASH%"
if not defined MSESH_RUNNER if defined MSESH_MSYS_ROOT if exist "%MSESH_MSYS_ROOT%\usr\bin\bash.exe" set "MSESH_RUNNER=%MSESH_MSYS_ROOT%\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "%SystemDrive%\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=%SystemDrive%\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "C:\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=C:\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "C:\tools\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=C:\tools\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe" set "MSESH_RUNNER=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe"

if not defined MSESH_RUNNER (
    >&2 echo install: no MSYS2 bash found - msesh needs tmux, which ships with MSYS2.
    >&2 echo install: install MSYS2 from https://www.msys2.org, then 'pacman -S tmux'.
    >&2 echo install: or set MSESH_BASH to an existing usr\bin\bash.exe.
    exit /b 1
)

if not exist "%MSESH_SETUP%" (
    >&2 echo install: cannot find install.sh next to this launcher.
    >&2 echo install: expected it at %MSESH_SETUP%
    exit /b 1
)

rem Forward slashes: bash is about to read this as a path, and some backslash
rem pairs are escape sequences to it even inside quotes.
set "MSESH_SETUP=%MSESH_SETUP:\=/%"

rem -l for a real MSYS2 environment, CHERE_INVOKING so the login profile leaves
rem us in the repo rather than wandering off to $HOME.
set "CHERE_INVOKING=1"
if not defined MSYSTEM set "MSYSTEM=UCRT64"

"%MSESH_RUNNER%" -l "%MSESH_SETUP%" %*
exit /b %ERRORLEVEL%
