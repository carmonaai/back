#!/usr/bin/env bash
# Upgrade check for valkey-data: valkey used to run as root, so an existing volume is root-owned (0700) and uid 999 cannot
# write its append-only file. This builds that old volume (old command, as root, one key), starts ONLY valkey through compose
# and asserts the key survived. With `NO_DEPS=1` it skips valkey-volume and must fail: that is the check that the init is what fixes it.
# Own project name and volume; touches nothing else. Run it through the slot semaphore (it starts two containers).
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
P=carmona-p2-har-vk
V=${P}_valkey-data
IMG=$(sed -nE 's#^[[:space:]]*image: (valkey/valkey:[^[:space:]]+).*#\1#p' compose.yaml | head -1)
DC=(docker compose -p "$P" -f compose.yaml)
# compose.yaml requires every ${VAR:?} at parse time, even for services that do not run: dummy values, this run only.
for v in $(grep -oE '\$\{[A-Z_]+:\?' compose.yaml | tr -d '${:?' | sort -u); do
  [[ -n ${!v:-} ]] || export "$v=dummy-$v"
done
export VALKEY_PASSWORD=check-only
cleanup() { docker rm -f "$P-old" >/dev/null 2>&1 || true; "${DC[@]}" down -v >/dev/null 2>&1 || true; docker volume rm "$V" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
docker volume create --label "com.docker.compose.project=$P" --label com.docker.compose.volume=valkey-data "$V" >/dev/null

# The old state: the previous command, as root (sh -c skipped the entrypoint's step down), one key on disk.
docker run -d --name "$P-old" --user 0:0 -v "$V:/data" "$IMG" sh -c "exec valkey-server --save '' --appendonly yes --appendfsync always" >/dev/null
for _ in $(seq 20); do docker exec "$P-old" valkey-cli ping 2>/dev/null | grep -q PONG && break; sleep 0.5; done
docker exec "$P-old" valkey-cli set upgrade-check kept | grep -q OK
docker stop "$P-old" >/dev/null; docker rm "$P-old" >/dev/null

if [[ ${NO_DEPS:-0} == 1 ]]; then "${DC[@]}" up -d --no-deps --wait valkey >/dev/null 2>&1 || true; else "${DC[@]}" up -d --wait valkey >/dev/null 2>&1 || true; fi
got=$("${DC[@]}" exec -T valkey sh -c 'valkey-cli --no-auth-warning -a "$VALKEY_PASSWORD" get upgrade-check' 2>/dev/null | tr -d '\r' || true)
# A second time, as smoke.sh does when it restarts valkey: the directory is valkey's now, and the init must still pass.
if [[ $got == kept && ${NO_DEPS:-0} != 1 ]]; then
  "${DC[@]}" stop valkey >/dev/null 2>&1
  "${DC[@]}" up -d --wait valkey >/dev/null 2>&1 || true
  got=$("${DC[@]}" exec -T valkey sh -c 'valkey-cli --no-auth-warning -a "$VALKEY_PASSWORD" get upgrade-check' 2>/dev/null | tr -d '\r' || true)
fi
if [[ $got == kept ]]; then echo "ok   valkey starts as 999 on a root-owned volume, the key survived, and a restart works too"; else echo "FAIL valkey did not start or lost the key ('$got')"; "${DC[@]}" logs valkey 2>&1 | tail -3; exit 1; fi
