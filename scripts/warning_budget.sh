#!/usr/bin/env bash
set -euo pipefail

PROJECT="LotusPlannerV3/LotusPlannerV3.xcodeproj"
SCHEME="LotusPlannerV3"
DERIVED_DATA="${DERIVED_DATA:-/tmp/LotusPlannerV3WarningBudget}"
MAX_WARNINGS="${MAX_WARNINGS:-120}"

log_file="$(mktemp "${TMPDIR:-/tmp}/lotus-warning-budget.XXXXXX")"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$log_file"

warning_count="$(
  awk '
    /warning:/ {
      warning = $0
      sub(/^.*warning: /, "warning: ", warning)
      key = $0
      if (match($0, /[^ ]+:[0-9]+:[0-9]+: warning:/)) {
        key = substr($0, RSTART, RLENGTH) " " warning
      }
      warnings[key] = 1
    }
    END {
      count = 0
      for (warning in warnings) {
        count++
      }
      print count
    }
  ' "$log_file"
)"
echo "warning_count=$warning_count"
echo "warning_budget=$MAX_WARNINGS"

if [ "$warning_count" -gt "$MAX_WARNINGS" ]; then
  echo "Warning budget exceeded: $warning_count > $MAX_WARNINGS"
  exit 1
fi
