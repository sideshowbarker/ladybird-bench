#!/usr/bin/env bash
# Runs inside the ladybird-ci container, as root, with the job's work directory mounted at /work.
#
#   in-container.sh build     compile both arms into /work/worktrees (bench_pr.py's own build recipe)
#   in-container.sh measure   run bench_pr.py over the arms the build phase left
#
# The two phases are separate so that the workflow can save the compiler and vcpkg caches between them: a first run
# that runs out of time in the build still leaves the next run a warm cache.
#
# Inputs, from the environment: MODE (calibrate or compare), HEAD_SHA, BASE_SHA, ROUNDS, BENCHMARKS, FOCUS.
set -euo pipefail

phase=${1:?usage: in-container.sh build|measure}

export XDG_CACHE_HOME=/work/cache
export XDG_RUNTIME_DIR=/work/xdg-runtime
export CCACHE_DIR=/work/cache/ccache
export CCACHE_MAXSIZE=5G
# The two arms are two worktrees, and every compile runs in its arm's Build/distribution: Relative paths plus no
# hashed working directory make an object from one arm a cache hit for the other.
export CCACHE_BASEDIR=/work/worktrees
export CCACHE_NOHASHDIR=true
export SCCACHE_DIR=/work/cache/sccache
export SCCACHE_CACHE_SIZE=2G
export CC=clang CXX=clang++
export PYTHONUNBUFFERED=1

mkdir -p "$XDG_CACHE_HOME" "$CCACHE_DIR" "$SCCACHE_DIR" /work/out
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
git config --global --add safe.directory '*'

wb=/work/web-benchmarks
python=$wb/.venv/bin/python
if [ ! -x "$python" ]; then
    python3 -m venv "$wb/.venv"
    "$wb/.venv/bin/pip" install --quiet -r "$wb/requirements.txt"
fi

case "$phase" in
build)
    ccache -z > /dev/null
    # bench_pr.py builds an arm only when its tree lacks a build stamp for that sha, so building here first leaves
    # the measure phase nothing to compile. Same function, same recipe.
    "$python" - <<'PYEOF'
import os, sys
sys.path.insert(0, "/work/web-benchmarks")
sys.argv = ["bench_pr.py"]
import bench_pr
base, head = os.environ["BASE_SHA"], os.environ["HEAD_SHA"]
bench_pr.ensure_worktree("base", base, "/work/src", "/work/worktrees")
bench_pr.ensure_worktree("head", head, "/work/src", "/work/worktrees")
PYEOF
    ccache -s
    ;;
measure)
    # bench_pr.py's preflight refuses a 1-minute load above a quarter of the cores, and the build has only just
    # finished. Let it settle — the measurement wants a quiet machine anyway.
    ncpu=$(nproc)
    for _ in $(seq 1 60); do
        load=$(cut -d' ' -f1 /proc/loadavg)
        if awk -v l="$load" -v n="$ncpu" 'BEGIN { exit !(l < n / 6) }'; then
            break
        fi
        sleep 10
    done
    echo "1-minute load before measuring: $(cut -d' ' -f1 /proc/loadavg) on $ncpu cores"

    args=(--ladybird /work/src --worktree-root /work/worktrees --rounds "$ROUNDS" -o /work/out/pr-perf-section.md)
    [ "$MODE" = calibrate ] && args+=(--calibrate)
    [ -n "${BENCHMARKS:-}" ] && args+=(--benchmarks "$BENCHMARKS")
    if [ -n "${FOCUS:-}" ]; then
        read -r -a focus <<< "$FOCUS"
        args+=(--focus "${focus[@]}")
    fi
    "$python" "$wb/bench_pr.py" "${args[@]}" 2>&1 | tee /work/out/bench_pr.log
    exit "${PIPESTATUS[0]}"
    ;;
*)
    echo "unknown phase: $phase" >&2
    exit 2
    ;;
esac
