#!/usr/bin/env bash
# One phase of a benchmark run, over the job's work directory: $WORK, or /work inside the ladybird-ci container.
#
#   phase.sh build     compile both arms into $WORK/worktrees (bench_pr.py's own build recipe)
#   phase.sh measure   run bench_pr.py over the arms the build phase left
#
# The two phases are separate so that the workflow can save the compiler and vcpkg caches between them: a first run
# that runs out of time in the build still leaves the next run a warm cache.
#
# On Linux, this runs inside the ladybird-ci container as root; on macOS, directly on the runner.
#
# Inputs, from the environment: MODE (calibrate or compare), HEAD_SHA, BASE_SHA, ROUNDS, BENCHMARKS, EXCLUDE, FOCUS.
set -euo pipefail

phase=${1:?usage: phase.sh build|measure}
work=${WORK:-/work}
export WORK=$work
os=$(uname -s)

export XDG_CACHE_HOME=$work/cache
export CCACHE_DIR=$work/cache/ccache
export CCACHE_MAXSIZE=5G
# The two arms are two worktrees, and every compile runs in its arm's Build/distribution: Relative paths plus no
# hashed working directory make an object from one arm a cache hit for the other.
export CCACHE_BASEDIR=$work/worktrees
export CCACHE_NOHASHDIR=true
export SCCACHE_DIR=$work/cache/sccache
export SCCACHE_CACHE_SIZE=2G
export PYTHONUNBUFFERED=1
if [ "$os" = Linux ]; then
    export XDG_RUNTIME_DIR=$work/xdg-runtime
    export CC=clang CXX=clang++
    # vcpkg's own downloaded tools are x86_64-only.
    [ "$(uname -m)" = aarch64 ] && export VCPKG_FORCE_SYSTEM_BINARIES=1
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    git config --global --add safe.directory '*'
fi

mkdir -p "$XDG_CACHE_HOME" "$CCACHE_DIR" "$SCCACHE_DIR" "$work/out"

wb=$work/web-benchmarks
python=$wb/.venv/bin/python
if [ ! -x "$python" ]; then
    python3 -m venv "$wb/.venv"
    "$wb/.venv/bin/pip" install --quiet -r "$wb/requirements.txt"
fi

load1() {
    if [ "$os" = Darwin ]; then sysctl -n vm.loadavg | awk '{ print $2 }'; else cut -d' ' -f1 /proc/loadavg; fi
}

case "$phase" in
build)
    ccache -z > /dev/null
    # bench_pr.py builds an arm only when its tree lacks a build stamp for that sha, so building here first leaves
    # the measure phase nothing to compile. Same function, same recipe.
    "$python" - "$work" <<'PYEOF'
import os, sys
work = sys.argv[1]
sys.path.insert(0, os.path.join(work, "web-benchmarks"))
sys.argv = ["bench_pr.py"]
import bench_pr
src, root = os.path.join(work, "src"), os.path.join(work, "worktrees")
bench_pr.ensure_worktree("base", os.environ["BASE_SHA"], src, root)
bench_pr.ensure_worktree("head", os.environ["HEAD_SHA"], src, root)
PYEOF
    ccache -s
    ;;
measure)
    # bench_pr.py's preflight refuses a 1-minute load above a quarter of the cores, and the build has only just
    # finished. Let it settle — the measurement wants a quiet machine anyway.
    ncpu=$(getconf _NPROCESSORS_ONLN)
    for _ in $(seq 1 60); do
        if awk -v l="$(load1)" -v n="$ncpu" 'BEGIN { exit !(l < n / 6) }'; then
            break
        fi
        sleep 10
    done
    echo "1-minute load before measuring: $(load1) on $ncpu cores"

    args=(--ladybird "$work/src" --worktree-root "$work/worktrees" --rounds "$ROUNDS" -o "$work/out/pr-perf-section.md")
    [ "$MODE" = calibrate ] && args+=(--calibrate)
    suites=${BENCHMARKS:-}
    if [ -z "$suites" ] && [ -n "${EXCLUDE:-}" ]; then
        # Every suite bench_pr.py runs by default, less the excluded ones.
        suites=$("$python" - <<'PYEOF2'
import os, sys
sys.path.insert(0, os.path.join(os.environ["WORK"], "web-benchmarks"))
import bench_plan
excluded = set(os.environ["EXCLUDE"].replace(",", " ").split())
print(",".join(s for s in bench_plan.default_suites() if s not in excluded))
PYEOF2
)
    fi
    [ -n "$suites" ] && args+=(--benchmarks "$suites")
    if [ -n "${FOCUS:-}" ]; then
        read -r -a focus <<< "$FOCUS"
        args+=(--focus "${focus[@]}")
    fi
    "$python" "$wb/bench_pr.py" "${args[@]}" 2>&1 | tee "$work/out/bench_pr.log"
    exit "${PIPESTATUS[0]}"
    ;;
*)
    echo "unknown phase: $phase" >&2
    exit 2
    ;;
esac
