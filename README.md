# msesh

Multi-session management for [Claude Code](https://claude.ai/code) on Windows. One command opens a tmux session of N panes in a new Windows Terminal tab, each pane running a Claude session, a shell, or anything you name.

```console
$ msesh build 4                        # four Claude panes, tiled, in a new tab
$ msesh build 3 claude +pwsh -s work   # three Claude panes and a shell, named 'work'
$ msesh build 3 claude -e ladder       # panes at low, medium and high effort
$ msesh layout make quad 4 claude -e l,m,h,x   # name that whole session
$ msesh build quad                     # ...and build it, whenever
$ msesh attach work                    # later: back to 'work', rebuilt if it died
```

## What it does

**Persistent.** Sessions outlive the tab. Close the window, run `msesh attach work`, and you are back in the same panes, still running. `msesh rebuild` starts over, `--ephemeral` ties the session's life to the tab.

**Recoverable.** Every build records a manifest, so a session survives a crash or a reboot too — `msesh restore work` rebuilds it exactly as it was. `msesh restore --all` restores every known session at once; point a logon task at it and your working set comes back with the machine.

**Nameable, as a whole.** A preset names one pane; a *layout* names an entire session — how many panes, what each runs, where, at what effort. `msesh layout make quad 4 claude -e l,m,h,x` writes it and `msesh build quad` builds it, today and next month.

**Sized.** Any pane count, not a fixed grid. Panes tile up to four per window, then spill into new tmux windows (`prefix+n` / `prefix+p` to move between them). `-w` changes the threshold, `-w 0` crams everything into one window.

**Noisy, and specific about it.** A pane that stops producing output has usually finished its turn and is waiting on you. msesh wires tmux's silence monitor to a Windows toast — and because a toast is gone in seconds and does not say where to look, it marks the waiting window in three places that stay until you deal with them:

- **the tab** — the Windows Terminal tab title becomes `(!) msesh: work — window 2 waiting`, so an unfocused tab advertises itself
- **the status bar** — the waiting window turns red, with a `!`
- **the block itself** — every pane border in that window turns red and reads `<< WAITING >>`

All three clear the moment you switch to that window. tmux only alerts on windows you are *not* looking at, so the window on screen never nags. `--notify` tunes the threshold, `--no-notify` turns it off, `MSESH_HIGHLIGHT=0` keeps the toast but drops the three markers.

Alerts are raised per *window*, never per pane — a window counts as silent only once every pane in it is — so the window is what gets highlighted. Build with `-w 1` if you would rather have one pane per window, and therefore one alert per pane.

**Reachable from any shell.** `msesh` means the same thing typed into PowerShell, cmd, Windows Terminal, VS Code's terminal, the Run box, Git Bash or MSYS2. tmux only ships with MSYS2, so that is where the work happens; everything else is handed over transparently.

## Requirements

- **MSYS2** with tmux (`pacman -S tmux`). This is the hard requirement — there is no native Windows tmux.
- **Windows Terminal**, to open a tab for you. Without it msesh still builds sessions; use `--no-tab` and attach yourself.
- **Claude Code** on `PATH`, if you want the Claude presets to do anything.

`./install.sh --check` reports on all three without installing.

## Install

```sh
git clone https://github.com/BlueRaddish/msesh
cd msesh
./install.sh                 # copies bin/* into ~/bin
```

From PowerShell or cmd — where `./install.sh` is not something you can run — use the shim next to it, which takes the same arguments:

```powershell
.\install.cmd
.\install.cmd --check
```

Options: `--prefix DIR` to install elsewhere, `--link` to symlink instead of copy so `git pull` updates the installed copy (needs Developer Mode on Windows, falls back to copying), `--uninstall` to remove.

Make sure the prefix is on your `PATH` — the installer warns if it is not. On Windows that means the **User `PATH`** in the registry, not a line in `.bashrc`: PowerShell, cmd and the Run box never read your shell rc, and `msesh` will look broken in exactly those places if you only do the latter.

## Commands

Every command is a word, not a flag. `msesh help` lists them; `msesh help TOPIC` goes deeper.

| Command | |
|---|---|
| `msesh build [SPECS]` | build a session, or attach to it if it is already up |
| `msesh rebuild [SPECS]` | kill this session and build it again from scratch |
| `msesh add [SPECS]` | add panes to a session that is already up |
| `msesh attach [NAME]` | attach to a session, restoring it first if it is down |
| `msesh restore [NAME]` | rebuild a session from its manifest (`--all` for every one) |
| `msesh kill [NAME]` | kill a session and everything in it (`--all` for every one) |
| `msesh forget NAME` | drop a session's manifest so it stops being restored |
| `msesh list` | live sessions, layouts and recorded sessions |
| `msesh preset ...` | name one pane: `list`, `show NAME`, `make [NAME]`, `remove NAME`, `edit` |
| `msesh layout ...` | name a whole session: `list`, `show`, `make`, `save`, `remove`, `edit` |
| `msesh help [TOPIC]` | topics: `specs`, `options`, `preset`, `layout`, `agents`, `files`, `env` |
| `msesh version` | |

## Specs

The arguments to `build`, `rebuild` and `add`, read left to right:

| Spec | Meaning | Example |
|---|---|---|
| `N` | N panes of the default preset | `msesh build 4` |
| `PRESET` | one pane of PRESET | `msesh build claude` |
| `N PRESET` | N panes of PRESET | `msesh build 4 claude` |
| `PRESET:N` | N panes of PRESET | `msesh build claude:2 pwsh:1` |
| `+PRESET` | one more pane (`+` is decoration) | `msesh build 3 claude +pwsh` |
| `!COMMAND` | one pane running COMMAND literally | `msesh build 2 claude '!htop'` |

With no spec you get one pane of the default preset. Specs and options interleave freely, so `msesh build 4 claude -e ladder` and `msesh build -e ladder 4 claude` are the same command.

## Presets

Built in: `claude`, `cly`, `plan`, `safe`, `bash`/`sh`, `pwsh`/`ps`, `cmd`. Your own go in `~/.config/msesh/presets.conf` as `name = command` lines and override the built-ins by name — see [`presets.conf.example`](presets.conf.example), or run `msesh preset list` to see what is currently defined.

A preset whose command runs a known **agent** — `claude`, `codex`, whatever else you have registered — is treated as an agent pane: it gets that agent's effort flag injected when you pass `-e`, and it is what `--lazy` leaves pre-typed instead of started. See [Agents](#agents).

You do not have to edit the file yourself. `msesh preset make` writes it:

```console
$ msesh preset make review "claude --remote-control /code-review"
msesh: preset 'review' = claude --remote-control /code-review
```

Leave anything out and it asks instead:

```console
$ msesh preset make
Name: work
How many panes [1]: 3
  pane 1 — a preset name, or a "literal command" [claude]: claude
  pane 2 — a preset name, or a "literal command" [claude]: codex
    'codex' is not a preset yet.
    command for 'codex' (blank to give up): codex --full-auto
    added preset 'codex' = codex --full-auto
  pane 3 — a preset name, or a "literal command" [claude]: "npm run dev"
Working directory [/c/Users/me/thing]:
Effort for claude panes — blank, 'ladder', or l,m,h: ladder
Max panes per window [4]:
Toast after this many seconds of silence (0 = off) [20]:
msesh: layout 'work' — 3 panes in /c/Users/me/thing
msesh: launch it with 'msesh restore work'
```

Answer a pane with a preset name, or with a `"quoted command"` to run that command as-is. Naming a preset that does not exist offers to write that one too — which is how you add `codex`, `gemini` or `aider` the first time.

**One pane makes a preset**, usable anywhere a preset name is (`msesh build 4 review`). **More than one makes a layout** — which is the next section.

## Layouts

A preset is a name for one pane. A **layout** is a name for a whole session: the pane list, the working directory, the effort ladder, how far panes spill into new windows, how long silence means waiting.

Write one with the same words you would have typed to build it:

```console
$ msesh layout make quad 4 claude -e l,m,h,x
msesh: layout 'quad' — 4 claude in /c/Users/me
msesh: launch it with 'msesh build quad'

$ msesh layout make repo 2 claude +pwsh -d /c/src/thing -w 1 --notify 30
```

Then build it, as often as you like:

```console
$ msesh build quad          # four Claude panes at low, medium, high and xhigh
$ msesh build quad -e x     # the same session, one option overridden
$ msesh build quad -s spike # the same session under another name
```

The layout names the session unless `-s` says otherwise, so `msesh build quad` twice over attaches to the one already up rather than making a second copy. Leave the specs out (`msesh layout make quad`) and it asks instead. Already built the session by hand? `msesh layout save work quad` keeps it.

| | |
|---|---|
| `msesh layout make NAME [SPECS]` | save a session under a name; asks if you leave the specs out |
| `msesh layout save SESS [NAME]` | save a session you already built |
| `msesh layout list` | every layout, with its panes |
| `msesh layout show NAME` | the file behind one |
| `msesh layout remove NAME` | delete one |
| `msesh layout edit NAME` | open it in `$EDITOR` |

Layouts live in `~/.config/msesh/layouts/`, in the same format as the manifests msesh records for itself — but in their own directory, because the two are different things. **A manifest is a recording** of what was running, rewritten by every build. **A layout is a definition**, written only when you ask. That is why building `quad` cannot overwrite `quad`, `msesh add` cannot edit it, and `msesh forget` cannot delete it — only `msesh layout remove` does that.

`msesh build NAME` always uses the layout, because building is what you do when you want the session as designed. `msesh restore NAME` prefers the recording and falls back to the layout, because restoring is what you do when you want back what you had.

A layout is a session, so it is used on its own: `msesh build quad +pwsh` and `msesh build 3 quad` are errors rather than guesses.

## Agents

Two of msesh's behaviours are about a pane holding an interactive coding agent rather than a shell: `-e` injects a reasoning-effort flag, and `--lazy` pre-types the pane instead of running it. Neither is about Claude in particular, so what msesh knows about any given agent is one row of a table:

| Agent | Effort flag | Levels |
|---|---|---|
| `claude` | `--effort ` | low, medium, high, xhigh |
| `codex` | `-c model_reasoning_effort=` | low, medium, high |
| `gemini` | *(none)* | — |
| `aider` | *(none)* | — |

Panes are matched on the command they run, so `review = claude ... /code-review` and `yolo = codex --full-auto` are recognised without being listed. `msesh help agents` prints the table as it currently stands.

An agent with no effort flag is **left out of `-e`** rather than made an error, so a session mixing `gemini` with `claude` still takes a single `-e` and the levels land where they can be used. Asking for a level an agent does not have **is** an error, naming both:

```console
$ msesh build 2 codex -e x
msesh: pane 1 runs codex, which has no 'xhigh' effort — it takes low, medium, high
```

Teach msesh about another one in `~/.config/msesh/agents.conf`, as `name = flag | levels`, where the flag carries its own separator:

```
myagent    = --reasoning | quick,deep
otheragent =                            # no effort setting
```

Genuinely Claude-specific behaviour stays under Claude-specific names: the `claude`, `cly`, `plan` and `safe` presets, `CLAUDE_BIN` / `CLAUDE_FLAGS`, and the workspace-trust pre-seed, which reads and writes `~/.claude.json` and is skipped entirely unless a pane is actually running Claude Code.

## Options

`msesh help options` prints them all. The ones you will reach for:

| | |
|---|---|
| `-s NAME` | session name (default: `msesh`) |
| `-d DIR` | working directory for every pane |
| `-e LIST` | effort levels for agent panes, in pane order — `l`/`m`/`h`/`x`, or `ladder` for low,medium,high; the last repeats for panes left over |
| `-w N` | max panes per window before spilling (default: 4, `0` for one window) |
| `--lazy` | pre-type agent panes' commands without running them |
| `--notify SECS` | toast after this much silence (default: 20, `0` = off) |
| `--no-tab` | build the session without opening a terminal tab |

## Configuration

Everything machine-specific is an environment variable, so msesh should work on a normal install without editing:

| Variable | Purpose |
|---|---|
| `CLAUDE_BIN`, `CLAUDE_FLAGS` | the Claude executable and its default flags |
| `MSESH_BASH`, `MSESH_MSYS_ROOT` | where MSYS2 lives, if it is somewhere unusual |
| `MSESH_PRESETS`, `MSESH_AGENTS` | presets and agents files |
| `MSESH_LAYOUTS`, `MSESH_STATE` | layout directory and manifest directory |
| `MSESH_DEFAULT_PRESET` | what a bare `msesh build 4` launches |
| `TMUX_BIN`, `WT_BIN`, `WT_PROFILE` | tmux and Windows Terminal binaries and profile |
| `MSESH_HIGHLIGHT` | `0` to stop marking a waiting window in the tab title, status bar and pane borders |

`msesh help env` lists the lot.

## A warning about the default flags

The built-in `claude` preset runs with `--dangerously-skip-permissions`, which turns off Claude Code's permission prompts entirely. That is a deliberate choice for a trusted personal machine and a bad one anywhere else. Use the `safe` or `plan` presets, or set `CLAUDE_FLAGS`, if you would rather not.

Note also that msesh pre-seeds Claude Code's workspace-trust record for the working directory so panes do not each stop on a trust dialog. `--no-trust` skips that.

## License

MIT
