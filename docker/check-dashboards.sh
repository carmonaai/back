#!/usr/bin/env bash
# The dashboards in grafana/dashboards, checked the way check-prometheus.sh checks the rules: valid JSON, a unique uid, unique panel ids, every panel that is not a row on the
# Prometheus datasource with an expression, every expression parsed by promtool in the pinned image, and every carmona_ metric a panel or rules.yml names found as a string
# literal in the Java of api/*/src/main (the names were read from there, so a metric renamed in Java fails here and not on the operator's screen). Needs jq and Docker, no stack.
# CI runs it before the build (ci.yaml); run it from anywhere.
#   bash docker/check-dashboards.sh
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "FAIL: jq is not installed (winget install jqlang.jq, or apt install jq)"; exit 1; }
bad=0
fail() { echo "FAIL: $1"; bad=1; }
shopt -s nullglob
files=(grafana/dashboards/*.json)
(( ${#files[@]} )) || { echo "FAIL: no dashboard in grafana/dashboards"; exit 1; }

# 1. The structure of each file. A collapsed row holds its panels inside it, so the panels are the top ones and the ones in a row.
for f in "${files[@]}"; do
  jq empty "$f" 2>/dev/null || { fail "$f is not valid JSON"; continue; }
  problems=$(jq -r '
    [.panels[] | recurse(.panels[]?)] as $p
    | (if (.uid | type) == "string" and .uid != "" then empty else "it has no uid" end),
      ($p[] | select(.id == null) | "a panel has no id: \(.title)"),
      ($p | group_by(.id)[] | select(length > 1) | "panel id \(.[0].id) is used \(length) times"),
      ($p[] | select(.type != "row" and .datasource.uid != "prometheus") | "panel \(.id) is not on the prometheus datasource"),
      ($p[] | select(.type != "row" and ([.targets[]? | select((.expr // "") != "")] | length) == 0) | "panel \(.id) has no expression")' "$f" | tr -d '\r')
  [[ -z $problems ]] || { sed "s#^#FAIL: $f: #" <<<"$problems"; bad=1; }
done
dup=$(jq -r '.uid' "${files[@]}" 2>/dev/null | tr -d '\r' | sort | uniq -d)
[[ -z $dup ]] || fail "two dashboards have the uid $dup"
(( bad == 0 )) || exit 1
echo "  SUCCESS: ${#files[@]} dashboards, each with its uid, unique panel ids, the prometheus datasource and an expression on every panel"

# 2. Every expression is a recording rule of one rules file that promtool, in the image compose.yaml pins, checks. The rule is named after the dashboard, the panel and the
# target, so its error says which. Grafana's own variables become what makes a valid selector. Nothing is written: the file goes in on stdin of a container that is removed.
IMG=$(sed -nE 's#^[[:space:]]*image: (prom/prometheus:[^[:space:]]+).*#\1#p' compose.yaml | head -1)
export MSYS_NO_PATHCONV=1
out=$(jq -s '
  {groups: [{name: "dashboards", rules: [
    .[] | .uid as $d | [.panels[] | recurse(.panels[]?)][] | .id as $id | .targets[]? | select((.expr // "") != "")
    | {record: ("panel_" + ($d | gsub("[^a-zA-Z0-9]"; "_")) + "_" + ($id | tostring) + "_" + ((.refId // "x") | gsub("[^a-zA-Z0-9]"; "_"))),
       expr: (.expr | gsub("[$]__(rate_interval|interval|range)"; "5m") | gsub("[$]job"; ".*"))}]}]}' "${files[@]}" |
  docker run --rm -i --entrypoint /bin/sh "$IMG" -c 'cat > /tmp/dashboards.yml && /bin/promtool check rules /tmp/dashboards.yml' 2>&1) || { echo "$out"; fail "promtool does not parse every panel expression"; }
(( bad == 0 )) || exit 1
echo "  SUCCESS: $(grep -oE '[0-9]+ rules found' <<<"$out" | cut -d' ' -f1) panel expressions parse"

# 3. Every carmona_ metric the panels and rules.yml name is a string literal of the Java, as it is or without its histogram suffix, or a recording rule of rules.yml. A name that ends in
# an underscore is a family named in prose (carmona_engine_*), not a metric.
src=(../api/*/src/main)
(( ${#src[@]} )) || { echo "FAIL: no api/*/src/main: are the submodules checked out?"; exit 1; }
literals=$(grep -rhoE --include='*.java' '"carmona_[a-z0-9_]+"' "${src[@]}" | tr -d '"\r' | sort -u)
while IFS=: read -r file name; do
  [[ $name == *_ ]] && continue
  base=$(sed -E 's/_(bucket|count|sum|max)$//' <<<"$name")
  grep -qxF -e "$name" -e "$base" <<<"$literals" || grep -qE "^[[:space:]]*- record: $name\$" prometheus/rules.yml || fail "$file names $name, which is no string literal in api/*/src/main"
done < <(grep -oHE 'carmona_[a-z0-9_]+' prometheus/rules.yml "${files[@]}" | sort -u)
(( bad == 0 )) || exit 1
echo "  SUCCESS: every carmona_ metric the panels and rules.yml name is a string literal in api/*/src/main"
