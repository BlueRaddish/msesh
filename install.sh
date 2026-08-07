#!/usr/bin/env bash
# install.sh — put msesh on your PATH.
#
# Copies the files in bin/ into a directory of your choosing (default ~/bin) and
# checks that the things msesh needs are actually there. Re-running is safe; it
# overwrites.
#
# Works on Linux, macOS, Windows (MSYS2) and WSL. What differs between them is
# answered by bin/msesh-platform, which this script sources rather than
# duplicating — the installer having its own idea of where tmux lives, or of
# what to say about PATH, is how the two drift apart.
#
# Usage: ./install.sh [--prefix DIR] [--link] [--uninstall] [--check]
#
# From PowerShell or cmd, run install.cmd next to this file instead — it finds
# MSYS2's bash and hands the same arguments over to this script.
#
#   --prefix DIR  where to install (default: $HOME/bin)
#   --link        symlink instead of copying, so `git pull` here updates the
#                 installed copy. Needs Developer Mode or an elevated shell on
#                 Windows; falls back to copying if the link cannot be made.
#   --uninstall   remove the installed files, then exit
#   --check       report on prerequisites without installing anything

set -euo pipefail

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=bin/msesh-platform
. "$SELF_DIR/bin/msesh-platform"
PREFIX="$HOME/bin"
LINK=0
UNINSTALL=0
CHECK_ONLY=0
FILES="msesh msesh.cmd msesh-notify msesh-platform"

while [ $# -gt 0 ]; do
  case $1 in
    --prefix)    PREFIX=${2:?--prefix needs a directory}; shift 2 ;;
    --link)      LINK=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check)     CHECK_ONLY=1; shift ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install: unknown option: $1" >&2; exit 1 ;;
  esac
done

say()  { printf 'install: %s\n' "$*"; }
warn() { printf 'install: %s\n' "$*" >&2; }

# Where this clone is. Needed before the copy, which stamps it beside the
# installed files, and again at the end for the completion lines.
SRC_DIR=$(cd "$(dirname "$0")" && pwd)

if [ "$UNINSTALL" = 1 ]; then
  for f in $FILES; do
    [ -e "$PREFIX/$f" ] && rm -f "$PREFIX/$f" && say "removed $PREFIX/$f"
  done
  [ -e "$PREFIX/.msesh-source" ] && rm -f "$PREFIX/.msesh-source" &&
    say "removed $PREFIX/.msesh-source"
  exit 0
fi

# --- prerequisites -----------------------------------------------------------
# msesh drives tmux, and on Windows tmux ships only with MSYS2. Report on all of
# it rather than stopping at the first problem, so one run tells you everything
# you have to fix.
missing=0

say "platform: $(plat_os)"

# How fast panes will actually draw. Worth saying at install time rather than
# leaving someone to discover it as "tmux is slow": the fix is a one-time
# install, and it is much harder to change runtimes once sessions exist.
rendering=$(plat_rendering)
case ${rendering%% *} in
  ok) say "rendering: ${rendering#* }" ;;
  *)  warn "rendering: ${rendering#* }"
      warn "      Heavy output can take minutes here that take under a second"
      warn "      on WSL. Install it once, from an ADMIN PowerShell:"
      warn "        wsl --install -d Ubuntu        (a reboot may be needed)"
      warn "      then inside it: apt install tmux, and install the agent too —"
      warn "      msesh only prefers WSL once BOTH are there, because panes"
      warn "      with no agent are worse than a slow session."
      warn "      Staying here still works." ;;
esac

tmux_bin=$(plat_tmux)
if [ -x "$tmux_bin" ] || command -v "$tmux_bin" >/dev/null 2>&1; then
  say "tmux: $tmux_bin"
else
  warn "tmux: NOT FOUND."
  case $(plat_os) in
    windows|wsl) warn "      Best: 'wsl --install -d Ubuntu', then 'apt install tmux' inside it."
                 warn "      Otherwise MSYS2 (https://www.msys2.org), then 'pacman -S tmux' —"
                 warn "      which works, but redraws far more slowly. See README." ;;
    macos)       warn "      brew install tmux" ;;
    *)           warn "      Install tmux from your package manager." ;;
  esac
  missing=1
fi

if command -v claude >/dev/null 2>&1; then
  say "claude: $(command -v claude)"
else
  warn "claude: not on PATH. msesh's default presets run it; set CLAUDE_BIN or"
  warn "        edit your presets file if it lives somewhere unusual."
fi

if opener=$(plat_tab_opener); then
  say "terminal: $opener"
else
  warn "terminal: none found. msesh builds sessions fine without one — it will"
  warn "          print the attach command instead of opening a window."
fi

if notifier=$(plat_notifier); then
  say "notifier: $notifier"
else
  warn "notifier: none found. Alerts fall back to a tmux message, which is"
  warn "          enough on a machine you are looking at."
fi

[ "$CHECK_ONLY" = 1 ] && exit "$missing"
[ "$missing" = 1 ] && warn "install: continuing anyway — fix the above before running msesh."

# --- install -----------------------------------------------------------------
mkdir -p "$PREFIX"

for f in $FILES; do
  src="$SELF_DIR/bin/$f"
  dst="$PREFIX/$f"
  [ -r "$src" ] || { warn "missing $src"; exit 1; }
  rm -f "$dst"
  # `ln -s` exiting 0 is not proof of a symlink: MSYS2 and Cygwin fall back to
  # copying when the OS will not grant a native link, and still report success.
  # Test the result rather than the exit code, or --link quietly becomes --copy
  # while claiming otherwise.
  if [ "$LINK" = 1 ] && ln -s "$src" "$dst" 2>/dev/null && [ -L "$dst" ]; then
    say "linked  $dst -> $src"
  else
    if [ "$LINK" = 1 ]; then
      rm -f "$dst"
      warn "$f: could not create a real symlink — copied instead."
      warn "    (Windows needs Developer Mode, or MSYS=winsymlinks:nativestrict.)"
      warn "    Re-run this installer after editing the repo to update it."
    fi
    cp "$src" "$dst"
    say "copied  $dst"
  fi
done

chmod +x "$PREFIX/msesh" "$PREFIX/msesh-notify" 2>/dev/null || true

# Leave a note saying where this came from, so the *installed* msesh can tell
# whether the clone has moved on without it. doctor could already spot that
# drift, but only when run from the clone — which is the direction that does
# not need warning about. The direction that does is the normal one: you edited
# the clone, forgot to install, and are now running the stale copy, where msesh
# has nothing to compare against unless it was told.
printf '%s\n' "$SRC_DIR" > "$PREFIX/.msesh-source" 2>/dev/null || true

# Where "on PATH" is checked, and what to do about it, are both platform
# questions: a line in a shell rc is the right answer on Unix and exactly the
# wrong one on Windows, where PowerShell, cmd and the Run box never read it.
case $(plat_path_check "$PREFIX") in
  ok) ;;
  *)  warn "$PREFIX is not on your PATH — add it to use 'msesh' as a bare command."
      plat_path_hint "$PREFIX" | sed 's/^/install:     /' >&2 ;;
esac

# --- completion ---------------------------------------------------------------
# Printed, not written. Both files live in the clone and are sourced from
# there, so a 'git pull' updates completion without a reinstall — the opposite
# of the binaries, which are copied. Editing someone's .bashrc or $PROFILE
# behind their back is the kind of thing an installer should ask about, and
# this one has no way to ask.
if [ -r "$SRC_DIR/completion/msesh.bash" ]; then
  case " $(complete -p msesh 2>/dev/null || true) " in
    *" msesh "*) say "completion: already active in this shell" ;;
    *) say "completion: add these lines to finish (optional)"
       say "  bash        source $SRC_DIR/completion/msesh.bash"
       if plat_is_windows; then
         say "  PowerShell  . $(plat_native_path "$SRC_DIR/completion/msesh.ps1")     (in \$PROFILE)"
       fi ;;
  esac
fi

say "done. Try: msesh help"
