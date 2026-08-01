# Suggestions

Ideas for msesh that are **not built**, written down so they can be picked or
dropped deliberately. Nothing here is a commitment.

Ordered by what I would build next — value first, cost as the tiebreak — rather
than by topic, so it can be read top to bottom and approved by range ("do P1–P4").
Numbers are positions in that order and will move; the `§` in each heading is the
stable id the PARA doc and commit messages refer to.

Current state for reference: v0.5.0 — verb-first CLI, presets for one pane and
layouts for a whole session, an agent table behind `-e`, and alerts marked in the
tab title, the status bar and the pane borders.

Built since this file was written, and so removed from it: layouts as a
first-class thing with their own store and verb (§2.2), saving a session as a
layout (§2.1, from its manifest rather than by reading tmux back), and the agent
registry (§3.1).

## At a glance

| | | Cost | Why here |
|---|---|---|---|
| **P1** | `version=` in the file format §6.1 | tiny | Gets more expensive every day it is not there |
| **P2** | `--dry-run` on build §5.3 | small | Makes everything else cheap to check |
| **P3** | `test.sh` §6.2 | small | Nothing guards what 0.5.0 just added |
| **P4** | Shell completion §4.1 | medium | The biggest everyday win |
| **P5** | Named windows from a layout §5.2 | small | Feeds the alert surface just fixed |
| **P6** | `msesh status` §4.3 | small | Answers "which one is waiting" from outside |
| **P7** | `msesh doctor` §4.2 | small | Matters to other people's machines more than this one |
| **P8** | `msesh send NAME "text"` §5.1 | small | Useful with four agents; easiest way to make a mess |
| **P9** | Implicit build §1.1 | tiny | Deliberately waiting on the verbs settling |
| **P10** | Built-in presets for other agents §3.2 | small | Nothing to gain until one is installed |
| **P11** | Snapshot a live session §2.1 | medium | Only if hand-split sessions turn out to be common |
| **P12** | Per-pane settings in a layout §2.3 | medium | Resist until the need is concrete |
| **P13** | `preset try NAME` §2.5 | tiny | Already one command; value is not having to think of it |
| **P14** | `preset copy` / `rename` §2.4 | tiny | Mild |
| **P15** | Short verb aliases §1.2 | tiny | Recommend against, beyond the `ls` that exists |
| **P16** | Preset parameters §2.6 | large | Recommend against |

The line I would draw: **P1–P5 next**, P6–P8 when they are wanted, P9–P14 on
demand, P15–P16 not at all.

---

## P1 — `version=` in the manifest and layout format §6.1

`version=1` at the top of every manifest and layout. Nothing needs it today; the
first time the format changes it is the difference between a migration and a
puzzling failure.

First on the list because it is two lines and the cost of not having it grows
with every file written. 0.5.0 already paid some of it: moving layouts to their
own directory meant identifying the old ones by a comment in their header, which
worked only because they happened to have one.

## P2 — `--dry-run` on build §5.3

Print the panes, commands and window split that *would* be created, and exit.

Useful on its own for working out what a spec line does, and much cheaper than
launching four agents to find out. Second because it makes the two items after it
easier: verifying the layout work meant building real sessions and reading pane
labels back out of tmux, which is a dry run done the expensive way, and a test
script wants exactly this output to assert against.

## P3 — `test.sh` §6.2

There is no test suite. Everything here has been verified by hand, which is fine
at this size, but the spec parser and the manifest round-trip are pure logic with
no tmux involvement and could be tested cheaply. Spec resolution, manifest
save/load and the preset file rewrite would have caught the
`add`-clobbers-the-manifest bug fixed in v0.2.0.

Two more things now want covering, both also pure logic:

- **effort against the agent table** — a level an agent does not have, an agent
  with no effort flag not consuming a level, a preset that already spells the flag
- **layout resolution** — a layout as the sole spec, a layout inside a spec list,
  `-s` beating the layout's name, `build` preferring the definition while
  `restore` prefers the recording

Third rather than first because P2 gives it something to assert against without
starting a tmux server.

## P4 — Shell completion §4.1

Bash completion for the verbs, preset names, layout names and session names, plus
a PowerShell `Register-ArgumentCompleter`.

The rewrite traded flags for words, and words complete. This is the biggest
everyday improvement left, and layouts raised it further: `msesh build <tab>` now
has a genuinely useful answer. Below P1–P3 only because it is the largest of the
four and touches nothing that is at risk of breaking.

## P5 — Named windows from a layout §5.2

Windows are `m1`, `m2`, … A layout could name them (`repo`, `logs`), which makes
`prefix+n` navigation mean something once there are more than two.

Worth more than when it was written: the status bar and the tab title now name the
*waiting* window, and `2 m2 !` says less than `2 tests !` would. Small, and it
improves the part of the tool that was just fixed.

---

## P6 — `msesh status` §4.3

Per pane: label, whether its command is still running, how long it has been
silent. The silence figure is what the notifier already computes, so this is
mostly a formatting job. Answers "which of these four is waiting for me" from
outside the session, which the toast and the highlight only answer from inside.

## P7 — `msesh doctor` §4.2

Fold `install.sh --check` into the tool: tmux found, MSYS2 found, Windows Terminal
found, `~/bin` on the Windows `PATH`, presets file readable, layout and manifest
directories writable.

The `PATH` check especially — that exact problem cost three days once, and the
installer only warns at install time. Ranked here rather than higher because the
machine it would have saved is already fixed; its value now is to whoever clones
the repo.

## P8 — `msesh send NAME "text"` §5.1

Type the same thing into every agent pane of a session — a shared prompt, or
`/clear` across the board. tmux `send-keys` in a loop.

Genuinely useful with four agents, and the easiest way in this whole file to make
a mess, so it should require the session name explicitly rather than defaulting to
the current one.

---

## P9 — Implicit build §1.1

`msesh 4 claude` currently errors with `'4' is a spec, not a command — try 'msesh
build 4'`. It could just build: if the first word is not a known command, treat
the whole line as a build.

The cost is that a preset named `list`, `add` or `kill` can then only be reached
as `msesh build list` — and worse, a *typo* that happens to match a preset name
silently builds something instead of being corrected.

Deliberately conditional: do it once the command names have settled and stopped
moving, not before. `layout` was added in 0.5.0, so they have not settled yet.

## P10 — Built-in presets for codex, gemini, aider, copilot §3.2

Cheap, but `msesh preset list` should not fill up with agents that are not
installed. Define them only when the binary is on `PATH`, and say so in the list
output.

Nothing to gain here until one of them is actually installed — none are, on this
machine. Until then `msesh preset make` already offers to define an unknown name,
which covers the first run, and the agent table already knows how to spell their
effort flags whenever a preset does appear.

## P11 — Snapshot a *live* session, not its manifest §2.1

`msesh layout save SESS` copies the manifest, which is what msesh built — not
necessarily what is there now. Panes split by hand in tmux, or a pane whose
command you changed, are not in it. Reading the panes back out of tmux would catch
those.

The hard part is unchanged: once a pane's command has exited and been replaced by
the shell that keeps the pane alive, tmux can only report the label, not the
command. The label *is* the preset name, so it may be enough. Worth doing only if
hand-split sessions turn out to be common.

## P12 — Per-pane settings in a layout §2.3

Today a layout has one working directory for all panes and one effort list spread
across the agent ones. Real sessions may want per-pane directories — three repos,
one pane each.

This needs a spec syntax extension (`claude@high`, `claude:/c/path`) or a richer
layout file that is no longer the same format as a manifest. It is the change most
likely to make the file format something you have to read the manual for, so it is
worth resisting until the need is concrete.

Note the per-pane *effort* half is already covered for the common case: `-e
l,m,h,x` assigns those four in pane order, and panes whose agent has no effort
setting are skipped rather than counted. What is missing is only saying it out of
order, or per directory.

## P13 — `preset try NAME` §2.5

Run a preset in one throwaway pane, attached, to see whether the command works
before wiring it into a four-pane session. Effectively `msesh build NAME -s _try
--ephemeral`, which is short enough already — the value is only in not having to
think of that.

## P14 — `preset copy OLD NEW` / `preset rename OLD NEW` §2.4

Trivial on top of `preset_file_set` and `preset_file_unset`. Mild value; `preset
show OLD` piped into `preset make NEW` almost covers it.

---

## P15 — Short aliases for the verbs §1.2 — recommend against

`msesh b 4`, `msesh a`, `msesh k --all`. One `|` per case arm, and it reintroduces
exactly the memorisation problem the verb rewrite removed, if the short forms
become what you actually type. Keep only `ls` for `list`, which already exists.

## P16 — Preset parameters §2.6 — recommend against

`review = claude /code-review {branch}`, used as `msesh build review:branch=main`.
Powerful, and a genuine step up in complexity: a substitution syntax, quoting
rules, and errors for missing parameters. Probably the wrong direction — a preset
that needs an argument is usually better written as a `!literal command` spec.

---

## Standing notes — not proposals

### §3.1 What the agent table deliberately does not cover

Built in 0.5.0. Two things were left out on purpose:

**Flags other than effort.** The table holds a name, an effort flag and its levels,
nothing else. An agent whose equivalent of `--dangerously-skip-permissions` is
spelled differently still needs a preset. That is the right line: a preset already
says "this command, with these flags", and duplicating it in the table would give
two places to look.

**Anything stateful.** The workspace-trust pre-seed stays Claude-specific and gated
on a Claude pane being present, because it edits `~/.claude.json`. If another agent
ever needs the same treatment it should be its own function beside that one, not a
generic "pre-seed" hook that has to know several file formats.

### §3.3 `MSESH_DEFAULT_PRESET` is already the escape hatch

Someone who lives in codex sets it once and `msesh build 4` means four codex panes.
No code needed — this only wants documenting more loudly.

### §6.3 How to check what tmux actually drew

The status-bar half of the alert highlight never worked for a session with more
than one window, from the day it was written until 0.5.0, because
`window-status-format` is a *window* option and it was being set on the session —
so it landed on whichever window happened to be current, and no other. Nothing
catches that class of bug by reading the code or the tmux docs, and `capture-pane`
sees pane contents only: not borders, not the status bar.

What did catch it: attach the session inside a second, outer tmux server and
`capture-pane` **that**.

```sh
tmux -L outer new-session -d -s cap -x 100 -y 24 'TMUX= tmux attach -t NAME'
tmux -L outer capture-pane -p -t cap        # -e to keep the colour escapes
```

The rendered screen comes back as text, borders and status line included. This is
the way to verify anything visual here, and P3 should use it for the alert path.
