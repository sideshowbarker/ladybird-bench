#!/usr/bin/env bash
# Writes cpu_key (architecture plus CPU model, for keying compiler caches) to $GITHUB_OUTPUT, and the machine to the
# job summary.
set -euo pipefail

if [ "$(uname -s)" = Darwin ]; then
    model=$(sysctl -n machdep.cpu.brand_string)
    memory_gib=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    os="macOS $(sw_vers -productVersion)"
else
    model=$(lscpu | sed -n 's/^Model name: *//p' | head -1)
    memory_gib=$(free -g | awk '/^Mem:/ { print $2 }')
    os="Linux $(uname -r)"
fi
echo "cpu_key=$(uname -m)-$(printf '%s' "$model" | tr -c 'A-Za-z0-9' '-')" >> "$GITHUB_OUTPUT"
{
    echo "### Machine"
    echo
    echo "- Runner: ${RUNNER_LABEL}"
    echo "- CPU: ${model}, $(getconf _NPROCESSORS_ONLN) cores"
    echo "- Memory: ${memory_gib} GiB"
    echo "- OS: ${os}"
    echo "- Disk free: $(df -h "$GITHUB_WORKSPACE" | awk 'NR == 2 { print $4 }')"
    echo
} >> "$GITHUB_STEP_SUMMARY"
