# Working on msesh

## Running several sessions at once

The register of live sessions is **`working.md` at the main worktree root** —
untracked, and it must never reach the remote. Find it from any linked worktree:

```sh
dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
```

Read it before choosing work, add a row when you start, delete the row when you
merge and remove the worktree.

- **One worktree and one branch per session.** Never two sessions in one
  checkout. `git worktree add ../msesh-<topic> -b claude/<topic>`
- **Divide by task, never by folder.** Two sessions touching one file is not an
  error; say what each is doing in the register and let rebase arbitrate.
- **Rebase onto `main` at the start of every work chunk and again before
  merging.** Rebase, never merge, to bring a branch up to date.
- **The main worktree stays parked on `main`, clean.** It is the merge target.
- **`./test.sh` gates every merge.** A branch that cannot pass it does not land.

## Two things specific to this repo

**Install is a copy.** `./install.sh` copies `bin/` into `~/bin`; editing the
clone changes nothing until it runs again. So an install from a feature branch
replaces the command everyone else on this machine is using. **Test from the
clone** (`./bin/msesh`, `./test.sh`) and install only from `main`.

**Cross-platform is a hard requirement, not a goal.** Everything
platform-specific lives in `bin/msesh-platform`; `bin/msesh` and
`bin/msesh-notify` may not name an OS or a platform binary, and `test.sh`
enforces it. bash 3.2 is the floor. CI runs the suite on Linux, macOS and MSYS2.

## Where the rest is written down

- `~/claude/para/1-Projects/msesh/WORKFLOW.md` — everything outstanding, in the
  order it should be done
- `~/claude/para/1-Projects/msesh/PLAN-portable-msesh-v1.md` — the design for
  Phases 0–5
- `~/claude/para/3-Resources/cli-help-design/` — the help protocol help output
  in this repo has to conform to
