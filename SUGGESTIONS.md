# Suggestions

Ideas for msesh that are **not built**, written down so they can be picked or
dropped deliberately. Nothing here is a commitment.

Ordered by what I would build next — value first, cost as the tiebreak — rather
than by topic, so it can be read top to bottom and approved by range ("do P1–P4").
Numbers are positions in that order and will move; the `§` in each heading is the
stable id the PARA doc and commit messages refer to.

Current state for reference: **v1.1.0** — verb-first CLI, presets for one pane
and layouts for a whole session, an agent table behind `-e`, `--dry-run`,
`status`, `send`, `doctor`, tab completion in two shells, a 92-check test
script, and — since v1.0.0 — Linux, macOS, Windows and WSL support proven by CI
on all three.

**Built and removed from this list:** layouts as a first-class thing (§2.2),
saving a session as a layout (§2.1, from its manifest), the agent registry
(§3.1), and — approved and shipped in 0.6.0 — a format version key (§6.1),
`--dry-run` (§5.3), `test.sh` (§6.2), shell completion (§4.1), named windows
(§5.2), `msesh status` (§4.3), `msesh doctor` (§4.2) and `msesh send` (§5.1).

**Shipped since, from the portability plan rather than this list**
(`~/claude/para/1-Projects/msesh/PLAN-portable-msesh-v1.md`): the platform layer
and CI matrix in v1.0.0, and the turn-end hook in v1.1.0 — which retired the
"Claude Code exposes no completion signal" premise that shaped everything up to
v0.6.0. Silence monitoring is now the fallback for panes that are not agents.

## At a glance

| | | Cost | Why here |
|---|---|---|---|
| **P1** | Implicit build §1.1 | tiny | Waiting on the verbs settling — `hooks` moved them again in 1.1.0 |
| **P2** | Built-in presets for other agents §3.2 | small | Nothing to gain until one is installed |
| **P3** | Snapshot a live session §2.1 | medium | Only if hand-split sessions turn out to be common |
| **P4** | Per-pane settings in a layout §2.3 | medium | Resist until the need is concrete |
| **P5** | `preset try NAME` §2.5 | tiny | Already one command; value is not having to think of it |
| **P6** | `preset copy` / `rename` §2.4 | tiny | Mild |
| **P7** | Rendered-screen tests §6.3 | medium | The one bug class the new test script cannot see |
| **P8** | Short verb aliases §1.2 | tiny | Recommend against, beyond the `ls` that exists |
| **P9** | Preset parameters §2.6 | large | Recommend against |

Nothing here is urgent, which is the point: everything that was is built. P1 is
the only one with a trigger rather than a reason — revisit once the command names
have been still for a few weeks. P7 is the one I would actually pick up next if
something needed doing.

---

## P1 — Implicit build §1.1

`msesh 4 claude` currently errors with `'4' is a spec, not a command — try 'msesh
build 4'`. It could just build: if the first word is not a known command, treat
the whole line as a build.

The cost is that a preset named `list`, `add` or `kill` can then only be reached
as `msesh build list` — and worse, a *typo* that happens to match a preset name
silently builds something instead of being corrected.

Deliberately conditional: do it once the command names have settled and stopped
moving, not before. `layout` arrived in 0.5.0, `status`, `send` and `doctor` in
0.6.0, and `hooks` in 1.1.0 — the clock has been reset three times, so this is
further off than when it was written, not closer.

## P2 — Built-in presets for codex, gemini, aider, copilot §3.2

Cheap, but `msesh preset list` should not fill up with agents that are not
installed. Define them only when the binary is on `PATH`, and say so in the list
output.

Nothing to gain here until one of them is actually installed — none are, on this
machine. Until then `msesh preset make` already offers to define an unknown name,
which covers the first run, and the agent table already knows how to spell their
effort flags whenever a preset does appear.

## P3 — Snapshot a *live* session, not its manifest §2.1

`msesh layout save SESS` copies the manifest, which is what msesh built — not
necessarily what is there now. Panes split by hand in tmux, or a pane whose
command you changed, are not in it. Reading the panes back out of tmux would catch
those.

The hard part is unchanged: once a pane's command has exited and been replaced by
the shell that keeps the pane alive, tmux can only report the label, not the
command. The label *is* the preset name, so it may be enough. Worth doing only if
hand-split sessions turn out to be common.

## P4 — Per-pane settings in a layout §2.3

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

## P5 — `preset try NAME` §2.5

Run a preset in one throwaway pane, attached, to see whether the command works
before wiring it into a four-pane session. Effectively `msesh build NAME -s _try
--ephemeral`, which is short enough already — the value is only in not having to
think of that.

## P6 — `preset copy OLD NEW` / `preset rename OLD NEW` §2.4

Trivial on top of `preset_file_set` and `preset_file_unset`. Mild value; `preset
show OLD` piped into `preset make NEW` almost covers it.

## P7 — Tests against the rendered screen §6.3

`test.sh` covers everything that is pure logic, which is most of msesh but not
the part that has actually broken: what tmux draws. The status-bar bug lived
from 0.3.0 to 0.5.0 precisely because no amount of reading the code or the tmux
manual reveals that `window-status-format` is a window option, and
`capture-pane` cannot see a status bar or a pane border.

The method that does work is in the standing note below — attach the session
inside an outer tmux server and capture *that*. Turning it into a test means
accepting a slower suite that starts real sessions and waits out a silence
threshold, which is why it is not in `test.sh` today. Worth doing as a separate
`test-visual.sh` that is not run on every change: build with `-w 1`, wait for
the silence alert, and assert that the alerting window's status entry contains
`!` and its borders contain `WAITING`.

This is the item I would pick up next, on the grounds that it is the only one
here that guards against a bug that has actually happened.

---

## P8 — Short aliases for the verbs §1.2 — recommend against

`msesh b 4`, `msesh a`, `msesh k --all`. One `|` per case arm, and it reintroduces
exactly the memorisation problem the verb rewrite removed, if the short forms
become what you actually type. Keep only `ls` for `list`, which already exists.

## P9 — Preset parameters §2.6 — recommend against

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
