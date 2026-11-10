#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CONF="${PUSH_MAIN_CONF:-$ROOT/scripts/push_main.conf}"
CAP="${PUSH_MAIN_CHECK_TIMEOUT:-600}"
POLL="${PUSH_MAIN_POLL:-15}"
RETRIES=10
M4_HOST="${PUSH_MAIN_M4:-m4}"

say() { echo "push-main: $*" >&2; }
finish() {
  local code="$1"
  shift
  echo "PUSH: $*"
  exit "$code"
}
usage() {
  cat >&2 <<'USAGE'
Check the commits ahead of origin/main and fast-forward main with them.
The repository's check is in scripts/push_main.conf; this script is the same
in every small repository and is written in little-worker-hq.

  scripts/push_main.sh                         check HEAD and push
  scripts/push_main.sh --package               also run the conf's PACKAGE step
  scripts/push_main.sh --skip-checks "<why>"   push without the check; the reason goes in Tested:
  scripts/push_main.sh --revert <sha> [--reason "<why>"]   revert a commit on main and push that
  scripts/push_main.sh --verify                check HEAD, change and push nothing (also --dry-run)

The last line on standard output is "PUSH: <state> <sha>". Exit codes:
  0 pushed or checked   1 usage or git error   2 the check failed, main unchanged
  3 rebase conflict     4 main moved 10 times  5 not pushable (dirty, nothing,
  a missing Customer-note:, a new code comment, a kill, a secret, no Mac to check on)
USAGE
  exit 1
}

revert=""
reason=""
skip=""
skip_flag=0
verify=0
package=0
while [ $# -gt 0 ]; do
  case "$1" in
    --revert | --reason)
      [ $# -ge 2 ] && [[ "$2" =~ [^[:space:]] ]] || usage
      case "$1" in
        --revert) revert="$2" ;;
        --reason) reason="$(printf '%s' "$2" | tr '\n\r' '  ')" ;;
      esac
      shift
      ;;
    --skip-checks)
      skip_flag=1
      if [ $# -ge 2 ] && [[ "$2" != --* ]] && [[ "$2" =~ [^[:space:]] ]]; then
        skip="$(printf '%s' "$2" | tr '\n\r' '  ')"
        shift
      fi
      ;;
    --verify | --dry-run) verify=1 ;;
    --package) package=1 ;;
    *) usage ;;
  esac
  shift
done
[ -z "$reason" ] || [ -n "$revert" ] || usage
[ "$skip_flag" -eq 0 ] || [ -n "$skip" ] || [ -n "$revert" ] || usage
[ -z "$revert" ] || [ "$verify" -eq 0 ] || usage
[[ "$CAP" =~ ^[1-9][0-9]*$ ]] && [[ "$POLL" =~ ^[1-9][0-9]*$ ]] || usage

CHECK=""
CHECK_LABEL=""
CHECK_ON=here
CHECK_PATHS=""
PACKAGE=""
NOTE_FREE_SCOPES=""
COMMENT_SCAN=""
COMMENT_SKIP='^(node_modules|vendor)/'
KILL_FILES='\.(md|mdx|markdown|txt|ya?ml)$'
KILL_SKIP='(^|/)(node_modules|vendor|fixtures)/'
NOTICES=()
M4_DIR=""
CLONE_URL=""
[ -f "$CONF" ] || finish 1 "no-conf - : $CONF is missing; it sets CHECK"
. "$CONF"
CHECK="${PUSH_MAIN_CHECK:-$CHECK}"
[ -n "$CHECK" ] || finish 1 "no-conf - : $CONF sets no CHECK"
CHECK_LABEL="${CHECK_LABEL:-$CHECK}"
M4_DIR="${M4_DIR:-/Volumes/Claude/$(basename "$ROOT")-push}"
origin_url="$(git remote get-url origin)"
origin_url="${origin_url%.git}"
origin_url="${origin_url//://}"
CLONE_URL="${CLONE_URL:-https://github.com/$(basename "$(dirname "$origin_url")")/$(basename "$origin_url").git}"

cd "$ROOT"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/push-main.XXXXXX")"
CAPPED_PID=""
WATCHDOG_PID=""
cleanup() {
  [ -z "$CAPPED_PID" ] || kill -TERM -- "-$CAPPED_PID" 2>/dev/null || true
  [ -z "$WATCHDOG_PID" ] || kill -KILL -- "-$WATCHDOG_PID" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[ -z "$(git status --porcelain)" ] || finish 5 "dirty - : commit or stash first"
git fetch --quiet origin main || finish 1 "fetch-failed - : git fetch origin main"

trailer() { git log -1 --format="%(trailers:key=$2,valueonly,unfold)" "$1" | sed '/^$/d'; }
json_text() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
beat_items() {
  local token="${HQ_ACCOUNT_TOKEN:-${WIKI_AGENT_TOKEN:-}}" beaten=" " commit item note answer
  [ -n "$token" ] && command -v curl >/dev/null 2>&1 || return 0
  for commit in $(git rev-list "$1..$2"); do
    for item in $(trailer "$commit" Item); do
      case "$beaten" in *" $item "*) continue ;; esac
      beaten="$beaten$item "
      note="$(json_text "$(printf 'pushed %s %s' "$(git rev-parse --short "$commit")" "$(git log -1 --format=%s "$commit")" | cut -c1-280)")"
      answer="$(curl -fsS --max-time 5 "${HQ_URL:-https://hq.thelittleworker.com}/mcp" -H "authorization: Bearer $token" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"beat_item\",\"arguments\":{\"item\":\"$(json_text "$item")\",\"note\":\"$note\"}}}" 2>/dev/null)" || answer=""
      case "$answer" in
        *"$item is live:"*) say "beat $item on HQ" ;;
        *) say "HQ took no beat for $item (no claim from this token, or HQ did not answer); the push stands" ;;
      esac
    done
  done
}
amend_trailers() {
  local drop="$1" args=() t
  shift
  for t in "$@"; do args+=(--trailer "$t"); done
  git log -1 --format=%B | sed -E "/^($drop): /d" | git interpret-trailers --if-exists add "${args[@]}" >"$tmp/msg"
  git commit --quiet --amend --only --no-verify -F "$tmp/msg"
}

if [ -n "$revert" ]; then
  target="$(git rev-parse --verify --quiet "$revert^{commit}")" || finish 1 "usage - : $revert is not a commit"
  git merge-base --is-ancestor "$target" origin/main || finish 5 "not-on-main $target - : only a commit on main can be reverted"
  git switch --quiet --detach origin/main
  git revert --no-edit "$target" >/dev/null || {
    git revert --abort >/dev/null 2>&1 || true
    finish 3 "conflict $target - : the revert does not apply on origin/main"
  }
  amend_trailers "Customer-note" "Customer-note: none (reverts ${target:0:12}${reason:+: $reason})"
  say "reverted ${target:0:12} as $(git rev-parse --short=12 HEAD)"
  skip="${skip:-revert of ${target:0:12}}"
fi

[ "$(git rev-list --count origin/main..HEAD)" -ge 1 ] || finish 5 "nothing - : HEAD has no commit that origin/main lacks"

rebase() {
  [ "$(git merge-base HEAD origin/main)" != "$(git rev-parse origin/main)" ] || return 0
  if ! git rebase --quiet origin/main >/dev/null 2>&1; then
    git rebase --abort >/dev/null 2>&1 || true
    finish 3 "conflict $(git rev-parse HEAD) - : rebase onto origin/main by hand, then run this again"
  fi
}

customer_notes() {
  [ -n "$NOTE_FREE_SCOPES" ] || return 0
  local c subject scope note head
  head="$(git rev-parse HEAD)"
  for c in $(git rev-list --reverse origin/main..HEAD); do
    subject="$(git log -1 --format=%s "$c")"
    [[ "$subject" =~ ^(feat|fix|perf)(\(([^\)]*)\))?!?: ]] || continue
    scope="${BASH_REMATCH[3]}"
    [[ "$NOTE_FREE_SCOPES" != *" $scope "* ]] || continue
    [ -z "$(trailer "$c" Customer-note)" ] || continue
    note="$(git log -1 --format=%B "$c" | sed -nE 's/^Customer-note: *(.+)$/\1/p' | head -1)"
    if [ "$c" = "$head" ] && [ -n "$note" ]; then
      [ "$verify" -eq 1 ] || amend_trailers "Customer-note" "Customer-note: $note"
      say "moved the Customer-note: line from the body to the trailers"
      continue
    fi
    finish 5 "no-customer-note $c - : add 'Customer-note: <one or two sentences>' or 'Customer-note: none (<reason>)' as a trailer"
  done
}

new_comments() {
  if [ -n "$COMMENT_SCAN" ]; then
    bash -c "$COMMENT_SCAN" || finish 1 "comment-scan-failed $(git rev-parse HEAD) - : $COMMENT_SCAN"
    return 0
  fi
  git diff -U0 --no-color --no-ext-diff --no-renames origin/main...HEAD |
    awk -v skip="$COMMENT_SKIP" '
      /^\+\+\+ / { file = substr($0, 7); kind = ""
        if (file ~ skip) next
        if (file ~ /\.(ts|tsx|js|jsx|mjs|cjs|swift|css)$/) kind = "slash"
        else if (file ~ /\.(sh|bash|toml|py|ya?ml)$/) kind = "hash"
        else if (file ~ /\.sql$/) kind = "dash"
        next }
      /^@@ / { split($3, at, ","); line = substr(at[1], 2) + 0; next }
      /^\+/ { text = substr($0, 2)
        if (kind == "slash" && text ~ /^[ \t]*(\/\/|\/\*|\*([ \t\/]|$))/ && text !~ /^[ \t]*\/\/(\/ *<reference| *@ts-expect-error | *MARK:| *swift-tools-version)/) hit = 1
        else if (kind == "hash" && text ~ /^[ \t]*#/ && text !~ /^[ \t]*#(!| *shellcheck )/) hit = 1
        else if (kind == "dash" && text ~ /^[ \t]*--/) hit = 1
        if (hit) print file ":" line ": " text
        hit = 0; line++ }'
}

refuse_comments() {
  local found
  found="$(new_comments)"
  [ -n "$found" ] || return 0
  say "these lines add code comments, which AGENTS.md bans:"
  printf '%s\n' "$found" >&2
  finish 5 "comments $(git rev-parse HEAD) - : take the new comments out, then run this again"
}

KILL_AWK="$(
  cat <<'AWK'
function killed(text,   t, pre, n, parts) {
  t = text
  if (t ~ /^[ \t]*>/ || t ~ /^[ \t-]*quote:/) return ""
  if (match(t, /^[ \t-]*[A-Za-z_][A-Za-z0-9_-]*:[ \t]*"/) && t ~ /"[ \t]*$/) { t = substr(t, RLENGTH + 1); sub(/"[ \t]*$/, "", t) }
  gsub(/`[^`]*`/, "", t)
  gsub(/"[^"]*"/, "", t)
  gsub(/“[^”]*”/, "", t)
  t = tolower(t)
  if (index(t, "—") || index(t, " – ")) return "em dash"
  if (t ~ /here('|’)?s the thing|here is the thing/) return "here's the thing"
  if (t ~ /(^|[^a-z])genuinely([^a-z]|$)/) return "genuinely"
  if (t ~ /(^|[^a-z])truly([^a-z]|$)/) return "truly"
  if (t ~ /(^|[^a-z])honestly([^a-z]|$)/) return "honestly"
  if (match(t, /(^|[^a-z])(isn('|’)t|is not|aren('|’)t|are not|wasn('|’)t|was not|it('|’)s not|that('|’)s not)[^.!?]*[,;:.!?]+ *(it('|’)s|it is|they('|’)re|they are|that('|’)s|this is|it was)([^a-z]|$)/)) {
    pre = substr(t, 1, RSTART)
    n = split(pre, parts, /[.!?]/)
    if (parts[n] !~ /(^|[^a-z])(if|when|whenever|unless|until|because|while|once|since|though|although)([^a-z]|$)/) return "X isn't Y, it's Z"
  }
  return ""
}
AWK
)"
killed_lines() {
  local c
  git diff -U0 --no-color --no-ext-diff --no-renames origin/main...HEAD |
    KILL_FILES_RE="$KILL_FILES" KILL_SKIP_RE="$KILL_SKIP" awk "$KILL_AWK"'
      /^\+\+\+ / { file = substr($0, 7); scan = file ~ ENVIRON["KILL_FILES_RE"] && file !~ ENVIRON["KILL_SKIP_RE"]; next }
      /^@@ / { split($3, at, ","); line = substr(at[1], 2) + 0; next }
      /^\+/ { text = substr($0, 2); if (scan && (k = killed(text)) != "") print file ":" line ": " k ": " text; line++ }'
  for c in $(git rev-list origin/main..HEAD); do
    git log -1 --format=%B "$c" | awk -v c="${c:0:12}" "$KILL_AWK"'{ if ((k = killed($0)) != "") print "commit " c ": " k ": " $0 }'
  done
}
count_kills() {
  local token="${HQ_ACCOUNT_TOKEN:-${WIKI_AGENT_TOKEN:-}}" kills lines line rest
  [ -n "$token" ] && command -v curl >/dev/null 2>&1 || return 0
  kills="$(printf '%s\n' "$1" | awk -F': ' '{ n[$2]++ } END { for (k in n) printf "%s\"%s\":%d", (s++ ? "," : ""), k, n[k] }')"
  lines=""
  while IFS= read -r line; do
    rest="${line#*: }"
    lines="$lines${lines:+,}{\"where\":\"$(json_text "${line%%: *}")\",\"kill\":\"$(json_text "${rest%%: *}")\",\"text\":\"$(json_text "${rest#*: }" | cut -c1-240)\"}"
  done < <(printf '%s\n' "$1" | head -10)
  curl -fsS --max-time 4 "${HQ_URL:-https://hq.thelittleworker.com}/api/kills/caught" -H "authorization: Bearer $token" -H 'content-type: application/json' \
    -d "{\"repo\":\"$(json_text "$(basename "$origin_url")")\",\"sha\":\"$(git rev-parse HEAD)\",\"kills\":{$kills},\"lines\":[$lines]}" >/dev/null 2>&1 &&
    say "counted on HQ's Kill catches page" || true
}
refuse_killed() {
  local found
  found="$(killed_lines)"
  [ -n "$found" ] || return 0
  say "these lines hold something on the kill list (RULES.md, Kill list):"
  printf '%s\n' "$found" >&2
  count_kills "$found"
  finish 5 "killed $(git rev-parse HEAD) - : rewrite these lines without it, then run this again; a quote keeps its words in quotes or a > line"
}

scan_secrets() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    say "no gitleaks here; the secret scan is skipped"
    return 0
  fi
  local code=0
  gitleaks git --no-banner --no-color --redact --exit-code 6 --log-opts "origin/main..HEAD" . >"$tmp/secrets.log" 2>&1 || code=$?
  [ "$code" -ne 6 ] || { cat "$tmp/secrets.log" >&2; finish 5 "secret $(git rev-parse HEAD) - : gitleaks found a secret; take it out and rotate it"; }
  [ "$code" -eq 0 ] || say "gitleaks could not run (exit $code); the secret scan is skipped"
}

capped() {
  local rc=0
  rm -f "$tmp/timed-out"
  set -m
  bash -c "$1" >>"$tmp/check.log" 2>&1 &
  CAPPED_PID=$!
  (
    sleep "$CAP"
    : >"$tmp/timed-out"
    kill -TERM -- "-$CAPPED_PID" 2>/dev/null
    sleep 2
    kill -KILL -- "-$CAPPED_PID" 2>/dev/null
  ) >/dev/null 2>&1 &
  WATCHDOG_PID=$!
  set +m
  wait "$CAPPED_PID" 2>/dev/null || rc=$?
  kill -KILL -- "-$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  CAPPED_PID="" WATCHDOG_PID=""
  [ ! -e "$tmp/timed-out" ] || rc=124
  return "$rc"
}

on_m4() {
  local sha job out misses=0 code="" start=$SECONDS
  sha="$(git rev-parse HEAD)"
  job="$M4_DIR.jobs/${sha:0:12}-$$"
  git bundle create "$tmp/head.bundle" origin/main..HEAD >/dev/null 2>&1
  cat >"$tmp/job.sh" <<REMOTE
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
d=$(printf '%q' "$M4_DIR")
job=$(printf '%q' "$job")
run() {
  [ -d "\$d/.git" ] || git clone -q $(printf '%q' "$CLONE_URL") "\$d" || return 12
  cd "\$d" && git fetch -q origin main && git fetch -q "\$job/head.bundle" HEAD &&
    git checkout -q --force --detach FETCH_HEAD && git clean -qfdx -e .build -e node_modules || return 12
  [ "\$(git rev-parse HEAD)" = $sha ] || return 12
  echo "WHERE M4, macOS \$(sw_vers -productVersion)"
  bash -c $(printf '%q' "$1")
}
work() {
  find "\$d.lock" -maxdepth 0 -mmin +60 -exec rm -rf {} + 2>/dev/null
  until mkdir "\$d.lock" 2>/dev/null; do sleep 5; done
  trap 'rm -rf "\$d.lock"' EXIT
  run
}
set -m
work &
wp=\$!
set +m
( while kill -0 "\$wp" 2>/dev/null; do
    if [ ! -d "\$job" ] || [ \$SECONDS -ge $((CAP + 30)) ]; then : >"\$job.stopped"; kill -TERM -- "-\$wp"; sleep 3; kill -KILL -- "-\$wp"; break; fi
    sleep 2
  done ) >/dev/null 2>&1 &
rc=0
wait "\$wp" || rc=\$?
[ "\$rc" -lt 128 ] || [ ! -e "\$job.stopped" ] || rc=124
rm -f "\$job.stopped"
echo \$rc >"\$job/exit"
REMOTE
  ssh_m4() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 "$M4_HOST" "$@"; }
  ssh_m4 "mkdir -p '$job' && cat >'$job/head.bundle'" <"$tmp/head.bundle" &&
    ssh_m4 "cat >'$job/job.sh' && { nohup bash '$job/job.sh' >'$job/log' 2>&1 </dev/null & }" <"$tmp/job.sh" || return 12
  while [ -z "$code" ]; do
    sleep "$POLL"
    if out="$(ssh_m4 "cat '$job/exit' 2>/dev/null; true" 2>/dev/null)"; then misses=0 code="$out"; else misses=$((misses + 1)); fi
    [ "$misses" -lt 8 ] || code=12
    [ -n "$code" ] || [ $((SECONDS - start)) -lt "$CAP" ] || code=124
  done
  ssh_m4 "cat '$job/log'; rm -rf '$job'" >>"$tmp/check.log" 2>/dev/null || true
  return "$code"
}

run_check() {
  local tree code=0 start=$SECONDS cmd="$CHECK" label="$CHECK_LABEL" where=here
  tree="$(git rev-parse --short=12 'HEAD^{tree}')"
  : >"$tmp/check.log"
  if [ -n "$skip" ]; then
    TESTED="Tested: skipped: $skip"
    return 0
  fi
  customer_notes
  refuse_comments
  refuse_killed
  scan_secrets
  if [ -n "$CHECK_PATHS" ] && ! git diff --name-only origin/main...HEAD | grep -Eq "$CHECK_PATHS"; then
    TESTED="Tested: $label skipped (nothing it reads changed) tree $tree"
    return 0
  fi
  if [ "$package" -eq 1 ] && [ -n "$PACKAGE" ]; then cmd="$cmd && $PACKAGE" label="$label + package"; fi
  say "running $label on $(git rev-parse --short=12 HEAD) (tree $tree), $CAP s at most"
  if [ "$CHECK_ON" = here ] || { [ "$(uname -s)" = Darwin ] && command -v swift >/dev/null 2>&1; }; then
    capped "$cmd" || code=$?
  elif ssh -o BatchMode=yes -o ConnectTimeout=5 "$M4_HOST" true >/dev/null 2>&1; then
    say "no Mac here; running it on the M4 ($M4_HOST)"
    on_m4 "$cmd" || code=$?
    where="$(sed -n 's/^WHERE //p' "$tmp/check.log" | head -1)"
  else
    finish 5 "no-mac $(git rev-parse HEAD) - : no Mac here and no ssh $M4_HOST; run it from a Mac, or pass --skip-checks \"<why>\""
  fi
  case "$code" in
    0) TESTED="Tested: $label pass (${where:-M4}, $((SECONDS - start))s) tree $tree" ;;
    124)
      tail -10 "$tmp/check.log" >&2
      say "WARNING: $label ran past $CAP s and was stopped; pushing anyway, and the Tested: trailer says so"
      TESTED="Tested: $label timed out after ${CAP}s tree $tree"
      ;;
    *)
      tail -30 "$tmp/check.log" >&2
      finish 2 "red $(git rev-parse HEAD) - : $label failed (exit $code); main is unchanged"
      ;;
  esac
}

for ((i = 0; i + 1 < ${#NOTICES[@]}; i += 2)); do
  ! git diff --name-only origin/main...HEAD | grep -Eq "${NOTICES[i]}" || say "${NOTICES[i + 1]}"
done

if [ "$verify" -eq 1 ]; then
  run_check
  finish 0 "checked $(git rev-parse HEAD) - : ${TESTED#Tested: }"
fi

for ((try = 1; try <= RETRIES; try++)); do
  rebase
  run_check
  amend_trailers "Tested" "$TESTED"
  sha="$(git rev-parse HEAD)"
  base="$(git rev-parse origin/main)"
  if out="$(git push --porcelain origin "$sha:refs/heads/main" 2>&1)"; then
    beat_items "$base" "$sha"
    finish 0 "pushed $sha"
  fi
  printf '%s\n' "$out" >&2
  case "$out" in
    *"non-fast-forward"* | *"fetch first"* | *"incorrect old value"* | *"cannot lock ref"*) ;;
    *) finish 1 "push-refused $sha - : see the git output above" ;;
  esac
  say "main moved (try $try of $RETRIES); fetching, rebasing and checking again"
  git fetch --quiet origin main || finish 1 "fetch-failed $sha - : git fetch origin main"
done
finish 4 "raced $(git rev-parse HEAD) - : main moved $RETRIES times"
