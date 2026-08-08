@echo off
rem msesh.cmd - the Windows-side door to msesh.
rem
rem msesh is a bash script and tmux ships only with MSYS2, so this hands the
rem invocation over to the MSYS2 bash with the current directory and the
rem arguments intact. It exists so that `msesh 4 claude` means the same thing
rem typed into PowerShell, cmd, a Windows Terminal tab, VS Code's terminal or
rem the Run box as it does inside MSYS2.
rem
rem PowerShell and cmd both prefer a .cmd over an extensionless file of the
rem same name, and bash only ever looks for the exact name, so `msesh` lands
rem here on Windows and on the bash script itself under MSYS2. Neither side
rem needs to know about the other.
rem
rem MSESH_BASH points at a bash.exe outright; MSESH_MSYS_ROOT points at an
rem MSYS2 install root when it is somewhere unusual.

setlocal

set "MSESH_SCRIPT=%~dp0msesh"
set "MSESH_RUNNER="

rem WSL first, when it can host a session, because going via MSYS2 only to hand
rem over again costs a whole extra login shell - measured at ~230ms of a ~800ms
rem command, spent starting an environment nothing then uses. MSESH_RUNTIME
rem pins the old route.
rem
rem The arguments cross as real argv: `bash -lc 'exec "$@"' _ prog args...`
rem hands them to bash as positional parameters rather than pasting them into a
rem command string, so a quoted sentence - 'msesh send work "look at src/"' -
rem survives without cmd's quoting rules getting a vote.
if defined MSESH_RUNTIME goto :viamsys
where wsl.exe >nul 2>&1 || goto :viamsys

rem Translate the path here rather than asking wslpath: starting a distro to
rem convert a string costs as much as the command being run. C:\x -> /mnt/c/x.
set "MSESH_WSLPATH=%MSESH_SCRIPT:\=/%"
set "MSESH_DRV=%MSESH_WSLPATH:~0,1%"
set "MSESH_REST=%MSESH_WSLPATH:~2%"
for %%D in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    if /i "%MSESH_DRV%"=="%%D" set "MSESH_DRV=%%D"
)
set "MSESH_WSLPATH=/mnt/%MSESH_DRV%%MSESH_REST%"

rem Ask once whether WSL can host a session, then remember. The probe is
rem another distro start, and paying it before every command to re-learn an
rem answer that changes when you install something is the wrong trade. Delete
rem the marker to ask again.
set "MSESH_WSLOK=%TEMP%\msesh-wsl-ok"
if exist "%MSESH_WSLOK%" goto :runwsl
wsl.exe -e bash -lc "command -v tmux >/dev/null 2>&1" >nul 2>&1 || goto :viamsys
break > "%MSESH_WSLOK%"

:runwsl
wsl.exe -e bash -lc "exec \"$@\"" _ "%MSESH_WSLPATH%" %*
exit /b %ERRORLEVEL%

:viamsys

if defined MSESH_BASH if exist "%MSESH_BASH%" set "MSESH_RUNNER=%MSESH_BASH%"
if not defined MSESH_RUNNER if defined MSESH_MSYS_ROOT if exist "%MSESH_MSYS_ROOT%\usr\bin\bash.exe" set "MSESH_RUNNER=%MSESH_MSYS_ROOT%\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "%SystemDrive%\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=%SystemDrive%\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "C:\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=C:\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "C:\tools\msys64\usr\bin\bash.exe" set "MSESH_RUNNER=C:\tools\msys64\usr\bin\bash.exe"
if not defined MSESH_RUNNER if exist "%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe" set "MSESH_RUNNER=%USERPROFILE%\scoop\apps\msys2\current\usr\bin\bash.exe"

if not defined MSESH_RUNNER (
    >&2 echo msesh: no MSYS2 bash found - msesh needs tmux, which ships with MSYS2.
    >&2 echo msesh: install MSYS2, or set MSESH_BASH to its usr\bin\bash.exe.
    exit /b 1
)

if not exist "%MSESH_SCRIPT%" (
    >&2 echo msesh: cannot find the msesh script next to this launcher.
    >&2 echo msesh: expected it at %MSESH_SCRIPT%
    exit /b 1
)

rem Forward slashes: bash is about to read this as a path, and backslashes are
rem escape characters to it even inside quotes for some of them.
set "MSESH_SCRIPT=%MSESH_SCRIPT:\=/%"

rem -l gives the script a real MSYS2 environment - tmux, cygpath, awk and sed
rem on PATH - the way it would have had if you had typed it in an MSYS2 shell.
rem CHERE_INVOKING keeps the login profile from wandering off to $HOME, so a
rem pane's working directory is still the directory you called msesh from.
set "CHERE_INVOKING=1"
if not defined MSYSTEM set "MSYSTEM=UCRT64"

"%MSESH_RUNNER%" -l "%MSESH_SCRIPT%" %*
exit /b %ERRORLEVEL%
