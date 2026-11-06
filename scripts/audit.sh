#!/usr/bin/env bash
# Pre-push audit. Fails (exit 1) if anything that must not be published is tracked
# by git, or if the hand-in files are missing or too big.
#   bash scripts/audit.sh
set -u
fail=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; fail=1; }
ok()  { say "ok:   $*"; }

tracked=$(git ls-files)

# 1. No secrets in tracked files (key value, bearer tokens, filled .Renviron).
if [ -n "${MICROBURBS_API_KEY:-}" ] && git grep -qF "$MICROBURBS_API_KEY" -- . ; then
  bad "the Microburbs key value appears in a tracked file"
else ok "no key value in tracked files"; fi
if git grep -nE "Bearer [A-Za-z0-9._-]{12,}" -- . ':!scripts/audit.sh' >/dev/null; then
  bad "a literal bearer token is committed"; else ok "no literal bearer tokens"; fi
if echo "$tracked" | grep -qE '(^|/)\.Renviron$|(^|/)\.env'; then
  bad ".Renviron or .env is tracked"; else ok ".Renviron not tracked"; fi

# 2. No data, API output or licensed rows (current tree AND history).
if echo "$tracked" | grep -E '^(data|out|demo)/|\.(csv|gpkg|rds|zip|xlsx?|parquet)$' | grep -v '^tests/testthat/fixtures/' ; then
  bad "data files are tracked (listed above)"; else ok "no data files tracked"; fi
if git log --all --name-only --pretty=format: | grep -E '^(data|out|demo)/|\.(csv|gpkg|rds|zip|xlsx?)$' | grep -v '^tests/' | sort -u | grep -q . ; then
  bad "data files appear in git history"; else ok "no data files in history"; fi

# 3. Hand-in files present and within limits.
for f in README.md report.html; do
  if [ -f "$f" ]; then ok "$f present"; else bad "$f missing"; fi
done
for f in demo.mp4 pitch.mp4; do
  if [ -f "$f" ]; then
    mb=$(( $(wc -c < "$f") / 1048576 ))
    if [ "$mb" -lt 95 ]; then ok "$f ${mb} MB"; else bad "$f is ${mb} MB (limit 95)"; fi
  else bad "$f missing"; fi
done

# 4. Commit authorship.
if git log --pretty='%an <%ae>' | sort -u | grep -vq 'Jai07-purpleticAIEngineer <jgarlyal@gmail.com>\|Durand'; then
  say "note: commits by other authors exist (fine if they are teammates)"; fi

if [ $fail -eq 0 ]; then say "AUDIT PASSED"; else say "AUDIT FAILED"; fi
exit $fail
