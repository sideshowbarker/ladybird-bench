# ladybird-bench

Runs web-benchmarks’ bench_pr.py on GitHub-hosted runners, so that a measurement needs no local machine.

One manually dispatched job builds both arms with bench_pr.py’s own recipe, inside the ladybird-ci image that the
measured commit’s CI uses. It saves the compiler and vcpkg caches, then measures. The build is a separate step, so a
first run that runs out of time still leaves the next one a warm cache.

## Calibrate a runner type

    gh workflow run bench.yml -R sideshowbarker/ladybird-bench -f mode=calibrate -f runner=ubuntu-24.04
    gh workflow run bench.yml -R sideshowbarker/ladybird-bench -f mode=calibrate -f runner=ubuntu-24.04-arm

Run each at least three times: The first run fills the caches, and the spread across runs shows how much a runner
type varies from one VM to the next. Each run reports its resolution (median and p90) and its false movers in the job
summary. Compare that with the macOS laptop’s calibration (±7.3% at p90): A runner type is usable when it reports
0 false movers and a p90 near that.

## Measure a branch

    gh workflow run bench.yml -R sideshowbarker/ladybird-bench -f mode=compare -f ladybird_ref=<branch-or-sha>

The baseline is the branch’s merge-base with upstream master. The job summary carries the PR performance section, and
the artifact holds it with the per-round results and the logs. A compare run restores that runner type’s most
recent calibration record.
