#!/usr/bin/env bash
# Rebuilds the build environment of a fresh cloud container. Idempotent: safe to run again.
# Prerequisite (cannot be scripted): each repo is attached with add_repo (push access) and cloned to /home/user/<name>.
set -euo pipefail
B=claude/peaceful-turing-14vw06
REPOS="account account-service auth auth-service organization organization-service usage usage-service inference-service billing billing-service batch-service gateway-service"

echo "== JDK 25 =="
if [ ! -x /usr/lib/jvm/java-25-openjdk-amd64/bin/javac ]; then
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-25-jdk-headless
fi

echo "== Docker daemon (installed but not started by default; Docker Hub rate-limits the shared IP, so use a mirror) =="
mkdir -p /etc/docker
echo '{ "registry-mirrors": ["https://mirror.gcr.io"] }' > /etc/docker/daemon.json
if ! docker info >/dev/null 2>&1; then
  nohup dockerd --storage-driver=overlay2 > /var/log/dockerd.log 2>&1 &
  for _ in $(seq 1 30); do sleep 1; docker info >/dev/null 2>&1 && break; done
fi
docker info >/dev/null 2>&1 || { echo "dockerd did not start; see /var/log/dockerd.log"; exit 1; }

echo "== test images (pulled by digest, so they list as <none>) =="
for img in \
  "postgres:17.11-bookworm@sha256:639ab7ceb90e13123085b741fb31ef493fba25463002f6da665352e7b534b652" \
  "valkey/valkey:9.0.6@sha256:63346cb24a61221e76bdf41acce99b3968a9fa83d8122144deab45394b27b4f2" \
  "axllent/mailpit:v1.31.4@sha256:b68349e3a014b90c5610bfb26b2ae36f3892d7b8cf25ee140c6c71c98d2fcf48"; do
  docker image inspect "$img" >/dev/null 2>&1 || docker pull -q "$img" >/dev/null
done

echo "== work branch in every cloned repo =="
for r in back $REPOS; do
  d=/home/user/$r
  [ -d "$d/.git" ] || { echo "  $r: NOT CLONED (attach with add_repo and clone first)"; continue; }
  if git -C "$d" ls-remote --exit-code origin "refs/heads/$B" >/dev/null 2>&1; then
    git -C "$d" fetch -q --depth=200 origin "$B"
    git -C "$d" checkout -q -B "$B" FETCH_HEAD
    echo "  $r: on $B @ $(git -C "$d" rev-parse --short HEAD)"
  else
    git -C "$d" checkout -q -B "$B" origin/main 2>/dev/null || git -C "$d" checkout -q -B "$B"
    echo "  $r: no remote work branch yet, started from main @ $(git -C "$d" rev-parse --short HEAD)"
  fi
done

echo "== build workspace /home/user/ws =="
mkdir -p /home/user/ws/api
cp /home/user/back/pom.xml /home/user/ws/pom.xml
for r in $REPOS; do [ -d /home/user/$r ] && ln -sfn /home/user/$r /home/user/ws/api/$r; done
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 PATH=/usr/lib/jvm/java-25-openjdk-amd64/bin:$PATH
( cd /home/user/ws && mvn -B -q -DskipTests install )
echo "== done. Test a module with: cd /home/user/ws && mvn -B -pl api/<module> verify =="
