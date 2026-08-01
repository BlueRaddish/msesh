# Suggestions

Ideas for msesh that are **not built**, written down so they can be picked or
dropped deliberately. Nothing here is a commitment; roughly, the ones marked
**worth doing** are the ones I would build next, and the rest are recorded so
they stop being re-thought from scratch.

Current state for reference: v0.2.0, verb-first CLI, presets and layouts
authored by `msesh preset make`.

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

### 2.1 `preset make --from-session NAME` — **worth doing**

Snapshot a live session into a named layout: read its panes back out of tmux
and write the layout file. The session you are sitting in is usually a better
description of what you want than anything you would type into a wizard, and
msesh already reads pane labels for the border format, so most of the machinery
is there. The one hard part is recovering a pane's *command* rather than its
label once the command has been replaced by the shell that keeps the pane
alive — the label is probably good enough, since it is the preset name.

### 2.2 Layouts should be distinguishable from recorded sessions — **worth doing**

Both live in the manifest directory and `msesh list` shows them in one column.
A layout you wrote on purpose and a session msesh happened to record are
different things: the first should survive `forget --all`-style cleanups and
should probably not be silently rewritten by a build under the same name.

Cheap version: a `layout=1` key in the file, a `(layout)` marker in `msesh
list`, and a warning when a build is about to overwrite one.

### 2.3 Per-pane settings in a layout

Today a layout has one working directory for all panes and one effort list
spread across the claude ones. Real sessions want per-pane dirs (three repos,
one pane each) and per-pane effort. This means a spec syntax extension —
`claude@high`, `claude:/c/path` — or a richer layout file that is no longer the
same format as a manifest. Worth doing eventually, worth resisting until the
need is concrete, because it is the change most likely to make the file format
something you have to read the manual for.

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

### 3.1 An agent registry instead of `is_claude_cmd` — **worth doing**

One function decides today whether a pane is "a claude pane", and that single
bit controls two unrelated things: whether `--effort` is injected, and whether
`--lazy` pre-types instead of running. Neither is really about Claude — they
are about "this is an expensive interactive agent, not a shell".

Suggest a small table: command name → does it take an effort/reasoning flag,
and how is that flag spelled. Then `-e` works for codex and gemini too, and
`--lazy` covers any agent rather than one vendor's.

Rough shape, one line per agent:

    claude   effort:--effort        levels:low,medium,high,xhigh
    codex    effort:-c model_reasoning_effort=  levels:low,medium,high
    gemini   effort:(none)
    aider    effort:(none)

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
the verbs, preset names and session names, plus a PowerShell
`Register-ArgumentCompleter`, would make the whole surface explorable by Tab.
This is probably the single highest-value item on this page now that the verbs
exist.

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

### 5.2 Named windows from a layout

Windows are `m1`, `m2`, … A layout could name them (`repo`, `logs`), which
makes `prefix+n` navigation mean something once there are more than two.

### 5.3 `--dry-run` on build

Print the panes, commands and window split that *would* be created. Useful when
working out what a spec line does, and a much cheaper way to check a layout
than launching four agents.

---

## 6. Robustness

### 6.1 A version key in the manifest format

`version=1` at the top of every manifest and layout. Nothing needs it today;
the first time the format changes it is the difference between a migration and
a puzzling failure.

### 6.2 Test script

There is no test suite. Everything in this repo has been verified by hand,
which is fine at this size, but the spec parser and the manifest round-trip are
both pure logic with no tmux involvement and could be tested cheaply. A single
`test.sh` covering spec resolution, manifest save/load, and the preset file
rewrite would have caught the `add`-clobbers-the-manifest bug fixed in v0.2.0.
