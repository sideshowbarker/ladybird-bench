#!/usr/bin/env bash
# Clones upstream Ladybird into $WORK/src (origin is upstream, so bench_pr.py's merge-base is against upstream master),
# checks the measured commit out detached, and clones the benchmarks into $WORK/web-benchmarks. Writes head, base,
# image (the ladybird-ci image the head's CI uses), and vcpkg_key to $GITHUB_OUTPUT.
#
# Inputs, from the environment: WORK, MODE, LADYBIRD_REPO, LADYBIRD_REF, BENCHMARKS_REPO, BENCHMARKS_REF.
set -euo pipefail
: "${WORK:?}" "${MODE:?}" "${LADYBIRD_REPO:?}" "${BENCHMARKS_REPO:?}" "${BENCHMARKS_REF:?}"

mkdir -p "$WORK"
git clone --quiet --filter=blob:none https://github.com/LadybirdBrowser/ladybird.git "$WORK/src"
cd "$WORK/src"
if [ -n "$LADYBIRD_REF" ]; then
    git fetch --quiet --filter=blob:none "https://github.com/${LADYBIRD_REPO}.git" "$LADYBIRD_REF"
    head=$(git rev-parse FETCH_HEAD)
else
    head=$(git rev-parse origin/master)
fi
git checkout --quiet --detach "$head"
if [ "$MODE" = calibrate ]; then
    base=$head
else
    base=$(git merge-base "$head" origin/master)
    if [ "$base" = "$head" ]; then
        echo "::error::$head is already on master, so there's nothing to compare."
        exit 1
    fi
fi
image=$(git show "$head:.github/workflows/ci.yml" | grep -o 'ghcr.io/ladybirdbrowser/ladybird-ci:[0-9.]*' | head -1)
[ -n "$image" ] || { echo "::error::No ladybird-ci image named in ci.yml at $head"; exit 1; }
{
    echo "head=$head"
    echo "base=$base"
    echo "image=$image"
    echo "vcpkg_key=$(git show "$head:vcpkg.json" | shasum -a 256 | cut -c1-16)"
} >> "$GITHUB_OUTPUT"

git clone --quiet "https://github.com/${BENCHMARKS_REPO}.git" "$WORK/web-benchmarks"
git -C "$WORK/web-benchmarks" checkout --quiet --detach "$BENCHMARKS_REF"
{
    echo "### Revisions"
    echo
    echo "- Head: ${head} (${LADYBIRD_REPO} ${LADYBIRD_REF:-master})"
    echo "- Base: ${base}"
    echo "- Benchmarks: $(git -C "$WORK/web-benchmarks" rev-parse --short HEAD)"
    echo "- Image (Linux): ${image}"
    echo
} >> "$GITHUB_STEP_SUMMARY"
