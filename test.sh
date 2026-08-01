#!/usr/bin/env bash
# msesh test script.
#
# Covers the parts that are pure logic — spec resolution, effort assignment
# against the agent table, layout resolution, the preset file rewrite and the
# manifest round-trip. All of it goes through `--dry-run`, so no tmux session
# is ever built and the whole run takes a second.
#
# What is deliberately not here: anything about what tmux actually draws. Pane
# borders and the status bar cannot be read with capture-pane — see
# SUGGESTIONS.md §6.3 for the outer-tmux trick that can, which is worth adding
# here once the alert path stops changing.
#
# Run it from anywhere:  ./test.sh  [-v]
#
# Every case runs against a scratch HOME-like config, so your real presets,
# layouts and manifests are never read or written.

set -uo pipefail

MSESH=${MSESH:-$(cd "$(dirname "$0")" && pwd)/bin/msesh}
[ -x "$MSESH" ] || { echo "test: no msesh at $MSESH" >&2; exit 1; }

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

ROOT=${TMPDIR:-/tmp}/msesh-test.$$
export MSESH_STATE=$ROOT/sessions
export MSESH_LAYOUTS=$ROOT/layouts
export MSESH_PRESETS=$ROOT/presets.conf
export MSESH_AGENTS=$ROOT/agents.conf
# Stops the re-exec into MSYS2: this script is already wherever it needs to be,
# and a second hop would lose the environment above.
export MSESH_REEXEC=1
export CLAUDE_BIN=claude CLAUDE_FLAGS=--remote-control

mkdir -p "$MSESH_STATE" "$MSESH_LAYOUTS"
trap 'rm -rf "$ROOT"' EXIT

cat > "$MSESH_PRESETS" <<'EOF'
kode   = codex --full-auto
gem    = gemini
pinned = claude --effort xhigh
EOF
cat > "$MSESH_AGENTS" <<'EOF'
myagent = --reasoning | quick,deep
EOF

PASS=0 FAIL=0

# The whole harness: run msesh, keep stdout and stderr together, and look for
# a substring. Substrings rather than whole-output comparison on purpose —
# these tests should survive someone rewording a message, and fail only when
# the behaviour changes.
check() {                               # check NAME EXPECT -- ARGS...
  local name=$1 expect=$2; shift 3
  local out rc
  out=$("$MSESH" "$@" 2>&1); rc=$?
  if printf '%s' "$out" | grep -qF -- "$expect"; then
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$name"
    printf '       expected to find: %s\n' "$expect"
    printf '       got (rc=%s):\n' "$rc"
    printf '%s\n' "$out" | sed 's/^/         /'
  fi
  return 0
}

missing() {                             # missing NAME UNEXPECTED -- ARGS...
  local name=$1 unexpect=$2; shift 3
  local out
  out=$("$MSESH" "$@" 2>&1)
  if printf '%s' "$out" | grep -qF -- "$unexpect"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$name"
    printf '       should not have found: %s\n' "$unexpect"
    printf '%s\n' "$out" | sed 's/^/         /'
  else
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$name"
  fi
  return 0
}

D="-d $HOME"                            # every build needs a real directory

echo "specs"
check "bare count uses the default preset"  "4 pane(s)"     -- build 4 -n $D
check "N PRESET"                            "3 pane(s)"     -- build 3 bash -n $D
check "PRESET:N"                            "3 pane(s)"     -- build bash:2 pwsh:1 -n $D
check "+PRESET adds one"                    "4 pane(s)"     -- build 3 bash +pwsh -n $D
check "!COMMAND runs literally"             "npm run dev"   -- build '!npm run dev' -n $D
check "!COMMAND labels on the first word"   "npm  "         -- build '!npm run dev' -n $D
check "no spec means one pane"              "1 pane(s)"     -- build -n $D
check "unknown preset is named"             "unknown preset 'nope'" -- build 2 nope -n $D
check "options may follow specs"            "2 window(s)"   -- build 4 bash -w 2 -n $D
check "options may precede specs"           "2 window(s)"   -- build -w 2 4 bash -n $D
check "width 0 is one window"               "1 window(s)"   -- build 9 bash -w 0 -n $D
check "spill into windows"                  "3 window(s)"   -- build 9 bash -w 4 -n $D

echo "agents and effort"
check "ladder spreads low first"      "claude/low"    -- build 3 claude -e ladder -n $D
check "ladder spreads high last"      "claude/high"   -- build 3 claude -e ladder -n $D
check "last level repeats"            "claude/xhigh"  -- build 3 claude -e x -n $D
check "abbreviations expand"          "claude/medium" -- build 1 claude -e m -n $D
check "codex takes its own flag"      "model_reasoning_effort=high" -- build 1 kode -e h -n $D
check "user-registered agent"         "myagent/quick" -- build '!myagent chat' -e quick -n $D
check "agent without effort is skipped" "gem  "       -- build 1 gem -e high -n $D
missing "shell panes never get effort" "bash/"        -- build 2 bash -e ladder -n $D
check "a level the agent lacks is an error" \
      "runs codex, which has no 'xhigh' effort"       -- build 1 kode -e x -n $D
check "the error names the levels it has" \
      "it takes low, medium, high"                    -- build 1 kode -e x -n $D
check "a preset that spells the flag is left alone" \
      "--effort xhigh"                                -- build 1 pinned -e low -n $D
missing "and is not given a second one" \
      "--effort xhigh --effort low"                   -- build 1 pinned -e low -n $D
# The bug this guards: an agent with no effort flag must not consume a level,
# or every agent after it in the session shifts by one.
check "skipped agents do not consume a level" \
      "claude/low"                                    -- build gem claude kode -e l,h -n $D
check "so the next agent still gets the second" \
      "kode/high"                                     -- build gem claude kode -e l,h -n $D

echo "window names"
check "windows are named in order"    "window repo"   -- build 4 bash -w 2 --windows repo,logs -n $D
check "names run out silently"        "window m3"     -- build 6 bash -w 2 --windows repo -n $D
check "a colon is rejected"           "cannot contain" -- build 2 bash --windows 'a:b' -n $D

echo "presets file"
"$MSESH" preset make review "claude /code-review" >/dev/null
check "a written preset resolves"     "/code-review"  -- build 1 review -n $D
"$MSESH" preset make review "claude /security-review" >/dev/null
check "writing it again replaces it"  "/security-review" -- build 1 review -n $D
missing "and does not leave the old one" "/code-review" -- preset show review
check "preset show prints the command" "claude"       -- preset show review
check "removing it is reported"       "removed preset 'review'" -- preset remove review
check "and then it is gone"           "unknown preset 'review'" -- build 1 review -n $D
check "a built-in cannot be removed"  "is a built-in" -- preset remove claude
check "user presets survived the rewrite" "codex --full-auto" -- preset show kode

echo "layouts"
"$MSESH" layout make quad 4 claude -e l,m,h,x -d "$HOME" >/dev/null
check "a layout builds its panes"     "4 pane(s)"     -- build quad -n
check "with its own effort list"      "claude/xhigh"  -- build quad -n
check "and names the session"         "would build 'quad'" -- build quad -n
check "-s overrides the name"         "would build 'spike'" -- build quad -s spike -n
check "an option overrides the file"  "claude/low"    -- build quad -e low -n
check "a layout in a spec list is an error" \
      "is a layout"                                   -- build quad +pwsh -n $D
check "so is a count in front of one"  "is a layout"  -- build 3 quad -n $D
check "and adding one to a session"    "is a layout"  -- add quad -n $D
check "layout list shows its panes"    "4 claude"     -- layout list
check "layout show prints the file"    "layout=1"     -- layout show quad
check "a missing layout is named"      "no layout 'nope'" -- layout show nope
check "layout remove reports"          "removed layout 'quad'" -- layout remove quad
check "and then build cannot find it"  "unknown preset 'quad'" -- build quad -n $D

echo "manifests"
# Written by hand rather than by a build: a dry run deliberately writes no
# manifest, and this is a round-trip test of the reader, not of tmux.
cat > "$MSESH_STATE/hand.conf" <<EOF
version=1
dir=$HOME
effort=ladder
eager=1
width=2
notify=30
windows=alpha,beta
spec=3
spec=claude
EOF
check "restore reads the pane specs"   "3 pane(s)"    -- restore hand -n
check "restore reads the width"        "2 window(s)"  -- restore hand -n
check "restore reads the effort"       "claude/medium" -- restore hand -n
check "restore reads the window names" "window alpha" -- restore hand -n
check "restore reads the notify"       "toast after 30s" -- restore hand -n
check "a flag beats the file"          "1 window(s)"  -- restore hand -w 0 -n
check "an unknown session is named"    "no manifest or layout for 'ghost'" -- restore ghost -n
printf 'version=99\nspec=1\nspec=bash\ndir=%s\n' "$HOME" > "$MSESH_STATE/future.conf"
check "a newer format warns"           "is format 99" -- restore future -n
check "but is still read"              "1 pane(s)"    -- restore future -n

# --- portability ---------------------------------------------------------------
# These two guard the invariant the platform layer exists for. They are not
# about behaviour, so they do not use `check`; they read the source.
#
# Without them the abstraction rots silently: someone adds a quick `cygpath`
# call, it works on their machine, and the next person on a Mac finds out.
echo "portability"

port_fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  printf '%s\n' "$2" | sed 's/^/         /'
}
port_ok() { PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$1"; return 0; }

SRC=$(cd "$(dirname "$MSESH")" && pwd)

# Comment lines are exempt: explaining *why* cmd.exe needs a handover is
# exactly the kind of thing that should stay written next to the code, and a
# test that forbids saying the word would push that knowledge out of the file.
uncommented() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; }

# Executable names only — the help text is allowed to document MSESH_MSYS_ROOT
# and WT_BIN, because those are real overrides the platform layer honours.
leaks=$(grep -nE 'cygpath|wt\.exe|powershell|reg\.exe|cmd\.exe|/c/msys|md5sum' \
        "$SRC/msesh" "$SRC/msesh-notify" 2>/dev/null | uncommented || true)
if [ -n "$leaks" ]; then
  port_fail "no platform binaries outside msesh-platform" "$leaks"
else
  port_ok "no platform binaries outside msesh-platform"
fi

# macOS ships bash 3.2 and Apple will not move. These are the constructs that
# would break there, and they are easier to ban than to remember.
b4=$(grep -nE 'mapfile|readarray|declare -A|local -n|\[-1\]|\$\{[A-Za-z_]+,,\}' \
     "$SRC/msesh" "$SRC/msesh-notify" "$SRC/msesh-platform" 2>/dev/null \
     | uncommented || true)
if [ -n "$b4" ]; then
  port_fail "nothing that needs bash 4" "$b4"
else
  port_ok "nothing that needs bash 4"
fi

# Git on Windows does not track the executable bit, so a script committed from
# there arrives mode 644 on Linux and macOS and `./install.sh` answers
# "permission denied" — which is invisible from the machine that committed it.
# This repo shipped that bug from its first commit until CI existed.
if command -v git >/dev/null 2>&1 && [ -d "$SRC/../.git" ]; then
  notexec=$(cd "$SRC/.." && git ls-files -s bin/msesh bin/msesh-notify \
              install.sh test.sh 2>/dev/null | grep -v '^100755' || true)
  if [ -n "$notexec" ]; then
    port_fail "scripts are executable in git" \
      "$(printf '%s\n' "$notexec")
       fix: git update-index --chmod=+x <file>"
  else
    port_ok "scripts are executable in git"
  fi
fi

# The platform layer must answer every question the rest of the script asks of
# it; a missing function is a runtime error on one OS only, which is the worst
# kind to find late.
missing_fn=
for fn in plat_os plat_is_windows plat_tmux plat_bootstrap plat_bootstrap_argv \
          plat_open_tab plat_tab_opener plat_notify plat_notifier \
          plat_native_path plat_config_home plat_checksum plat_path_check \
          plat_path_hint plat_shell_presets; do
  grep -q "^$fn()" "$SRC/msesh-platform" || missing_fn="$missing_fn $fn"
done
if [ -n "$missing_fn" ]; then
  port_fail "platform layer is complete" "missing:$missing_fn"
else
  port_ok "platform layer is complete"
fi

# Exercised rather than assumed: each of the three OS branches must produce a
# config path and a shell preset list without erroring, on whatever machine the
# suite happens to be running on.
for os in linux macos windows wsl; do
  out=$(MSESH_OS=$os bash -c ". '$SRC/msesh-platform'; plat_config_home; echo; plat_shell_presets" 2>&1)
  case $out in
    */msesh*) port_ok "platform branch: $os" ;;
    *)        port_fail "platform branch: $os" "$out" ;;
  esac
done

echo "the version key is written"
"$MSESH" layout make v 1 bash -d "$HOME" >/dev/null
check "layouts carry a version"        "version=1"    -- layout show v

echo
if [ "$FAIL" = 0 ]; then
  echo "$PASS passed"
else
  echo "$PASS passed, $FAIL failed"
  exit 1
fi
