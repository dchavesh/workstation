# Track 5: Many agents at once

**Decision: none yet.** Two building blocks are tested. Everything else on
this page is a question.

## Question

The owner runs several agents at the same time on a machine where memory is
the limit (9 GB for WSL). What should the machine provide so that they do not
collide, one cannot starve the others, their work outlives the terminal, and
the owner can see what is running?

## Tested (2026-11-16, records in `data/runs/`)

| Test | Result |
|------|--------|
| `lab/tests/resource-limits.sh` | The login user can cap one process without root: a 64 MB cap stopped a 300 MB request, and a 50 % processor cap gave 1.03 s of processor time in 2 s (2.06 s uncapped) |
| `lab/tests/parallel-agents.sh` | Three workloads, each in its own unit capped at 1 GB and two processors, beside a fourth that asked for 3 GB: all three finished, 9–13 % slower than one alone (1.77–1.83 s against 1.62 s); the runaway one did not get its memory; free memory was unchanged afterwards |
| `lab/tests/android-emulator.sh` | For scale: one Android emulator takes 3.3 GB, a third of the machine's WSL memory |

What this shows: `systemd-run --user` is enough to give each agent its own
budget, with no extra software and no root. The workloads were stand-ins
(hashing), not real agents.

## Not tested yet

- **Working copies.** One git worktree per agent, and whether tool caches
  (npm, uv) can be shared between them without collisions.
- **Sessions that outlive the terminal.** Linger is on, so a unit started by
  the user keeps running after the last terminal closes. Not yet tried with a
  real agent session, nor how the owner re-attaches to it.
- **Seeing what runs.** One command that lists every agent unit with its
  memory and processor use.
- **How many agents fit.** With real agents, not stand-ins: memory per Claude
  Code session was about 300 MB in the owner's diagnostic (5 processes,
  1.5 GB).
- **What the right caps are.** 1 GB and two processors were picked for the
  test, not measured as good values.

## Boundary

Which agent gets which budget, and how agents are started, is Daedalus's
side. This repo supplies the mechanism and the measurements.
