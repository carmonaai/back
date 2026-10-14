# The simulated engine with the disconnect patch (docker/sim/disconnect.patch) applied to llm-d-inference-sim v0.11.4.
# Not built by compose: `bash docker/sim/build.sh` prepares the context (the verified, patched source) and tags the image.
#
# builder: the source is compiled the way upstream's Dockerfile does it (pure Go, no CGO). Base pinned by digest.
FROM golang:1.26.6@sha256:0d1d3a794be25f809dd2cb3160d8c73276c4056a9f8242a138e908ddeee7b6b6 AS builder
WORKDIR /workspace
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/llm-d-inference-sim ./cmd/llm-d-inference-sim

# test (build.sh with SIM_TEST=1): the simulator's own suites plus the patch's, as go test runs them.
FROM builder AS test
RUN go test -count=1 ./pkg/api/... ./pkg/simulator/... ./pkg/communication/...

# The runtime image is upstream's own, pinned by digest (distroless static, uid 65532, same entrypoint and port):
# only the binary is replaced, so the patched image differs from the pinned one by nothing else.
FROM ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb00ac62d0eb7c100e7a6816b8acec487aa06f0f38dba72b0ab1754e8f6
COPY --from=builder /out/llm-d-inference-sim /app/llm-d-inference-sim
