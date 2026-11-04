#!/usr/bin/env bash
# Appends the run's result to the job summary: the calibration lines, any preflight complaints and movers, and the PR
# performance section when there is one.
set -uo pipefail

{
    if [ -f "$WORK/out/bench_pr.log" ]; then
        echo "### Result"
        echo
        echo '```'
        grep -E '^(A-vs-A calibration|false movers|  [^ ].*[+-][0-9.]+%$)|BLOCKING|warning:' "$WORK/out/bench_pr.log" || true
        echo '```'
        echo
    fi
    [ -f "$WORK/out/pr-perf-section.md" ] && cat "$WORK/out/pr-perf-section.md"
} >> "$GITHUB_STEP_SUMMARY"
exit 0
