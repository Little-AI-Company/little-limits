#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NOTE_FREE_SCOPES=" release website ci test repo "
SWIFT_PATHS='^(Sources/|Tests/|Resources/|scripts/|Package\.(swift|resolved)$)'
REPO_URL="https://github.com/Little-AI-Company/little-limits.git"
M4_HOST="${PUSH_MAIN_M4:-m4}"
M4_CHECKOUT='$HOME/Developer/little-limits-push'
RETRIES=10
CAP="${PUSH_MAIN_CHECK_TIMEOUT:-600}"
GRACE="${PUSH_MAIN_REMOTE_GRACE:-30}"

usage() {
  cat >&2 <<'USAGE'
  scripts/push_main.sh [--package] [--squash "<subject>"] [--no-swift "<why>"]
  scripts/push_main.sh --revert <sha> [--reason "<text>"]
  scripts/push_main.sh --verify [--package]     # check HEAD, push nothing
  scripts/push_main.sh --skip-checks "<why>"    # push without running any check
USAGE
  exit 1
}
say() { echo "push-main: $*" >&2; }
[[ "$CAP" =~ ^[1-9][0-9]*$ ]] && [[ "$GRACE" =~ ^[0-9]+$ ]] || {
  say "PUSH_MAIN_CHECK_TIMEOUT must be a number of seconds"
  exit 1
}
cap_label() {
  if [ $((CAP % 60)) -eq 0 ]; then echo "$((CAP / 60))m"; else echo "${CAP}s"; fi
}
finish() {
  local code="$1"
  shift
  echo "PUSH: $*"
  exit "$code"
}

package=0
verify=0
squash=""
no_swift=""
revert=""
reason=""
skip_why=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-checks)
      [ $# -ge 2 ] && [[ "$2" =~ [^[:space:]] ]] || {
        say '--skip-checks needs a reason: --skip-checks "<why>"'
        usage
      }
      case "$2" in *$'\n'* | *$'\r'*) say "the --skip-checks reason is one line" && usage ;; esac
      skip_why="$2"
      shift
      ;;
    --squash | --no-swift | --revert | --reason)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --squash) squash="$2" ;;
        --no-swift) no_swift="$2" ;;
        --revert) revert="$2" ;;
        --reason) reason="$2" ;;
      esac
      shift
      ;;
    --package) package=1 ;;
    --verify) verify=1 ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
  shift
done
[ -z "$revert" ] || [ -z "$squash" ] || usage
[ "$verify" -eq 0 ] || [ -z "$revert$squash" ] || usage

tmp="$(mktemp -d "${TMPDIR:-/tmp}/push-main.XXXXXX")"
CAPPED_PID=""
cleanup() {
  [ -z "$CAPPED_PID" ] || kill -TERM -- "-$CAPPED_PID" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[ -z "$(git status --porcelain)" ] || finish 5 "dirty - : commit or stash first"
git fetch --quiet origin main || finish 1 "fetch-failed - : git fetch origin main"

tree12() { git rev-parse "HEAD^{tree}" | cut -c1-12; }
trailer() { git log -1 --format="%(trailers:key=$1,valueonly,unfold)" HEAD | sed '/^$/d'; }

rewrite_trailers() {
  local drop="$1" args=() t
  shift
  for t in "$@"; do args+=(--trailer "$t"); done
  if [ -n "$drop" ]; then
    git log -1 --format=%B | sed -E "/^($drop): /d"
  else
    git log -1 --format=%B
  fi | git interpret-trailers --if-exists add "${args[@]}" >"$tmp/msg"
  git commit --quiet --amend --no-verify -F "$tmp/msg"
}

if [ -n "$revert" ]; then
  target="$(git rev-parse --verify --quiet "$revert^{commit}")" || finish 1 "usage - : $revert is not a commit"
  git merge-base --is-ancestor "$target" origin/main ||
    finish 5 "not-on-main $target : only a commit on main can be reverted"
  git switch --quiet --detach origin/main
  git revert --no-edit "$target" >/dev/null || {
    git revert --abort >/dev/null 2>&1 || true
    finish 3 "conflict $target : the revert does not apply on origin/main"
  }
  rewrite_trailers "" "Customer-note: none (reverts ${target:0:12}${reason:+: $reason})"
  say "reverted ${target:0:12} as $(git rev-parse --short=12 HEAD)"
fi

count="$(git rev-list --count origin/main..HEAD)"
[ "$count" -ge 1 ] || finish 5 "nothing - : HEAD has no commit that origin/main lacks"
if [ "$count" -gt 1 ] && [ "$verify" -eq 0 ]; then
  [ -n "$squash" ] || finish 5 "commits=$count - : one change per push; pass --squash \"<subject>\""
  base="$(git merge-base HEAD origin/main)"
  {
    printf '%s\n\n' "$squash"
    git log --reverse --format='- %s' "$base..HEAD"
    echo
    git log --reverse --format='%(trailers:only,unfold)' "$base..HEAD" | sed -E '/^$/d;/^Tested: /d' | awk '!seen[$0]++'
  } >"$tmp/squash-msg"
  git reset --quiet --soft "$base"
  git commit --quiet --no-verify -F "$tmp/squash-msg"
  say "squashed $count commits into $(git rev-parse --short=12 HEAD)"
fi

rebase() {
  [ "$(git merge-base HEAD origin/main)" != "$(git rev-parse origin/main)" ] || return 0
  if ! git rebase --quiet origin/main >/dev/null 2>&1; then
    git rebase --abort >/dev/null 2>&1 || true
    finish 3 "conflict $(git rev-parse HEAD) : rebase onto origin/main by hand, then run this again"
  fi
}
[ "$verify" -eq 1 ] || rebase

subject="$(git log -1 --format=%s)"
if [[ "$subject" =~ ^(feat|fix|perf)(\(([^\)]*)\))?!?: ]]; then
  scope="${BASH_REMATCH[3]}"
  if [[ "$NOTE_FREE_SCOPES" != *" $scope "* ]] && [ -z "$(trailer Customer-note)" ]; then
    if git log -1 --format=%B | grep -q '^Customer-note:'; then
      finish 5 "no-customer-note $(git rev-parse HEAD) : the Customer-note: line is not in the last paragraph, so it is not a trailer"
    fi
    finish 5 "no-customer-note $(git rev-parse HEAD) : add 'Customer-note: <one or two sentences>' or 'Customer-note: none (<reason>)' as a trailer"
  fi
fi

remote_script() {
  cat <<EOF
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
dir="$M4_CHECKOUT"
bundle="\$(mktemp)"
cat >"\$bundle"
trap 'rm -f "\$bundle"' EXIT
work() {
  lock="\$dir.lock"
  for _ in \$(seq 360); do
    if mkdir "\$lock" 2>/dev/null; then echo \$\$ >"\$lock/pid"; break; fi
    kill -0 "\$(cat "\$lock/pid" 2>/dev/null || echo 0)" 2>/dev/null || rm -rf "\$lock"
    sleep 5
  done
  [ -d "\$lock" ] && [ "\$(cat "\$lock/pid" 2>/dev/null)" = \$\$ ] || { echo "the checkout stayed locked for 30 minutes" >&2; exit 1; }
  trap 'rm -rf "\$lock"' EXIT
  [ -d "\$dir/.git" ] || git clone -q $REPO_URL "\$dir"
  cd "\$dir"
  git fetch -q origin main
  git fetch -q "\$bundle" HEAD
  git checkout -q --force --detach FETCH_HEAD
  git clean -fdq
  echo "TREE \$(git rev-parse HEAD^{tree})"
  echo "HOSTINFO m4, macOS \$(sw_vers -productVersion), \$(xcodebuild -version | head -1)"
  swift test
  if [ "\${PACKAGE:-0}" = 1 ]; then
    scripts/package_app.sh
    codesign --verify --strict --verbose=2 "dist/Little Limits.app"
  fi
}
set -m
work &
wp=\$!
set +m
(
  start=\$SECONDS
  while kill -0 "\$wp" 2>/dev/null; do
    if [ \$((SECONDS - start)) -ge \$((\${CAP:-600} + $GRACE)) ]; then
      kill -TERM -- "-\$wp" 2>/dev/null
      sleep 3
      kill -KILL -- "-\$wp" 2>/dev/null
      break
    fi
    sleep 2
  done
) >/dev/null 2>&1 &
wd=\$!
rc=0
wait "\$wp" || rc=\$?
kill "\$wd" 2>/dev/null || true
[ "\$rc" -lt 128 ] || rc=124
exit "\$rc"
EOF
}

TIMED_OUT=0
capped() {
  local log="$1" rc=0 start
  shift
  TIMED_OUT=0
  set -m
  "$@" >"$log" 2>&1 &
  CAPPED_PID=$!
  set +m
  start=$SECONDS
  while kill -0 "$CAPPED_PID" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$CAP" ]; then
      TIMED_OUT=1
      kill -TERM -- "-$CAPPED_PID" 2>/dev/null || true
      sleep 2
      kill -KILL -- "-$CAPPED_PID" 2>/dev/null || true
      break
    fi
    sleep 1
  done
  wait "$CAPPED_PID" 2>/dev/null || rc=$?
  CAPPED_PID=""
  return "$rc"
}

local_mac_run() {
  swift test &&
    if [ "$package" -eq 1 ]; then
      scripts/package_app.sh && codesign --verify --strict --verbose=2 "dist/Little Limits.app"
    fi
}

m4_run() {
  ssh -o BatchMode=yes "$M4_HOST" \
    "f=\$(mktemp); echo $(base64 <"$tmp/remote.sh" | tr -d '\n') | base64 -d >\"\$f\"; PACKAGE=$package CAP=$CAP bash \"\$f\"; rc=\$?; rm -f \"\$f\"; exit \$rc" \
    <"$tmp/head.bundle"
}

run_checks() {
  local tree start code where log="$tmp/swift.log"
  tree="$(tree12)"
  TESTED=()
  STATE=pass
  if [ -n "$skip_why" ]; then
    say "skipping every check: $skip_why"
    TESTED+=("Tested: skipped: $skip_why")
    return 0
  fi
  if git diff --check origin/main HEAD >"$tmp/diffcheck.log" 2>&1; then
    TESTED+=("Tested: git diff --check pass tree $tree")
  else
    TESTED+=("Tested: git diff --check fail tree $tree")
    STATE=fail
    cat "$tmp/diffcheck.log" >&2
  fi

  if ! git diff --name-only origin/main HEAD | grep -Eq "$SWIFT_PATHS"; then
    [ "$package" -eq 0 ] || say "--package: nothing the app is built from changed; not packaging"
    return 0
  fi
  [ "$STATE" = pass ] || return 0

  start="$(date +%s)"
  code=0
  if [ "$(uname -s)" = Darwin ] && command -v swift >/dev/null 2>&1; then
    where="here, macOS $(sw_vers -productVersion), $(xcodebuild -version 2>/dev/null | head -1)"
    say "running swift test here"
    capped "$log" local_mac_run || code=$?
  elif ssh -o BatchMode=yes -o ConnectTimeout=10 "$M4_HOST" true >/dev/null 2>&1; then
    say "running swift test on the M4 ($M4_HOST)"
    git bundle create --quiet "$tmp/head.bundle" HEAD ^origin/main
    remote_script >"$tmp/remote.sh"
    capped "$log" m4_run || code=$?
    where="$(sed -n 's/^HOSTINFO //p' "$log" | head -1)"
    local remote_tree
    remote_tree="$(sed -n 's/^TREE //p' "$log" | head -1)"
    if [ "$code" -eq 0 ] && [ "${remote_tree:0:12}" != "$tree" ]; then
      say "the M4 tested tree ${remote_tree:0:12}, not $tree"
      code=1
    fi
  elif command -v swift >/dev/null 2>&1; then
    where="here, Linux: UsageHistory only"
    say "running swift test here (Linux builds only UsageHistory)"
    capped "$log" swift test || code=$?
  elif [ -n "$no_swift" ]; then
    TESTED+=("Tested: swift test not-run ($no_swift) tree $tree")
    say "swift test not run: $no_swift"
    return 0
  else
    finish 5 "no-swift $(git rev-parse HEAD) : no Swift here and no ssh $M4_HOST; run little-worker's scripts/m4-ssh-setup.sh, or pass --no-swift \"<why>\""
  fi

  local label="swift test"
  [ "$package" -eq 0 ] || label="swift test + package"
  [ "$TIMED_OUT" -eq 0 ] || code=124
  if [ "$code" -eq 124 ]; then
    TESTED+=("Tested: $label timed out after $(cap_label)")
    tail -10 "$log" >&2 || true
    say "WARNING: $label ran past $(cap_label) and was stopped; pushing anyway, and the Tested: trailer says so"
  elif [ "$code" -eq 0 ]; then
    TESTED+=("Tested: $label pass (${where:-unknown host}, $(($(date +%s) - start))s) tree $tree")
  else
    TESTED+=("Tested: $label fail (${where:-unknown host}, exit $code) tree $tree")
    STATE=fail
    tail -40 "$log" >&2
  fi
}

if [ "$verify" -eq 1 ]; then
  run_checks
  printf '%s\n' "${TESTED[@]}" >&2
  [ "$STATE" = pass ] || finish 2 "red $(git rev-parse HEAD)"
  finish 0 "verified $(git rev-parse HEAD)"
fi

for ((try = 1; try <= RETRIES; try++)); do
  run_checks
  [ "$STATE" = pass ] || finish 2 "red $(git rev-parse HEAD)"
  rewrite_trailers "Tested" "${TESTED[@]}"
  sha="$(git rev-parse HEAD)"
  if out="$(git push --porcelain origin "$sha:refs/heads/main" 2>&1)"; then
    say "pushed $sha to main; GitHub Actions now runs the full build on it"
    finish 0 "pushed $sha"
  fi
  printf '%s\n' "$out" >&2
  case "$out" in
    *"non-fast-forward"* | *"fetch first"*) ;;
    *) finish 1 "push-refused $sha" ;;
  esac
  say "main moved (try $try of $RETRIES); fetching, rebasing and checking again"
  git fetch --quiet origin main || finish 1 "fetch-failed $sha"
  rebase
done
finish 4 "raced $(git rev-parse HEAD) : main moved $RETRIES times"
