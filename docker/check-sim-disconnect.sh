#!/usr/bin/env bash
# Live check that the simulated engine notices a client that hangs up (G1 of work/prototype-sim/FINDINGS-contract.md,
# contract point E19), reports usage on every chunk when asked (G3) and, started with --enable-per-request-metrics, sends
# vLLM's per-request timing report (OB-18). It needs no compose stack: it starts the image twice on a private network (the
# second time with that flag), drives the engines with python (the tools image's pinned base) over raw sockets, and removes all.
#   bash docker/check-sim-disconnect.sh [image]       default: carmona/llm-d-inference-sim:v0.11.4-disconnect.2 (docker/sim/build.sh)
# It exits 1 on any failed assertion. It is also the negative control of the patch: against upstream's own image
#   bash docker/check-sim-disconnect.sh ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb00ac62d0eb7c100e7a6816b8acec487aa06f0f38dba72b0ab1754e8f6
# every assertion about the hang-up and about usage fails (it keeps generating for nobody), and the engine with the flag does
# not start at all (upstream has no such flag).
# Run it through the slot semaphore: bash work/docker-slots.sh run <name> -- bash docker/check-sim-disconnect.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
IMAGE=${1:-${ENGINE_IMAGE:-carmona/llm-d-inference-sim:v0.11.4-disconnect.2}}
PY=$(sed -nE 's/^FROM (python[^ ]+).*/\1/p' "$here/tools/Dockerfile")
NET=carmona-p2-har-simchk
NAME=carmona-p2-har-simchk-engine
NAME2=carmona-p2-har-simchk-report
cleanup() { docker rm -f "$NAME" "$NAME2" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; }
trap cleanup EXIT
cleanup
docker network create "$NET" >/dev/null || exit 1
# One slot and a queue of 4, so a second request has to wait; the latency of the engine in compose.yaml. $1 is the name, the
# rest are more flags.
engine() {
  docker run -d --name "$1" --network "$NET" --read-only --cap-drop ALL --security-opt no-new-privileges:true --memory 256m \
    "$IMAGE" --model=carmona/qwen3-4b --port=8000 --mode=echo --max-num-seqs=1 --max-waiting-queue-length=4 --max-model-len=4096 \
    --latency-calculator=constant --time-to-first-token=600ms --time-to-first-token-std-dev=0ms \
    --inter-token-latency=24ms --inter-token-latency-std-dev=0ms --seed=42 "${@:2}" >/dev/null
}
engine "$NAME" || exit 1
engine "$NAME2" --enable-per-request-metrics || exit 1
sleep 2
docker run --rm -i --network "$NET" --read-only --cap-drop ALL --user 10001 "$PY" python3 - "$NAME" "$NAME2" <<'PY'
import json, socket, sys, time, urllib.request

host, port = sys.argv[1], 8000
reporting = sys.argv[2]  # the same engine started with --enable-per-request-metrics
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


def body(words, options=None, **more):
    # in echo mode the answer is the prompt, so the number of words is the number of tokens (+ the chat template's)
    req = {"model": "carmona/qwen3-4b", "max_tokens": 1000, "stream": True,
           "messages": [{"role": "user", "content": " ".join("w%d" % i for i in range(words))}]}
    if options:
        req["stream_options"] = options
    req.update(more)  # stream=False for a whole answer, n=2
    return json.dumps(req)


def send(payload, to=None):
    s = socket.create_connection((to or host, port))
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

# 5. the engine's timing report, as vLLM sends it with --enable-per-request-metrics: the object "metrics" beside "usage", on the
#    final usage chunk of a stream and on a whole answer; never on a chunk before it, never for n > 1, and not at all without the flag
FIVE = ["queue_time_ms", "time_to_first_token_ms", "generation_time_ms", "mean_itl_ms", "tokens_per_second"]
USAGE = {"include_usage": True, "continuous_usage_stats": True}  # what inference-service always asks of a stream


def whole(h, payload):
    req = urllib.request.Request("http://%s:%d/v1/chat/completions" % (h, port), payload.encode(), {"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read())


def stream(h, payload):
    s = send(payload, h)
    raw = read_until(s, b"data: [DONE]", 15).decode(errors="replace")
    s.close()
    return [json.loads(l[6:]) for l in raw.splitlines() if l.startswith("data: {")]


def is_report(m):
    return isinstance(m, dict) and sorted(m) == sorted(FIVE) and all(isinstance(m[k], (int, float)) and not isinstance(m[k], bool) for k in FIVE)


def up(h, secs=10):
    end = time.time() + secs
    while time.time() < end:
        try:
            urllib.request.urlopen("http://%s:%d/health" % (h, port), timeout=2).read()
            return True
        except Exception:
            time.sleep(0.2)
    return False


plain = stream(host, body(8, USAGE))
check(plain and plain[-1].get("usage") and not plain[-1].get("choices"), "without the flag a stream still ends in its usage chunk")
check(not any("metrics" in c for c in plain), "without the flag no chunk carries a report")
check("metrics" not in whole(host, body(8, stream=False)), "without the flag a whole answer carries none")

ready = up(reporting)
check(ready, "the engine started with --enable-per-request-metrics answers")
if ready:
    s = stream(reporting, body(8, USAGE))
    m = s[-1].get("metrics") if s else None
    check(s and s[-1].get("usage") and not s[-1].get("choices") and m is not None, "the final usage chunk carries the report")
    check(not any("metrics" in c for c in s[:-1]), "no chunk before it carries one, though each has its usage so far",
          "%d chunks before it" % (len(s) - 1))
    check(is_report(m), "the report has the five fields, all numbers", json.dumps(m))
    if is_report(m):
        check(550 <= m["time_to_first_token_ms"] <= 800, "the prefill is the first-token delay, 600 ms, in milliseconds",
              "%.1f ms" % m["time_to_first_token_ms"])
        check(m["generation_time_ms"] > 0 and m["mean_itl_ms"] > 0 and m["tokens_per_second"] > 0, "it took time to generate", json.dumps(m))
        check(m["queue_time_ms"] < 100, "a request that finds a free worker does not wait", "%.1f ms" % m["queue_time_ms"])

    w = whole(reporting, body(8, stream=False))
    check(is_report(w.get("metrics")), "a whole answer carries the report too", json.dumps(w.get("metrics")))

    cut = send(body(300, USAGE), reporting)  # a stream that is cut before its usage chunk has not seen a report
    seen = read_until(cut, b'"content"', 10)
    cut.close()
    check(b'"content"' in seen and b"metrics" not in seen, "a stream cut early shows none")

    w2 = whole(reporting, body(5, stream=False, n=2))
    check(len(w2.get("choices", [])) == 2 and "metrics" not in w2, "n=2: a whole answer carries none")
    s2 = stream(reporting, body(5, USAGE, n=2))
    check(s2 and s2[-1].get("usage") and not any("metrics" in c for c in s2), "n=2: the usage chunk carries none")

check(scrape_errors == 0, "the engine's /metrics answered every scrape", "%d failed scrapes" % scrape_errors)
print("check-sim-disconnect: %d failed" % failures)
sys.exit(1 if failures else 0)
PY
rc=$?
[[ $rc -ne 0 ]] && { echo "--- engine log (tail)"; docker logs --tail 15 "$NAME" 2>&1; echo "--- engine with the flag, log (tail)"; docker logs --tail 15 "$NAME2" 2>&1; }
exit $rc
