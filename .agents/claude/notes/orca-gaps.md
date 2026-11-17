# orca-gaps

## 2026-10-25

Orca gap: a worker's first worker_done settles its dispatch. A correction pass sent later by terminal cannot send a second worker_done ("No recipient or active Dispatch Run could be resolved"), so the coordinator never hears the result. Workaround until the runtime supports follow-up reports on a settled dispatch: after a terminal-sent correction pass, read the worker's terminal on each wake, or dispatch the correction as a new task.

## 2026-11-17

Orca gap (#1159, cause unconfirmed on a live remote): a remote worker's `worker_done` was rejected with `worker_done references unknown dispatch ctx_...`. Orca's `worker_done` handler checks the task first (`unknown_task`), then `getDispatchContextById` on the server that receives the message (`unknown_dispatch`). The coordinator creates the dispatch, so a remote worker's own server can hold the task but not the dispatch. `--environment <remote>` from the coordinator is refused with `agent_server_route_refused` (use `--on`). No remote environment was available to capture the exact command, and one local `worker_done` capture succeeded because that terminal was local. Workaround: worker-startup.sh now adds a "If worker_done is rejected" note to every remote brief (leave the PR open, stop); the coordinator reads the PR and `worker-show`. Upstream filing needs the owner's go.
