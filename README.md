# msesh

Multi-session management for [Claude Code](https://claude.ai/code) and other coding agents. One command opens a tmux session of N panes in a new terminal tab, each pane running an agent, a shell, or anything you name.

Runs on **Linux, macOS and Windows** — tested on all three in CI, including under macOS's stock bash 3.2. **On Windows, use WSL**: msesh prefers it automatically, and the alternative redraws slowly enough to matter. See [Windows: use WSL](#windows-use-wsl).

```console
$ msesh build 4                        # four shells, tiled, in a new tab
$ msesh build 4 claude                 # four Claude panes instead
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

**Noisy, and specific about it.** Run `msesh hooks install` once and a Claude pane reports the end of its turn the moment it happens. Everything else — a build, a test run, a REPL — falls back to tmux's silence monitor: a pane that has printed nothing for a while has usually finished. Either way, because a toast is gone in seconds and does not say where to look, msesh marks the waiting window in three places that stay until you deal with them:

- **the tab** — the terminal tab title becomes `(!) msesh: work — window 2 waiting`, so an unfocused tab advertises itself
- **the status bar** — the waiting window turns red, with a `!`
- **the block itself** — every pane border in that window turns red and reads `<< WAITING >>`

All three clear the moment you switch to that window. tmux only alerts on windows you are *not* looking at, so the window on screen never nags. `--notify` tunes the threshold, `--no-notify` turns it off, `MSESH_HIGHLIGHT=0` keeps the toast but drops the three markers.

Alerts are raised per *window*, never per pane — a window counts as silent only once every pane in it is — so the window is what gets highlighted. Build with `-w 1` if you would rather have one pane per window, and therefore one alert per pane.

**Reachable from any shell.** `msesh` means the same thing typed into bash, zsh, fish, PowerShell, cmd, VS Code's terminal or the Windows Run box. Windows has no tmux of its own, so msesh hands itself over to a runtime that has one — WSL for preference, then MSYS2 or Cygwin.

## Requirements

- **tmux** and **bash**. That is the hard requirement. On Linux and macOS tmux is a package (`apt install tmux`, `brew install tmux`). Windows has none of its own: install [WSL](https://learn.microsoft.com/windows/wsl/install) (`wsl --install -d Ubuntu` from an admin PowerShell, possibly a reboot), then `apt install tmux` **and your agent** inside it — msesh only prefers WSL once both are there, since panes with no agent are worse than a slow session. It then hands itself over from any other shell. [MSYS2](https://www.msys2.org) (`pacman -S tmux`) and Cygwin also work and are used as fallbacks, with the caveat below.
- **A terminal emulator**, if you want msesh to open a window for you. It looks for Windows Terminal, iTerm/Terminal.app, or kitty/alacritty/wezterm/gnome-terminal/konsole and friends. Without one, msesh still builds the session and prints the attach command — which is the right behaviour on a headless box.
- **A notifier**, if you want desktop toasts: `notify-send`, `terminal-notifier`/`osascript`, or Windows toast. Without one, alerts fall back to a tmux message.
- **Claude Code** (or codex, or whatever you put in a preset) on `PATH`, if you want the agent presets to do anything.

Only the first is required; everything else degrades to something useful. `./install.sh --check` and `msesh doctor` both report what this machine actually resolved to.

### Platform support

Everything platform-specific lives in one file, `bin/msesh-platform`, which answers five questions: where tmux is, how to reach a runtime that has it, how to open a terminal, how to raise a notification, and how to spell a path. `bin/msesh` and `bin/msesh-notify` may not name an operating system or a platform binary at all — `./test.sh` enforces that with a grep, and CI runs the suite on Linux, macOS and MSYS2 on every push.

msesh does not branch on OS names to decide what to run. It uses the OS only to *order* a list of candidates, then picks the first that exists — because the OS does not tell you what is installed, and "any platform, any installation" is mostly the second half.

### Windows: use WSL

**On Windows, run msesh under WSL.** It will get there by itself if it can — `plat_bootstrap` prefers WSL whenever WSL has both tmux and the agent — but it is worth understanding why, because the alternative is not a little slower.

A tmux client running under MSYS2 or Cygwin reaches the terminal through **conpty**, Windows' pseudo-console. conpty charges a fixed cost **per `write()` call**, not per byte, and tmux draws by emitting many small screen updates. So tmux pays that toll continuously, while a program like `cat` — which writes in a few large blocks — does not. Measured on one machine, same terminal, same 4-pane session, same 40,000 lines of output:

| runtime | time |
|---|---|
| WSL2 | **0.13 s** |
| MSYS2, best available workaround | 164 s |
| MSYS2, plain | 679 s |

The same effect is what makes scrolling and agent output feel sluggish long before you notice it on a bulk dump. It is not tmux's fault and it is not fixable from inside msesh: the identical tmux binary is fast the moment conpty is out of the path.

**If you cannot use WSL**, msesh still works — it falls back to MSYS2, then Cygwin, and `msesh doctor` will say so under `rendering`. Expect heavy output to redraw slowly. Some of it can be clawed back by wrapping the client in a relay that batches writes (`script -qc 'tmux attach -t NAME' /dev/null` is the zero-install version), but nothing on this path approaches WSL.

**Two things to know about the WSL path.** A session built under WSL lives on a tmux server *inside* the distro, so sessions you created under MSYS2 are not visible to it and vice versa — they are separate servers, not a shared one. And your Windows files are reachable at `/mnt/c/...`, which is fine for editing and building; only tree-walking operations like `git status` are meaningfully slower there.

`MSESH_RUNTIME=msys2` (or `cygwin`) pins the old behaviour if you want it.

## Install

```sh
git clone https://github.com/BlueRaddish/msesh
cd msesh
./install.sh                 # copies bin/* into ~/bin
```

On Windows, from PowerShell or cmd — where `./install.sh` is not something you can run — use the shim next to it, which takes the same arguments:

```powershell
.\install.cmd
.\install.cmd --check
```

Options: `--prefix DIR` to install elsewhere, `--link` to symlink instead of copy so `git pull` updates the installed copy (needs Developer Mode on Windows, falls back to copying), `--uninstall` to remove.

Make sure the prefix is on your `PATH` — the installer warns if it is not, and tells you the right way to fix it for the platform you are on. Those differ: on Unix a line in your shell rc is the answer, and on Windows it is the **User `PATH`** in the registry, because PowerShell, cmd and the Run box never read a shell rc. Getting that backwards on Windows makes msesh work in bash and look broken everywhere else.

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
| `msesh status [NAME]` | what each pane is doing, and which window is waiting |
| `msesh send NAME TEXT` | type TEXT into every agent pane of NAME (`--all` for every pane) |
| `msesh snapshot [NAME]` | record a live session, conversations and all |
| `msesh hooks [SUB]` | `status`, `install` or `remove` the agent hooks |
| `msesh doctor` | check this machine: platform, tmux, terminal, notifier, PATH, files |
| `msesh preset ...` | name one pane: `list`, `show NAME`, `make [NAME]`, `remove NAME`, `edit` |
| `msesh layout ...` | name a whole session: `list`, `show`, `make`, `save`, `remove`, `edit` |
| `msesh help [TOPIC]` | topics: `specs`, `options`, `preset`, `layout`, `agents`, `hooks`, `resume`, `files`, `env` |
| `msesh version` | |

## Specs

The arguments to `build`, `rebuild` and `add`, read left to right:

| Spec | Meaning | Example |
|---|---|---|
| `N` | N panes of the default preset (a plain shell) | `msesh build 4` |
| `PRESET` | one pane of PRESET | `msesh build claude` |
| `N PRESET` | N panes of PRESET | `msesh build 4 claude` |
| `PRESET:N` | N panes of PRESET | `msesh build claude:2 pwsh:1` |
| `+PRESET` | one more pane (`+` is decoration) | `msesh build 3 claude +pwsh` |
| `!COMMAND` | one pane running COMMAND literally | `msesh build 2 claude '!htop'` |

With no spec you get one pane of the default preset, which is a plain shell — ask for agents by name. `MSESH_DEFAULT_PRESET` changes that if you would rather `msesh build 4` meant four Claude panes. Specs and options interleave freely, so `msesh build 4 claude -e ladder` and `msesh build -e ladder 4 claude` are the same command.

## Presets

Built in, in the order `msesh preset list` shows them: `shell` (your shell), then the shells this machine has (`bash`, `sh`, `zsh`, `fish`, `pwsh`, `cmd` — whichever exist), then the agents that are installed (`claude`, `codex`, `gemini`, `aider`). Agents come last because they are the specialised end of the list, not the front of it. Your own go in `~/.config/msesh/presets.conf` as `name = command` lines and override the built-ins by name — see [`presets.conf.example`](presets.conf.example), or run `msesh preset list` to see what is currently defined.

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
| `--windows LIST` | name the windows this build creates, in order — `repo,logs`; names run out silently |
| `-n`, `--dry-run` | print the panes, commands and window split, then stop |
| `--notify SECS` | toast after this much silence (default: 20, `0` = off) |
| `--no-tab` | build the session without opening a terminal tab |

## Knowing when an agent has finished

By default msesh infers "this pane is waiting on you" from silence: a pane that has printed nothing for 20 seconds has, in practice, finished its turn. That is a guess, and it is late by the length of the timeout and wrong in both directions — an agent thinking quietly looks finished, and one printing steadily never alerts.

Claude Code will simply tell you instead. `msesh hooks install` adds a `Stop` hook to `~/.claude/settings.json`, and from then on a pane reports the end of its turn the moment it happens:

```console
$ msesh hooks status
settings:  /home/me/.claude/settings.json
Stop hooks:  2 total, 1 msesh, 1 yours
  msesh -> "/home/me/bin/msesh-notify" --turn-end

$ msesh status work
work:
  window 2 (review)
    1  claude/high            WAITING — turn ended
```

Silence monitoring stays as the fallback for panes that are not agents — a build, a test run, a REPL — where it was always the right signal.

**That file is not msesh's**, and it commonly holds hooks you wrote. So `hooks install` is **append-only** (it never rewrites, reorders or drops an entry it did not create), every entry it writes is tagged `"_msesh": 1` so `hooks remove` takes exactly its own, it backs the file up to `settings.json.msesh-backup` first, it validates the JSON before replacing anything, and running it twice changes nothing the second time. `hooks status` is read-only and `--dry-run` prints the result without writing. An install followed by a remove leaves the file byte-identical, line endings included.

`hooks install` adds two hooks, together: `Stop` is the turn-end signal above, and `SessionStart` records which conversation each pane holds — which is what the next section restores from.

## Coming back to the conversation, not just the panes

`msesh restore work` rebuilds the shape of a session: the right panes, running the right commands, in the right windows. The agents in them are brand new and remember nothing.

```sh
msesh restore work --resume
```

brings each pane back to the conversation it was in, in the directory it was in, at the size it was.

This needs `msesh hooks install` — the conversation ids come from the `SessionStart` hook, and without it there is nothing recorded to come back to.

**A snapshot is a manifest with a timestamp.** Not a third concept: same format, same reader, so `msesh list` still shows two sections and everything that reads a manifest reads a snapshot for free. One is taken automatically on `msesh kill`, which is how a session normally ends and the last moment its conversations can be read; `msesh snapshot NAME` takes one on demand.

Panes are matched to the snapshot **by position**, because position is the only identity a pane has across a kill. A pane whose conversation was never recorded — one you never pressed Enter in, say — starts fresh. **Three resumed and one new is a normal restore, not a failure.** Resumed panes are marked with a trailing `~`:

```
  window m1
    claude~                claude --resume 0bfc5eb6-6653-44ba-bac5-2b1fa5c75930
    claude~                claude --resume 3a91c204-11de-4c7a-9f02-7b6e5d0a1c88
    claude                 claude
  2 pane(s) would resume a conversation, 1 would start fresh
```

Snapshots are kept per machine — a conversation id and an absolute path mean nothing on another one. Everything from the last week is kept, then one a day for two months, then nothing.

Only an agent that can be reopened *by id* takes part. `claude` can; `codex` resumes by recency, which is a different thing msesh cannot record, so it starts fresh rather than pretending. Add one in `agents.conf` with a third field: `myagent = --reasoning | quick,deep | --continue`.

## Checking before you build

`--dry-run` resolves the whole command — specs, presets, the agent table, effort assignment, the window split — and prints it instead of building it. Nothing starts, no manifest is written.

```console
$ msesh build quad -n
msesh: would build 'quad' — 4 pane(s) in /c/Users/me
  window m1
    claude/low             claude --remote-control --effort low
    claude/medium          claude --remote-control --effort medium
    claude/high            claude --remote-control --effort high
    claude/xhigh           claude --remote-control --effort xhigh
  1 window(s), 4 pane(s) per window, toast after 20s of silence
msesh: nothing was built (--dry-run)
```

Once it is running, `msesh status` answers the same question from the other side — from any shell, without attaching:

```console
$ msesh status
work:
  window 1 (repo) — waiting
    1  claude/high            finished — shell only
    2  claude/low             running
  window 2 (logs)
    1  npm                    running
```

"Waiting" is per window, because tmux's silence flag is: a window counts as silent only once every pane in it is. Whether a *pane* has finished is recorded by the pane itself as its command exits — tmux can only report the wrapper shell, so asking it from outside cannot tell a working pane from a finished one.

`msesh doctor` checks the machine rather than the session: which platform it resolved to, tmux, which terminal and notifier it will use, whether the turn-end hook is installed, whether the install directory is really on `PATH` (checked the way that platform means it — a shell rc on Unix, the User `PATH` in the registry on Windows), whether the installed copy has drifted from your clone, and whether the config files and directories are readable and writable.

## Talking to every pane at once

```console
$ msesh send work "/clear"
msesh: sent to 3 pane(s) in 'work' — claude/low, claude/medium, claude/high
msesh: skipped 1 non-agent pane(s)
```

Agent panes only by default — a shared prompt does not belong in a shell — with `--all` to include everything and `--no-enter` to leave the line typed but not submitted. The session must be named explicitly: there is no default, because typing into the wrong four agents at once is the mistake worth designing out.

## Tab completion

```console
$ msesh la<TAB>              → msesh layout
$ msesh build cl<TAB>        → msesh build claude-quad
$ msesh layout <TAB>         → list  make  save  show  remove  edit
```

`completion/msesh.bash` and `completion/msesh.ps1` are sourced from the clone rather than copied, so `git pull` keeps them current. `./install.sh` prints the one line to add to `~/.bashrc` or `$PROFILE` — it will not edit either for you.

Both ask `msesh complete-names KIND`, which prints one name per line and nothing else, so the human-readable listings stay free to change.

## Tests

`./test.sh` — 173 checks over spec resolution, effort against the agent table, layout resolution, the preset file rewrite, the manifest round-trip, the portability invariants, and whether the help still describes the tool. Everything goes through `--dry-run`, so no tmux session is ever built. `-v` lists each check.

The run is dominated by process startup, so it is quick on Linux and macOS and slow where spawning is expensive — on Windows under MSYS2, expect around four minutes rather than the couple of seconds it takes elsewhere.

CI runs the same suite on Linux, macOS and MSYS2 on every push — the macOS job deliberately uses `/bin/bash`, which is bash 3.2, because that is the bash a Mac user actually has.

## Configuration

Everything machine-specific is an environment variable, so msesh should work on a normal install without editing:

| Variable | Purpose |
|---|---|
| `CLAUDE_BIN`, `CLAUDE_FLAGS` | the Claude executable and its default flags |
| `MSESH_OS` | override platform detection (`linux`, `macos`, `windows`, `wsl`) |
| `MSESH_RUNTIME` | Windows: which runtime to hand over to — `msys2` or `cygwin` to stop preferring WSL |
| `MSESH_AGENT_BIN` | the agent looked for when deciding whether WSL can host a session (default: `claude`) |
| `MSESH_TERMINAL`, `TERMINAL` | the terminal to open a session in, tried before the search |
| `MSESH_NOTIFY_CMD` | a command taking TITLE BODY, tried before the search |
| `MSESH_MSYS_ROOT` | Windows: where MSYS2 lives, if it is somewhere unusual |
| `MSESH_PRESETS`, `MSESH_AGENTS` | presets and agents files |
| `MSESH_LAYOUTS`, `MSESH_STATE` | layout directory and manifest directory |
| `MSESH_DEFAULT_PRESET` | what a bare `msesh build 4` launches (default: `shell`) |
| `TMUX_BIN` | tmux, if it is not where the search would find it |
| `WT_BIN`, `WT_PROFILE` | Windows: Terminal binary and the profile a tab uses |
| `CLAUDE_SETTINGS` | Claude Code's settings.json, for `msesh hooks` |
| `MSESH_HIGHLIGHT` | `0` to stop marking a waiting window in the tab title, status bar and pane borders |

`msesh help env` lists the lot.

## A note on flags

Every built-in preset is the **bare command** — `claude` runs `claude`, nothing more. An earlier version added `--dangerously-skip-permissions` to the `claude` preset, which meant msesh turned off permission prompts without saying so. Flags are yours to add:

```
claude = claude --permission-mode plan
yolo   = claude --dangerously-skip-permissions
review = claude /code-review
```

`CLAUDE_FLAGS` appends to the built-in `claude` preset if you would rather set it once in your environment.

msesh still pre-seeds Claude Code's workspace-trust record for the working directory so panes do not each stop on a trust dialog. `--no-trust` skips that.

## License

MIT
