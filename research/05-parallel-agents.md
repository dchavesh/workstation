# Track 5: Many agents at once

**Decision: the machine gives each agent three things, all tested with
stand-in workloads: its own budget, its own working copy, and a session that
outlives the terminal. Real agents have not been run through them yet.**

## Question

The owner runs several agents at the same time on a machine where memory is
the limit (9 GB for WSL). What should the machine provide so that they do not
collide, one cannot starve the others, their work outlives the terminal, and
the owner can see what is running?

## Tested (records in `data/runs/`)

### A budget per agent — `lab/tests/resource-limits.sh`, `parallel-agents.sh`

- The login user can cap one process without root: a 64 MB cap stopped a
  300 MB request, and a 50 % processor cap gave 1.03 s of processor time in
  2 s (2.06 s uncapped).
- Three workloads, each in its own unit capped at 1 GB and two processors,
  ran beside a fourth that asked for 3 GB. All three finished, 9–13 % slower
  than one alone (1.77–1.83 s against 1.62 s). The runaway one did not get
  its memory, and free memory was unchanged afterwards.

### A working copy per agent — `lab/tests/worktrees.sh`

Three git worktrees of one repository with an npm and a Python dependency:

| Measure | Result |
|---------|--------|
| Create a worktree | 7 ms, 1 MB |
| Two agents on the same branch | refused by git |
| `npm ci` in all three at once, shared cache | all succeeded, slowest 1.0 s |
| `uv sync` in all three at once, shared cache | all succeeded, slowest 0.05 s |
| All three commit at the same moment | all succeeded; the repository passes git's integrity check |
| npm dependencies on disk | 31 MB each, 92 MB for three: copied, not shared |
| Python environment on disk | 3 MB for one and 3 MB for all three: shared through hard links |
| Tools in a new worktree | **refused until that worktree's config is approved** |

The last row is a cost of paranoid mode (`02-tools.md`): approval is tied to
a file's contents *and* its path, so every new working copy needs one
`mise trust`. Whoever creates the worktree has to do it. To pass on to
Daedalus.

### A session that outlives the terminal — `lab/tests/agent-sessions.sh`

A stand-in that writes one line per second, started as a user unit with a
memory cap, and a second one inside tmux in a capped unit:

| Situation | Work still running | Distro |
|-----------|--------------------|--------|
| Seen from another terminal | yes; listed by name, with memory, processor time and cap | running |
| 45 s with no terminal attached, linger on | yes, without a break; tmux alive too | running |
| 45 s with no terminal and nothing running | — | **stopped** by WSL |
| 45 s with no terminal, linger **off** | **no**: it wrote 17 lines and died | stopped |

- **Linger is what keeps an agent's work alive.** With it, WSL also keeps the
  distro up while the work runs, and stops it once nothing is left. So
  WSL's 15-second idle limit needs no change, and the proposal to set
  `instanceIdleTimeout=-1` is dropped.
- **Reaching the work again:** the unit shows up under `systemctl --user
  list-units 'agent-*'`; its output is in its file or the journal; a tmux
  session started inside a capped unit can be found and its screen read from
  any other terminal, which is what an interactive agent needs.

## Not tested yet

- **Real agents.** Everything above used stand-ins. Memory per Claude Code
  session was about 300 MB in the owner's diagnostic (5 processes, 1.5 GB).
- **Long waits.** The longest stretch without a terminal was 45 s. Hours,
  and the Windows side going to sleep, are untried.
- **The right caps.** 1 GB and two processors were picked for the test.
- **Sharing npm dependencies.** pnpm links them from one store, as uv does;
  not tried.
- **One command that lists every agent with its use.** The pieces exist
  (above); nothing wraps them yet.

## Boundary

Which agent gets which budget, how agents are started, and who approves a
new working copy is Daedalus's side. This repo supplies the mechanism and
the measurements.
