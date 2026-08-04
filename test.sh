#!/usr/bin/env bash
# msesh test script.
#
# Covers the parts that are pure logic — spec resolution, effort assignment
# against the agent table, layout resolution, the preset file rewrite and the
# manifest round-trip. All of it goes through `--dry-run`, so no tmux session
# is ever built.
#
# Every check is one msesh invocation, so the runtime is process startup and
# nothing else: a couple of seconds on Linux and macOS, around four minutes on
# Windows under MSYS2, where spawning is expensive. It is not hung.
#
# What is deliberately not here: anything about what tmux actually draws. Pane
# borders and the status bar cannot be read with capture-pane — see
# the WORKFLOW.md in this project's PARA folder for the outer-tmux trick that
# can, which is worth adding here once the alert path stops changing.
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
# Pointed at the scratch tree before a single check runs, so that no bug in
# 'msesh hooks' — and no test added later in a hurry — can reach the real
# ~/.claude/settings.json. That file belongs to Claude Code and commonly holds
# hooks the user wrote; damaging it would not break msesh, it would silently
# stop their work running.
export CLAUDE_SETTINGS=$ROOT/settings.json

mkdir -p "$MSESH_STATE" "$MSESH_LAYOUTS"
trap 'rm -rf "$ROOT"' EXIT

# The agent presets are defined here rather than relied on: built-in agent
# presets only exist when the binary is installed, and a CI runner has none.
# The command name is what makes a pane an agent pane, so these are enough.
cat > "$MSESH_PRESETS" <<'EOF'
claude = claude
kode   = codex --full-auto
gem    = gemini
pinned = claude --effort xhigh
EOF
cat > "$MSESH_AGENTS" <<'EOF'
myagent = --reasoning | quick,deep
EOF

PASS=0 FAIL=0 SKIP=0

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
# 'shell', not 'claude': agent presets only exist where the agent is installed,
# so on a machine without one 'preset remove claude' would remove the fixture
# this file wrote and every layout test after it would fail. 'shell' is built in
# everywhere.
check "a built-in cannot be removed"  "is a built-in" -- preset remove shell
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

echo "resuming a conversation"
# Snapshots are normally written from a live session. These are hand-built so
# the whole resume path can be tested without a tmux server — what is being
# checked is the matching, not tmux's ability to list panes.
SNAPDIR=$MSESH_STATE/snapshots/$(bash -c ". '$(dirname "$MSESH")/msesh-platform'; plat_host")
mkdir -p "$SNAPDIR"
{
  printf 'version=2\nsnapshot=%s\n' "$(date +%s)"
  printf 'dir=%s\nspec=2\nspec=claude\n' "$HOME"
  printf 'window=1|m1|d44e,80x24,0,0[80x11,0,0,60,80x12,0,12,61]\n'
  printf 'pane=1|claude|claude|%s|aaaaaaaa-1111-4444-8888-cccccccccccc\n' "$HOME"
  printf 'pane=1|claude|claude|%s|bbbbbbbb-2222-4444-8888-cccccccccccc\n' "$HOME"
} > "$SNAPDIR/resumed-$(date +%s).conf"

check "--resume reopens the recorded conversation" \
      "--resume aaaaaaaa-1111"                    -- restore resumed --resume -n
check "each pane gets its own conversation" \
      "--resume bbbbbbbb-2222"                    -- restore resumed --resume -n
check "resumed panes are marked in the label"  "claude~" -- restore resumed --resume -n
check "and it says how many came back"  "2 pane(s) would resume" -- restore resumed --resume -n
missing "a plain restore stays fresh"   "--resume aaaaaaaa" -- restore resumed -n
check "--resume needs restore"          "--resume goes with restore" -- build 2 claude --resume -n

# The failure this guards: a pane with no recorded conversation must start
# fresh rather than fail the restore, or one unstarted agent would make the
# whole session unrestorable.
{
  printf 'version=2\nsnapshot=%s\n' "$(date +%s)"
  printf 'dir=%s\nspec=3\nspec=claude\n' "$HOME"
  printf 'pane=1|claude|claude|%s|\n' "$HOME"
  printf 'pane=1|claude|claude|%s|dddddddd-3333-4444-8888-cccccccccccc\n' "$HOME"
  printf 'pane=1|claude|claude|%s|\n' "$HOME"
} > "$SNAPDIR/partial-$(date +%s).conf"
check "a pane with no conversation starts fresh" \
      "1 pane(s) would resume a conversation, 2 would start fresh" \
                                                  -- restore partial --resume -n
check "while its neighbour still resumes" "--resume dddddddd-3333" -- restore partial --resume -n
# A recorded session that was never snapshotted: --resume has nothing to work
# from, and the restore has to go ahead anyway rather than refuse.
printf 'version=2\ndir=%s\nspec=2\nspec=claude\n' "$HOME" > "$MSESH_STATE/nosnap.conf"
check "a session with no snapshot says so" \
      "no snapshot of 'nosnap'"                   -- restore nosnap --resume -n
check "and restores fresh anyway"     "2 pane(s)" -- restore nosnap --resume -n
check "with nothing claimed as resumed" \
      "0 pane(s) would resume"                    -- restore nosnap --resume -n
check "a session that is not known at all is still refused" \
      "no manifest or layout for 'ghostsess'"     -- restore ghostsess --resume -n

echo "the format version"
printf 'version=1\ndir=%s\nspec=1\nspec=bash\n' "$HOME" > "$MSESH_STATE/older.conf"
missing "an older manifest reads without a warning" "is format 1" -- restore older -n
check "and still restores"             "1 pane(s)"  -- restore older -n

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

# Always printed, never counted as a pass. A check that could not run is not a
# check that succeeded, and the difference has been invisible three times now:
# once in a worktree, once on macOS, once on the MSYS2 CI job.
port_skip() {
  SKIP=$((SKIP + 1))
  printf '  SKIP %s — %s\n' "$1" "$2"
  return 0
}

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
#
# Asked of git rather than by looking for a .git directory: in a linked
# worktree .git is a *file*, so the directory test quietly skipped this guard
# in exactly the checkouts where work happens.
#
# A skipped check says so out loud. It used to just vanish, which is how it went
# unnoticed that it never ran in a worktree, and then that it never ran on the
# MSYS2 CI job either — the one platform whose treatment of the exec bit causes
# the bug in the first place. An invisible skip is a check you think you have.
if ! command -v git >/dev/null 2>&1; then
  port_skip "scripts are executable in git" "no git on PATH"
elif ! git -C "$SRC/.." rev-parse --git-dir >/dev/null 2>&1; then
  port_skip "scripts are executable in git" "not a git checkout"
else
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
          plat_path_hint plat_shell_presets plat_host; do
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

# --- help ----------------------------------------------------------------------
# There was no coverage here at all until v1.1.0, which is exactly why the front
# page still promised a Windows Terminal tab two releases after that stopped
# being true, and why two options added in 0.6.0 were never listed. A verb that
# is not on the front page and has no topic is a verb nobody finds.
echo "help"

for t in specs options preset layout agents hooks resume files env; do
  check "topic '$t' resolves" "" -- help "$t"
done
check "an unknown topic lists the real ones" "topics: specs" -- help nope

for v in build rebuild add attach restore kill snapshot forget list status send doctor \
         hooks preset layout; do
  check "the front page lists '$v'" "  $v" -- help
done
check "the front page shows --version" "--version" -- help

# --- help conformance ----------------------------------------------------------
# The Help Screen Protocol's lint rules. Help rots silently and review does not
# catch it — this file exists because it drifted twice in one day.
echo "help conformance"

for t in "" specs options preset layout agents hooks resume files env; do
  out=$("$MSESH" help $t 2>/dev/null)
  label=${t:-main}

  wide=$(printf '%s
' "$out" | awk 'length($0) > 95 { print NR": "length($0) }')
  [ -z "$wide" ] && port_ok "L1 '$label' fits 95 columns"                  || port_fail "L1 '$label' fits 95 columns" "$wide"

  # L14: tab width is unpredictable across terminals and breaks alignment.
  case $out in
    *"$(printf '	')"*) port_fail "L14 '$label' has no tabs" "found a tab" ;;
    *) port_ok "L14 '$label' has no tabs" ;;
  esac

  # L9: escape codes must never survive a pipe.
  case $out in
    *$'['*) port_fail "L9 '$label' has no escape codes" "found ESC[" ;;
    *) port_ok "L9 '$label' has no escape codes" ;;
  esac
done

for t in "" specs options preset layout agents hooks resume files env; do
  out=$("$MSESH" help $t 2>/dev/null)
  label=${t:-main}

  # L6: a description is a label, not a sentence — lowercase, no full stop.
  # Only two-column rows are descriptions, so a row is a left token of at most
  # 28 characters, then a gutter of two or more spaces, then the description.
  # Prose paragraphs are single-spaced and never match; the agents table is
  # skipped by its border characters.
  # [$] rather than \$: macOS ships the one-true-awk, which rejects \$ in a
  # regex as an unknown escape. It did so silently — awk bailed out, printed
  # nothing, and an empty result reads exactly like "no violations", so this
  # rule passed on macOS for a whole release without ever running. Hence the
  # exit status is now checked too: a lint that cannot fail is not a lint.
  bad=$(printf '%s\n' "$out" | awk '
    /^[ ]*[|+]/ { next }                      # the agents table, not a row
    /^[ ]*[$] / { next }                      # an example, not a row
    {
      n = split($0, f, /[ ][ ]+/)
      if (n < 3 || f[1] != "") next           # needs indent, token, description
      if (length(f[2]) > 28) next             # a long left side is prose
      d = f[3]
      # A capitalised word is a sentence opener. A placeholder (N, PRESET) and
      # a path (C:/...) are neither, so the test is capital-then-lowercase.
      if (d ~ /^[A-Z][a-z]/ || d ~ /[.]$/) print NR": "d
    }')
  awkrc=$?
  if [ "$awkrc" != 0 ]; then
    port_fail "L6 '$label' descriptions are labels" "awk failed (rc=$awkrc) — the rule did not run"
  else
    [ -z "$bad" ] && port_ok "L6 '$label' descriptions are labels"         || port_fail "L6 '$label' descriptions are labels" "$bad"
  fi

  # L8: one placeholder style — UPPER, with POSIX brackets for what is
  # optional. An angled placeholder is a second style, which is the mix the
  # rule exists to forbid.
  case $out in
    *'<'[a-zA-Z]*'>'*) port_fail "L8 '$label' has one placeholder style" "found an angled placeholder" ;;
    *) port_ok "L8 '$label' has one placeholder style" ;;
  esac
done

# L4: asking for help is not an error, so nothing goes to stderr.
err=$("$MSESH" help 2>&1 >/dev/null)
[ -z "$err" ] && port_ok "L4 help writes nothing to stderr"               || port_fail "L4 help writes nothing to stderr" "$err"

# L3: and it succeeds.
"$MSESH" help >/dev/null 2>&1 && port_ok "L3 help exits 0"                               || port_fail "L3 help exits 0" "non-zero exit"

# L12: what help documents and what the parser accepts must be the same set.
# This is the rule that would have caught --dry-run and --windows missing from
# the summary line for three releases, and --now and --no-enter never being
# documented at all. Both directions fail: a documented flag that the parser
# rejects is a lie, an accepted flag nobody documents is unsupported.
# Read off the case *patterns*, not the first flag on each line: --eager|--now
# and ''|help|--help|-h are both single branches naming more than one spelling,
# and taking only the first would report the others as undocumented.
parser_flags=$(grep -oE '^[[:space:]]*[^();|&]*(\|[^();|&]*)*\)' "$SRC/msesh" |
               grep -oE '\-\-[a-z][a-z-]*' | sort -u)
doc_flags=$( { "$MSESH" help options; "$MSESH" help; } 2>/dev/null |
             grep -oE '\-\-[a-z][a-z-]*' | sort -u)

undocumented=$(comm -23 <(printf '%s\n' "$parser_flags") <(printf '%s\n' "$doc_flags"))
[ -z "$undocumented" ] && port_ok "L12 every flag the parser takes is documented" \
  || port_fail "L12 every flag the parser takes is documented" "$undocumented"

invented=$(comm -13 <(printf '%s\n' "$parser_flags") <(printf '%s\n' "$doc_flags"))
[ -z "$invented" ] && port_ok "L12 every documented flag is real" \
  || port_fail "L12 every documented flag is real" "$invented"

# L13: the examples are the part people copy, so they have to still parse.
# Each is run against the scratch config with --dry-run forced, which exercises
# the whole argument path without building anything. Examples that are not
# msesh commands, or that would write outside the sandbox, are skipped by name.
#
# Collected into a variable first, deliberately. This pipeline used to live in
# the heredoc feeding the loop, and a backslash inside a command substitution
# inside an unquoted heredoc survives — awk was handed a literal `\$0`, bailed
# out, and fed the loop nothing. The rule then reported that all *zero* examples
# parsed, and passed on every platform for a whole release. Hence the count is
# now asserted below: a rule with nothing to check is a failure, not a pass.
ex_list=$(for t in "" specs options preset layout agents hooks resume files env; do
            "$MSESH" help $t 2>/dev/null
          done | sed -n 's/^[[:space:]]*\$ \(msesh .*\)$/\1/p' | awk '!seen[$0]++')

ex_run=0 ex_bad=
while IFS= read -r ex; do
  case $ex in
    *'hooks install'*|*'hooks remove'*) continue ;;   # writes settings.json
    *' edit'*) continue ;;                            # opens $EDITOR
  esac
  eval "set -- $ex" 2>/dev/null || { ex_bad="$ex_bad
  $ex -> does not even parse as a command line"; continue; }
  shift                                               # drop the leading 'msesh'
  case ${1:-} in
    build|rebuild|add|attach|restore) set -- "$@" --dry-run ;;
  esac
  # stdin from /dev/null: 'preset make' with nothing to go on asks questions,
  # and a test that waits for an answer never finishes.
  out=$("$MSESH" "$@" </dev/null 2>&1); rc=$?
  ex_run=$((ex_run + 1))
  case $out in
    *'unknown option'*|*'no help topic'*|*'unknown preset'*)
      ex_bad="$ex_bad
  \$ $ex
    $out" ;;
    *) [ "$rc" -le 1 ] || ex_bad="$ex_bad
  \$ $ex -> rc=$rc" ;;
  esac
done <<EOF
$ex_list
EOF
if [ "$ex_run" -lt 10 ]; then
  port_fail "L13 all $ex_run help examples still parse" \
    "only $ex_run examples were collected — the extraction is broken, not the help"
else
  [ -z "$ex_bad" ] && port_ok "L13 all $ex_run help examples still parse" \
    || port_fail "L13 all $ex_run help examples still parse" "$ex_bad"
fi

# L11 and the required sections of the root screen.
for want in NAME USAGE DESCRIPTION EXAMPLES COMMANDS OPTIONS "EXIT STATUS"             "SEE ALSO" "REPORT BUGS" "github.com"; do
  check "root help has $want" "$want" -- help
done

echo "hooks"
# The most invasive thing msesh does, and until now the least tested: it edits
# a file that is not its own. Everything here runs against the scratch
# CLAUDE_SETTINGS exported at the top.
#
# --dry-run is the case that earns this whole section. It was broken for the
# entire life of the feature: the subcommand re-scanned ARGS for the flag, but
# the global option parser had already consumed it into DRY_RUN and did not put
# it back, so the scan matched nothing, 'dry' was always 0, and
# 'hooks install --dry-run' performed a real install of the one thing whose
# whole design is about not surprising you.
hooks_py=$(command -v python3 || command -v python || true)
if [ -z "$hooks_py" ]; then
  SKIP=$((SKIP + 1))
  echo "  SKIP hooks (no python on this machine)"
else
  seed_settings() {
    cat > "$CLAUDE_SETTINGS" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "echo yours"}]}
    ]
  }
}
JSON
  }

  untouched() {                         # untouched NAME -- ARGS...
    local name=$1; shift 2
    local before after
    before=$(cksum < "$CLAUDE_SETTINGS")
    "$MSESH" "$@" >/dev/null 2>&1
    after=$(cksum < "$CLAUDE_SETTINGS")
    if [ "$before" = "$after" ]; then
      PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$name"
    else
      FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$name"
      printf '       "msesh %s" rewrote the settings file\n' "$*"
    fi
    return 0
  }

  in_file() {                           # in_file NAME EXPECT
    if grep -qF -- "$2" "$CLAUDE_SETTINGS" 2>/dev/null; then
      PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$1"
    else
      FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"
      printf '       settings file has no: %s\n' "$2"
    fi
    return 0
  }

  seed_settings
  check "dry-run install is hypothetical" "would add"  -- hooks install --dry-run
  check "dry-run install shows the result" '"_msesh"'  -- hooks install --dry-run
  untouched "dry-run install writes nothing"           -- hooks install --dry-run
  if [ -e "$CLAUDE_SETTINGS.msesh-backup" ]; then
    FAIL=$((FAIL + 1)); echo "  FAIL dry-run install left a backup behind"
  else
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && echo "  ok   dry-run install leaves no backup"
  fi
  check "status is quiet before installing" "0 msesh" -- hooks status
  untouched "status never writes"                     -- hooks status

  check "install adds both hooks" "the turn-end and session-start hooks" -- hooks install
  check "status counts the Stop hook"      "Stop hooks:"        -- hooks status
  check "status counts the SessionStart"   "SessionStart hooks:" -- hooks status
  check "status keeps yours apart from ours" "1 yours"          -- hooks status
  in_file "your own hook survives install"  "echo yours"
  in_file "what msesh writes is tagged"     '"_msesh"'
  check "a second install is a no-op" "already installed" -- hooks install
  untouched "a second install changes nothing"        -- hooks install

  # The v1.4.0 defect, which was invisible for two releases: python's text mode
  # rewrites every \n as \r\n on Windows, so adding one hook silently changed
  # every line of the user's file. Asserted on every platform because the bug
  # is only reachable on one, and that is the one nobody runs the suite on.
  if [ "$(tr -cd '\r' < "$CLAUDE_SETTINGS" | wc -c)" -eq 0 ]; then
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && echo "  ok   install leaves line endings alone"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL install rewrote the file to CRLF"
  fi

  check "dry-run remove is hypothetical" "would remove" -- hooks remove --dry-run
  untouched "dry-run remove writes nothing"             -- hooks remove --dry-run

  # Byte-identical round trip, measured from a file already in the canonical
  # shape. The first install/remove pair normalises the formatting; every pair
  # after it must change nothing at all. Measuring from the hand-written seed
  # instead would conflate "msesh damaged the file" with "json.dump reindented
  # it", and only one of those is a bug.
  seed_settings
  "$MSESH" hooks install >/dev/null 2>&1
  "$MSESH" hooks remove  >/dev/null 2>&1
  canon=$(cksum < "$CLAUDE_SETTINGS")
  "$MSESH" hooks install >/dev/null 2>&1
  "$MSESH" hooks remove  >/dev/null 2>&1
  if [ "$canon" = "$(cksum < "$CLAUDE_SETTINGS")" ]; then
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && echo "  ok   install then remove is a round trip"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL install then remove did not restore the file"
  fi
  in_file "remove leaves your own hook"  "echo yours"
  # Asked as a yes/no, not as a count. 'grep -c' prints 0 *and* exits 1 when it
  # matches nothing, so the obvious 'grep -c ... || echo 0' yields the string
  # "0\n0" and compares unequal to 0 — the check then fails on the one outcome
  # it exists to call a pass.
  if grep -qF -- '"_msesh"' "$CLAUDE_SETTINGS" 2>/dev/null; then
    FAIL=$((FAIL + 1)); echo "  FAIL remove left tagged entries behind"
  else
    PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && echo "  ok   remove takes all of its own"
  fi
fi

echo "the version key is written"
# Read off the script rather than written out here: this test existed to prove
# the key is present, and hardcoding the number turned the first format bump
# into a test failure that said nothing about what had broken.
FMT=$(sed -n 's/^MSESH_FORMAT=\([0-9][0-9]*\)$/\1/p' "$SRC/msesh")
"$MSESH" layout make v 1 bash -d "$HOME" >/dev/null
check "layouts carry a version"        "version=$FMT" -- layout show v

echo
# Skips are reported in the summary as well as inline: a run that quietly does
# less than the last one should be obvious from the last line alone.
summary="$PASS passed"
[ "$SKIP" != 0 ] && summary="$summary, $SKIP skipped"
if [ "$FAIL" = 0 ]; then
  echo "$summary"
else
  echo "$summary, $FAIL failed"
  exit 1
fi
