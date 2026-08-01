# Suggestions

Ideas for msesh that are **not built**, written down so they can be picked or
dropped deliberately. Nothing here is a commitment; roughly, the ones marked
**worth doing** are the ones I would build next, and the rest are recorded so
they stop being re-thought from scratch.

Current state for reference: v0.5.0, verb-first CLI, presets for one pane and
layouts for a whole session, an agent table behind `-e`, and alerts marked in
the tab title, the status bar and the pane borders.

Built since this file was written, and so removed from it: layouts as a
first-class thing with their own store and verb (2.2), saving a live session as
a layout (2.1, though from its manifest rather than by reading tmux back), and
the agent registry (3.1).

---

## 1. Deferred on purpose

### 1.1 Implicit build — **worth doing, on a condition**

`msesh 4 claude` currently errors with `'4' is a spec, not a command — try
'msesh build 4'`. It could just build.

The rule would be: if the first word is not a known command, treat the whole
line as a build. The cost is that a preset named `list`, `add` or `kill` can
then only be reached as `msesh build list`, and — worse — a *typo* that
happens to be a preset name silently builds something instead of being
corrected.

The condition: do it once the command names have settled and stopped moving,
not before. Learning the verbs is easier when the verbs are the only thing
that works. Revisit after a few weeks of use.

### 1.2 Short aliases for the verbs

`msesh b 4`, `msesh a`, `msesh k --all`. Cheap to add (one `|` per case arm),
and reintroduces exactly the memorisation problem the rewrite removed if the
short forms become what you actually type. Suggest: only `ls` for `list`, which
is already there, and nothing else.

---

## 2. Presets and layouts

### 2.1 Snapshot a *live* session, not its manifest

`msesh layout save SESS` copies the manifest, which is what msesh built, not
necessarily what is there now: panes you split by hand in tmux, or a pane whose
command you changed, are not in it. Reading the panes back out of tmux would
catch those. The hard part is unchanged — once a pane's command has exited and
been replaced by the shell that keeps the pane alive, tmux can only tell you
the label, not the command. Given the label *is* the preset name, that may be
enough, and this is only worth doing if hand-split sessions turn out to be
common.

### 2.3 Per-pane settings in a layout

Today a layout has one working directory for all panes and one effort list
spread across the agent ones. Real sessions want per-pane dirs (three repos,
one pane each) and per-pane effort. This means a spec syntax extension —
`claude@high`, `claude:/c/path` — or a richer layout file that is no longer the
same format as a manifest. Worth doing eventually, worth resisting until the
need is concrete, because it is the change most likely to make the file format
something you have to read the manual for.

Note that the per-pane *effort* half is already covered for the common case:
`-e l,m,h,x` in a layout assigns those four levels in pane order, and panes
whose agent has no effort setting are skipped rather than counted. What is
missing is only the ability to say it out of order, or per directory.

### 2.4 `preset copy OLD NEW` / `preset rename OLD NEW`

Trivial to add on top of `preset_file_set` and `preset_file_unset`. Mild value;
`preset show OLD` piped into `preset make NEW` almost covers it.

### 2.5 `preset try NAME`

Run a preset in one throwaway pane, attached, so you can see whether the
command works before wiring it into a four-pane session. Effectively
`msesh build NAME -s _try --ephemeral`, which is short enough already — the
value is in not having to think of that.

### 2.6 Preset parameters

`review = claude /code-review {branch}` used as `msesh build review:branch=main`.
Powerful and a genuine step up in complexity — a substitution syntax, quoting
rules, and errors for missing parameters. Probably the wrong direction: a
preset that needs an argument is usually better as a `!literal command` spec.

---

## 3. Other agents — the codex thread

This is the largest open item, from the earlier discussion about not being
tied to Claude Code.

### 3.1 What the agent table still does not cover

Built in 0.5.0. Two things were deliberately left out of it:

**Flags other than effort.** The table holds a name, an effort flag and its
levels, and nothing else. An agent whose equivalent of `--dangerously-skip-
permissions` is spelled differently still needs a preset. That is the right
line for now — a preset already says "this command, with these flags", and
duplicating that in the table would give two places to look.

**Anything stateful.** The workspace-trust pre-seed stays Claude-specific and
gated on a Claude pane being present, because it edits `~/.claude.json`. If
another agent ever needs the same treatment it should be its own function
beside that one, not a generic "pre-seed" hook that has to know several file
formats.

### 3.2 Built-in presets for codex, gemini, aider, copilot

Cheap, but `msesh preset list` should not fill up with agents that are not
installed. Suggest defining them only when the binary is on `PATH`, and saying
so in the list output. Until then `msesh preset make` already offers to define
an unknown name, which covers the first-run case.

### 3.3 `MSESH_DEFAULT_PRESET` is already the escape hatch

Worth documenting more loudly: someone who lives in codex sets it once and
`msesh build 4` means four codex panes. No code needed.

---

## 4. Discoverability

### 4.1 Shell completion — **worth doing**

The rewrite traded flags for words, and words complete. A bash completion for
the verbs, preset names, layout names and session names, plus a PowerShell
`Register-ArgumentCompleter`, would make the whole surface explorable by Tab.
This is probably the single highest-value item on this page now that the verbs
exist — more so with layouts, since `msesh build <tab>` now has a genuinely
useful answer.

### 4.2 `msesh doctor`

Fold `install.sh --check` into the tool itself: tmux found, MSYS2 found,
Windows Terminal found, `~/bin` on the Windows `PATH`, presets file readable,
manifest directory writable. The `PATH` check especially — that exact problem
cost three days once, and the installer's warning is only shown at install
time.

### 4.3 `msesh status`

Per pane: label, whether its command is still running, how long it has been
silent. The silence figure is what the notifier already computes, so this is
mostly a formatting job. Answers "which of these four is waiting for me" from
outside the session.

---

## 5. Session ergonomics

### 5.1 `msesh send NAME "text"`

Type the same thing into every claude pane of a session — a shared prompt, or
`/clear` across the board. tmux `send-keys` to each pane, one loop. Small and
genuinely useful with four agents; also the easiest way to make a mess, so it
should probably require the session name explicitly rather than defaulting.

### 5.2 Named windows from a layout — **worth doing**

Windows are `m1`, `m2`, … A layout could name them (`repo`, `logs`), which
makes `prefix+n` navigation mean something once there are more than two. Worth
more now than when it was written: the status bar marks the *waiting window* by
name, and `2 m2 !` says less than `2 tests !` would.

### 5.3 `--dry-run` on build — **worth doing**

Print the panes, commands and window split that *would* be created. Useful when
working out what a spec line does, and a much cheaper way to check a layout
than launching four agents. Promoted because verifying the layout work meant
building real sessions and reading pane labels back out of tmux to see what had
been assembled — which is what a dry run is.

---

## 6. Robustness

### 6.1 A version key in the manifest format — **worth doing**

`version=1` at the top of every manifest and layout. Nothing needs it today;
the first time the format changes it is the difference between a migration and
a puzzling failure. 0.5.0 moved layouts to their own directory and had to
identify the old ones by a comment in their header — which worked, but only
because they happened to have one.

### 6.2 Test script — **worth doing**

There is no test suite. Everything in this repo has been verified by hand,
which is fine at this size, but the spec parser and the manifest round-trip are
both pure logic with no tmux involvement and could be tested cheaply. A single
`test.sh` covering spec resolution, manifest save/load, and the preset file
rewrite would have caught the `add`-clobbers-the-manifest bug fixed in v0.2.0.

Two more things now want covering, and both are cheap because they are pure
logic: effort assignment against the agent table (levels an agent does not
have, agents with no effort flag not consuming a level, a preset that already
spells the flag), and layout resolution (a layout as the sole spec, a layout in
a spec list, `-s` beating the layout's name).

### 6.3 Checking what tmux actually drew

The status-bar half of the alert highlight never worked for a session with more
than one window, from the day it was written until 0.5.0, because
`window-status-format` is a *window* option and it was being set on the
session — so it landed on whichever window happened to be current and no other.
Nothing catches that class of bug by reading the code or the tmux docs, and
`capture-pane` does not see borders or the status bar.

What did catch it: attach the session inside a second, outer tmux and
`capture-pane` *that*. The rendered screen, borders and status line included,
comes back as text. Worth writing down as the way to verify anything visual
here, and worth a line in `test.sh` for the alert path specifically.
