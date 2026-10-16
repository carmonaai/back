#!/usr/bin/env bash
# Live check that the simulated engine notices a client that hangs up (G1 of work/prototype-sim/FINDINGS-contract.md,
# contract point E19) and reports usage on every chunk when asked (G3). It needs no compose stack: it starts the image
# on a private network, drives it with python (the tools image's pinned base) over raw sockets, and removes both.
#   bash docker/check-sim-disconnect.sh [image]       default: carmona/llm-d-inference-sim:v0.11.4-disconnect.1 (docker/sim/build.sh)
# It exits 1 on any failed assertion. It is also the negative control of the patch: against upstream's own image
#   bash docker/check-sim-disconnect.sh ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb00ac62d0eb7c100e7a6816b8acec487aa06f0f38dba72b0ab1754e8f6
# every assertion about the hang-up and about usage fails (it keeps generating for nobody).
# Run it through the slot semaphore: bash work/docker-slots.sh run <name> -- bash docker/check-sim-disconnect.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
IMAGE=${1:-${ENGINE_IMAGE:-carmona/llm-d-inference-sim:v0.11.4-disconnect.1}}
PY=$(sed -nE 's/^FROM (python[^ ]+).*/\1/p' "$here/tools/Dockerfile")
NET=carmona-p2-har-simchk
NAME=carmona-p2-har-simchk-engine
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; }
trap cleanup EXIT
cleanup
docker network create "$NET" >/dev/null || exit 1
# One slot and a queue of 4, so a second request has to wait; the latency of the engine in compose.yaml.
docker run -d --name "$NAME" --network "$NET" --read-only --cap-drop ALL --security-opt no-new-privileges:true --memory 256m \
  "$IMAGE" --model=carmona/qwen3-4b --port=8000 --mode=echo --max-num-seqs=1 --max-waiting-queue-length=4 --max-model-len=4096 \
  --latency-calculator=constant --time-to-first-token=600ms --time-to-first-token-std-dev=0ms \
  --inter-token-latency=24ms --inter-token-latency-std-dev=0ms --seed=42 >/dev/null || exit 1
sleep 2
docker run --rm -i --network "$NET" --read-only --cap-drop ALL --user 10001 "$PY" python3 - "$NAME" <<'PY'
import json, socket, sys, time, urllib.request

host, port = sys.argv[1], 8000
failures = 0


def check(ok, what, detail=""):
    global failures
    failures += 0 if ok else 1
    print(("ok   " if ok else "FAIL ") + what + (" (" + detail + ")" if detail else ""), flush=True)


scrape_errors = 0


def metric(name, match=""):
    global scrape_errors
    for _ in range(5):
        try:
            text = urllib.request.urlopen("http://%s:%d/metrics" % (host, port), timeout=5).read().decode()
            break
        except Exception:  # upstream's engine answers a scrape 500 after a hang-up mid-stream (a failed write is sent to the next request)
            scrape_errors += 1
            time.sleep(0.1)
    else:
        raise SystemExit("the engine's /metrics does not answer")
    return sum(float(l.rsplit(" ", 1)[1]) for l in text.splitlines() if l.startswith(name + "{") and match in l)


running = lambda: metric("vllm:num_requests_running")
waiting = lambda: metric("vllm:num_requests_waiting")
generated = lambda: metric("vllm:generation_tokens_total")
aborted = lambda: metric("vllm:request_success_total", 'finish_reason="abort"')


def body(words, options=None):
    # in echo mode the answer is the prompt, so the number of words is the number of tokens (+ the chat template's)
    req = {"model": "carmona/qwen3-4b", "max_tokens": 1000, "stream": True,
           "messages": [{"role": "user", "content": " ".join("w%d" % i for i in range(words))}]}
    if options:
        req["stream_options"] = options
    return json.dumps(req)


def send(payload):
    s = socket.create_connection((host, port))
    s.sendall(("POST /v1/chat/completions HTTP/1.1\r\nHost: sim\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s"
               % (len(payload), payload)).encode())
    return s


def read_until(s, marker, secs):
    s.settimeout(secs)
    data = b""
    end = time.time() + secs
    while marker not in data and time.time() < end:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
    return data


def wait_for(fn, want, secs):
    """Seconds until fn() == want, or None."""
    start = time.time()
    while time.time() - start < secs:
        if fn() == want:
            return time.time() - start
        time.sleep(0.05)
    return None


def idle(secs=30):
    return wait_for(running, 0, secs) is not None and wait_for(waiting, 0, secs) is not None


check(idle(), "engine idle at the start")

# 1. a client that hangs up in the middle of a stream: 300 tokens are 7 s of generation, the hang-up comes after about 1 s
s = send(body(300))
read_until(s, b'"content"', 10)
a0, g0 = aborted(), generated()
s.close()
t = wait_for(running, 0, 3)
check(t is not None and t < 1.0, "engine idle within 1 s of a hang-up mid-stream",
      "idle after %s s" % ("%.2f" % t if t is not None else "more than 3"))
if t is not None:
    wait_for(aborted, a0 + 1, 2)
    gen = generated() - g0
    check(aborted() == a0 + 1, "the cut stream is counted once as finish_reason=abort", "abort %d -> %d" % (a0, aborted()))
    check(gen < 40, "only the tokens produced before the hang-up are counted", "%d tokens after the hang-up, 300 in the prompt" % gen)
    time.sleep(0.5)
    check(generated() - g0 == gen, "no token is generated after that")
check(idle(), "engine idle again")  # a stock engine needs the 7 s here

# 2. a client that hangs up before the first token (600 ms of prefill)
a0, g0 = aborted(), generated()
s = send(body(300))
wait_for(running, 1, 2)
time.sleep(0.2)
s.close()
t = wait_for(running, 0, 3)
check(t is not None and t < 1.0, "engine idle within 1 s of a hang-up during prefill",
      "idle after %s s" % ("%.2f" % t if t is not None else "more than 3"))
time.sleep(0.3)
check(generated() == g0 and aborted() == a0, "nothing is counted for a prompt that was never processed")
check(idle(), "engine idle again")

# 3. a client that hangs up while its request waits in the queue; the request in front of it is not touched
first = send(body(60))  # about 2 s
wait_for(running, 1, 2)
queued = send(body(60))
check(wait_for(waiting, 1, 2) is not None, "the second request waits in the queue")
queued.close()
t = wait_for(waiting, 0, 3)
check(t is not None and t < 1.0, "the queue is empty within 1 s of the waiting client's hang-up",
      "empty after %s s" % ("%.2f" % t if t is not None else "more than 3"))
check(running() == 1, "the request in front of it is still running")
answer = read_until(first, b"data: [DONE]", 15)
check(b"data: [DONE]" in answer, "and it is answered to the end")
first.close()
check(idle(), "engine idle again")

# 4. stream_options.continuous_usage_stats: the usage so far on every chunk, the role chunk first
s = send(body(8, {"include_usage": True, "continuous_usage_stats": True}))
raw = read_until(s, b"data: [DONE]", 10).decode(errors="replace")
s.close()
chunks = [json.loads(l[6:]) for l in raw.splitlines() if l.startswith("data: {")]
with_choices = [c for c in chunks if c.get("choices")]
check(len(with_choices) > 8 and all(c.get("usage") for c in with_choices), "every chunk carries usage",
      "%d of %d chunks have it" % (sum(1 for c in with_choices if c.get("usage")), len(with_choices)))
if with_choices and with_choices[0].get("usage"):
    u0 = with_choices[0]["usage"]
    check(u0["completion_tokens"] == 0 and u0["prompt_tokens"] > 0, "the role chunk has the prompt tokens and no completion tokens", json.dumps(u0))
    done = [c["usage"]["completion_tokens"] for c in with_choices if c.get("usage")]
    check(done == sorted(done) and done[-1] == len(done) - 2, "completion tokens count up with the chunks",
          "%d chunks, last says %d" % (len(done), done[-1]))
check(chunks and chunks[-1].get("usage") and not chunks[-1].get("choices"), "the usage chunk is still the last one")

check(scrape_errors == 0, "the engine's /metrics answered every scrape", "%d failed scrapes" % scrape_errors)
print("check-sim-disconnect: %d failed" % failures)
sys.exit(1 if failures else 0)
PY
rc=$?
[[ $rc -ne 0 ]] && { echo "--- engine log (tail)"; docker logs --tail 15 "$NAME" 2>&1; }
exit $rc
