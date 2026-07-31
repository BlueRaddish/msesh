# msesh

Multi-session management for [Claude Code](https://claude.ai/code) on Windows. One command opens a tmux session of N panes in a new Windows Terminal tab, each pane running a Claude session, a shell, or anything you name.

```console
$ msesh 4                       # four Claude panes, tiled, in a new tab
$ msesh -s work 3 claude +pwsh  # three Claude panes and a shell, named 'work'
$ msesh -e ladder 3 claude      # panes at low, medium and high effort
$ msesh -s work                 # later: re-attach, or rebuild it if it died
```

## What it does

**Persistent.** Sessions outlive the tab. Close the window and re-run `msesh -s work` and you are back in the same panes, still running. `-F` forces a rebuild, `-E` ties the session's life to the tab.

**Recoverable.** Every build records a manifest, so a session survives a crash or a reboot too — `msesh -r work` rebuilds it exactly as it was. `msesh -R` restores every known session at once; point a logon task at it and your working set comes back with the machine.

**Sized.** Any pane count, not a fixed grid. Panes tile up to four per window, then spill into new tmux windows (`prefix+n` / `prefix+p` to move between them). `-w` changes the threshold, `-1` crams everything into one window.

**Noisy.** A pane that stops producing output has usually finished its turn and is waiting on you. msesh wires tmux's silence monitor to a Windows toast, so you get told — with the pane's label, so you know where to go. tmux only alerts on windows you are *not* looking at, so the pane on screen never nags. `-N` tunes the threshold, `--no-notify` turns it off.

**Reachable from any shell.** `msesh` means the same thing typed into PowerShell, cmd, Windows Terminal, VS Code's terminal, the Run box, Git Bash or MSYS2. tmux only ships with MSYS2, so that is where the work happens; everything else is handed over transparently.

## Requirements

- **MSYS2** with tmux (`pacman -S tmux`). This is the hard requirement — there is no native Windows tmux.
- **Windows Terminal**, to open a tab for you. Without it msesh still builds sessions; use `-n` and attach yourself.
- **Claude Code** on `PATH`, if you want the Claude presets to do anything.

`./install.sh --check` reports on all three without installing.

## Install

```sh
git clone https://github.com/BlueRaddish/msesh
cd msesh
./install.sh                 # copies bin/* into ~/bin
```

Options: `--prefix DIR` to install elsewhere, `--link` to symlink instead of copy so `git pull` updates the installed copy (needs Developer Mode on Windows, falls back to copying), `--uninstall` to remove.

Make sure the prefix is on your `PATH` — the installer warns if it is not.

## Specs

Arguments are read left to right:

| Spec | Meaning | Example |
|---|---|---|
| `N` | N panes of the default preset | `msesh 4` |
| `PRESET` | one pane of PRESET | `msesh claude` |
| `N PRESET` | N panes of PRESET | `msesh 4 claude` |
| `PRESET:N` | N panes of PRESET | `msesh claude:2 pwsh:1` |
| `+PRESET` | one more pane (`+` is decoration) | `msesh 3 claude +pwsh` |
| `!COMMAND` | one pane running COMMAND literally | `msesh 2 claude '!htop'` |

With no spec you get one pane of the default preset.

## Presets

Built in: `claude`, `cly`, `plan`, `safe`, `bash`/`sh`, `pwsh`/`ps`, `cmd`. Your own go in `~/.config/msesh/presets.conf` as `name = command` lines and override the built-ins by name — see [`presets.conf.example`](presets.conf.example), or run `msesh -P` to list what is currently defined.

A preset whose command runs `claude` is treated as a Claude pane: it gets `--effort` injected when you pass `-e`, and it is what `-X` leaves pre-typed instead of started.

## Options

`msesh -h` prints the full manual. The ones you will reach for:

| | |
|---|---|
| `-s NAME` | session name (default: `msesh`) |
| `-d DIR` | working directory for every pane |
| `-e LIST` | effort levels for Claude panes, in pane order — `l`/`m`/`h`/`x`, or `ladder` for low,medium,high |
| `-w N` | max panes per window before spilling (default: 4) |
| `-X` | pre-type Claude panes' commands without running them |
| `-N SECS` | toast after this much silence (default: 20, `0` = off) |
| `-l` | list live sessions and known manifests |
| `-k` / `-K` | kill this session / every msesh session |

## Configuration

Everything machine-specific is an environment variable, so msesh should work on a normal install without editing:

| Variable | Purpose |
|---|---|
| `CLAUDE_BIN`, `CLAUDE_FLAGS` | the Claude executable and its default flags |
| `MSESH_BASH`, `MSESH_MSYS_ROOT` | where MSYS2 lives, if it is somewhere unusual |
| `MSESH_PRESETS`, `MSESH_STATE` | presets file and manifest directory |
| `MSESH_DEFAULT_PRESET` | what a bare `msesh 4` launches |
| `TMUX_BIN`, `WT_BIN`, `WT_PROFILE` | tmux and Windows Terminal binaries and profile |

## A warning about the default flags

The built-in `claude` preset runs with `--dangerously-skip-permissions`, which turns off Claude Code's permission prompts entirely. That is a deliberate choice for a trusted personal machine and a bad one anywhere else. Use the `safe` or `plan` presets, or set `CLAUDE_FLAGS`, if you would rather not.

Note also that msesh pre-seeds Claude Code's workspace-trust record for the working directory so panes do not each stop on a trust dialog. `-T` skips that.

## License

MIT
