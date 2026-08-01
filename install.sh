#!/usr/bin/env bash
# install.sh — put msesh on your PATH.
#
# Copies the three files in bin/ into a directory of your choosing (default
# ~/bin) and checks that the things msesh needs are actually there. Re-running
# is safe; it overwrites.
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

if [ "$UNINSTALL" = 1 ]; then
  for f in $FILES; do
    [ -e "$PREFIX/$f" ] && rm -f "$PREFIX/$f" && say "removed $PREFIX/$f"
  done
  exit 0
fi

# --- prerequisites -----------------------------------------------------------
# msesh drives tmux, and on Windows tmux ships only with MSYS2. Report on all of
# it rather than stopping at the first problem, so one run tells you everything
# you have to fix.
missing=0

if command -v tmux >/dev/null 2>&1; then
  say "tmux: $(command -v tmux)"
else
  found=
  for r in /c/msys64 /d/msys64 /c/tools/msys64 "$HOME/scoop/apps/msys2/current"; do
    [ -x "$r/usr/bin/tmux.exe" ] && { found=$r; break; }
  done
  if [ -n "$found" ]; then
    say "tmux: $found/usr/bin/tmux.exe (not on this shell's PATH — msesh will find it)"
  else
    warn "tmux: NOT FOUND. On Windows install MSYS2 (https://www.msys2.org) and"
    warn "      then 'pacman -S tmux'; elsewhere install tmux from your package manager."
    missing=1
  fi
fi

if command -v claude >/dev/null 2>&1; then
  say "claude: $(command -v claude)"
else
  warn "claude: not on PATH. msesh's default presets run it; set CLAUDE_BIN or"
  warn "        edit your presets file if it lives somewhere unusual."
fi

case $(uname -s 2>/dev/null || echo unknown) in
  MINGW*|MSYS*|CYGWIN*)
    if command -v wt.exe >/dev/null 2>&1 || [ -x "$LOCALAPPDATA/Microsoft/WindowsApps/wt.exe" ]; then
      say "Windows Terminal: found"
    else
      warn "Windows Terminal: not found. msesh builds sessions fine without it,"
      warn "                  but cannot open a tab — use 'msesh build --no-tab' and attach."
    fi ;;
  *)
    say "non-Windows host: msesh.cmd and the toast notifier are Windows-only;"
    say "                  the tmux side works, use --no-notify." ;;
esac

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

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) warn "$PREFIX is not on your PATH — add it to use 'msesh' as a bare command."
     # On Windows the usual mistake is to add it to a shell rc, which cmd,
     # PowerShell and the Run box never read — msesh then works in bash and
     # looks broken everywhere else. Say where it actually has to go.
     case $(uname -s 2>/dev/null || echo unknown) in
       MINGW*|MSYS*|CYGWIN*)
         warn "    On Windows put it on the *User* PATH, not in .bashrc:"
         warn "    PowerShell: [Environment]::SetEnvironmentVariable('PATH',"
         warn "      [Environment]::GetEnvironmentVariable('PATH','User') + ';$(cygpath -w "$PREFIX" 2>/dev/null || echo "$PREFIX")', 'User')"
         warn "    Then open a new terminal — PATH is read once, at startup." ;;
     esac ;;
esac

# --- completion ---------------------------------------------------------------
# Printed, not written. Both files live in the clone and are sourced from
# there, so a 'git pull' updates completion without a reinstall — the opposite
# of the binaries, which are copied. Editing someone's .bashrc or $PROFILE
# behind their back is the kind of thing an installer should ask about, and
# this one has no way to ask.
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -r "$SRC_DIR/completion/msesh.bash" ]; then
  case " $(complete -p msesh 2>/dev/null || true) " in
    *" msesh "*) say "completion: already active in this shell" ;;
    *) say "completion: add these lines to finish (optional)"
       say "  bash        source $SRC_DIR/completion/msesh.bash"
       ps1_win=$(cygpath -w "$SRC_DIR/completion/msesh.ps1" 2>/dev/null ||
                 echo "$SRC_DIR/completion/msesh.ps1")
       say "  PowerShell  . $ps1_win     (in \$PROFILE)" ;;
  esac
fi

say "done. Try: msesh help"
