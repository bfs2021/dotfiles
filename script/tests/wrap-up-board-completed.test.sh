#!/usr/bin/env bash
# wrap-up --scheduled (coordinator) sets a merged-PR worktree still in-review to completed, and leaves an open-PR one alone.
# Real wrap-up.sh and board-done.py; fake orca, gh, per repo wrap-up and board-clean.
# shellcheck source=lib/asdf-pin.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/asdf-pin.sh"
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d); tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state" "$tmp/home" "$tmp/repo/.agents"
: > "$tmp/repo/.agents/head-checks.conf"
cat > "$tmp/bin/orca" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$ORCA_LOG"
case "$*" in
  'status --json') echo '{"ok":true,"result":{"runtime":{"state":"ready","reachable":true}}}' ;;
  'repo list --json') printf '{"ok":true,"result":{"repos":[{"path":"%s","kind":"git"}]}}\n' "$REPO" ;;
  'environment list --json') echo '{"ok":true,"result":{"environments":[]}}' ;;
  'worktree list --json') cat "$FAKE_TREES" ;;
  'orchestration worker-list --limit 100 --json') echo '{"ok":true,"result":{"workers":[]}}' ;;
  'worktree set '*) exit 0 ;;
  *) exit 2 ;;
esac
FAKE
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  'pr list') cat "$FAKE_PRS" ;;
  'issue view') echo '{"state":"OPEN","number":1}' ;;
  *) exit 2 ;;
esac
FAKE
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/wrap-up-child.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/board-clean-stub.sh"
chmod +x "$tmp/bin/orca" "$tmp/bin/gh" "$tmp/wrap-up-child.sh" "$tmp/board-clean-stub.sh"
cat > "$tmp/trees.json" <<'JSON'
{"ok":true,"result":{"truncated":false,"worktrees":[
 {"path":"/w/merged","projectId":"github:acme/app","branch":"refs/heads/feat-merged","workspaceStatus":"in-review"},
 {"path":"/w/open","projectId":"github:acme/app","branch":"refs/heads/feat-open","workspaceStatus":"in-review"}
]}}
JSON
cat > "$tmp/prs.json" <<'JSON'
[{"number":12,"state":"MERGED","headRefName":"feat-merged","closingIssuesReferences":[]},
 {"number":9,"state":"OPEN","headRefName":"feat-open","closingIssuesReferences":[]}]
JSON
printf 'coordinator %s\n' "$(hostname -s)" > "$tmp/coordinator.conf"
log="$tmp/orca.log"; : > "$log"
env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:$(dirname "$(command -v jq)"):$(dirname "$(command -v python3)")" \
  WRAP_UP_STATE_DIR="$tmp/state" WRAP_UP_SCHEDULED_LOG="$tmp/round.log" WRAP_UP_ORCA_APP_BIN="$tmp/noapp" WRAP_UP_EXTRA_BIN= \
  WRAP_UP_SCHEDULED_LOAD_CMD='echo 1' WRAP_UP_SCHEDULED_CORES_CMD='echo 4' WRAP_UP_ISSUE_REPO= \
  WRAP_UP_SCHEDULED_WRAP_UP="$tmp/wrap-up-child.sh" WRAP_UP_BOARD_CLEAN="$tmp/board-clean-stub.sh" \
  BOARD_DONE_COORDINATOR_CONF="$tmp/coordinator.conf" BOARD_DONE_STAMP="$tmp/stamps.json" \
  ORCA_CLI_COMMAND="$tmp/bin/orca" ORCA_LOG="$log" REPO="$tmp/repo" FAKE_TREES="$tmp/trees.json" FAKE_PRS="$tmp/prs.json" \
  bash "$root/script/wrap-up.sh" --scheduled >/dev/null 2>&1

passed=0; failed=0
check() { if "${@:2}"; then printf 'ok %s\n' "$1"; passed=$((passed+1)); else printf 'FAIL %s\n' "$1"; failed=$((failed+1)); fi; }
check 'merged PR worktree in-review is set completed' grep -Fxq 'worktree set --worktree path:/w/merged --workspace-status completed' "$log"
check 'open PR worktree in-review is left alone' bash -c '! grep -Fq "path:/w/open" "$1"' _ "$log"
printf '%s tests passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
