#!/usr/bin/env bash
# Builds the simulated engine with the disconnect patch into a local image (never :latest):
#   bash docker/sim/build.sh                       -> carmonai/llm-d-inference-sim:v0.11.4-disconnect.1
#   SIM_TEST=1 bash docker/sim/build.sh            -> also runs the simulator's Go tests (the patch's included) in the build
#   SIM_SRC=<dir> SIM_IMAGE=<tag> bash docker/sim/build.sh
#
# SIM_SRC is a checkout of github.com/llm-d/llm-d-inference-sim at tag v0.11.4 (commit db3e12bdf8ccf500d93309dc73015fb811296404).
# The default is the one the prototype kept: ../../../prototype-sim/_sim-src-v0.11.4, i.e. work/prototype-sim next to the
# workspaces. The script does not clone anything; fetch the tag yourself if you have no copy. It copies the tree, makes
# the sources LF (a Windows checkout is CRLF), checks that they are exactly v0.11.4 (SRC_PIN below: sha256 of the sha256
# of every .go file, go.mod and go.sum, which is all `go build` reads), applies disconnect.patch and builds the Dockerfile
# next to this file. The patch is the whole difference to the pinned upstream engine; what it changes is in its header.
#
# What the patch does (G1 of work/prototype-sim/FINDINGS-contract.md, contract points E19, E34, E35):
#  - a client that hangs up stops the generation at its next token, in the queue, before the first token and mid-stream,
#    and a waiting request leaves the queue at once (stock v0.11.4 ran every request to its end);
#  - stream_options.continuous_usage_stats puts the usage so far on every chat chunk, as vLLM does (G3), so a cancelled
#    stream is billed the tokens it had produced;
#  - an aborted request counts the work done in vllm:request_success_total{finish_reason="abort"} and the token counters.
# It needs Docker (slots: this is a build, take one with work/docker-slots.sh) and network (Go modules, base images).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
TAG=${SIM_IMAGE:-carmonai/llm-d-inference-sim:v0.11.4-disconnect.1}
SRC=${SIM_SRC:-$here/../../../prototype-sim/_sim-src-v0.11.4}
SRC_PIN=c014e9cf50b2690601b7467efb964fd22ee6d3343a839e3ebda14039406c7f0b
[[ $TAG == *:* && $TAG != *:latest ]] || { echo "SIM_IMAGE must carry an explicit tag that is not latest: $TAG" >&2; exit 1; }

[[ -f $SRC/go.mod ]] || { echo "no simulator source at $SRC: check out llm-d-inference-sim tag v0.11.4 and set SIM_SRC" >&2; exit 1; }
ctx=$(mktemp -d)
log=$(mktemp)
trap 'rm -rf "$ctx" "$log"' EXIT
(cd "$SRC" && tar -c --exclude=.git .) | tar -x -C "$ctx"
cd "$ctx"
find . \( -name '*.go' -o -name go.mod -o -name go.sum \) -type f -exec sed -i 's/\r$//' {} +
got=$(find . -type f \( -name '*.go' -o -name go.mod -o -name go.sum \) | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
if [[ $got != "$SRC_PIN" ]]; then
  echo "the source at $SRC is not llm-d-inference-sim v0.11.4 (source hash $got, want $SRC_PIN)" >&2
  exit 1
fi
patch -p1 -s < "$here/disconnect.patch"

if [[ ${SIM_TEST:-0} == 1 ]]; then
  # --no-cache-filter: the suites run every time, so their lines are always in the log (a cached stage prints nothing)
  # --output type=cacheonly: nothing is stored (the test stage is 5.7 GB; without it every run left an image behind)
  docker build -f "$here/Dockerfile" --target test --no-cache-filter test --progress=plain --output type=cacheonly "$ctx" >"$log" 2>&1 || { tail -n 60 "$log" >&2; exit 1; }
  grep -E '^#[0-9]+ [0-9.]+ (ok|\?) ' "$log" || tail -n 5 "$log"
fi
docker build -f "$here/Dockerfile" -t "$TAG" "$ctx"
docker image inspect "$TAG" --format '{{.RepoTags}} {{.Id}}'
