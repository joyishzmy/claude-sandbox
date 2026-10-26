#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/common.sh
. "$HERE/scripts/common.sh"
sandbox_ensure_docker

kill_switch=0
if [ "${1:-}" = "--kill-switch" ]; then
  kill_switch=1
fi

status=0
set +e
docker exec \
  -e EXPECT_TZ="$SANDBOX_TZ" \
  -e EXPECT_LOCALE="$SANDBOX_LOCALE" \
  -u "$SANDBOX_UID:$SANDBOX_GID" "$SANDBOX_CONTAINER" bash -c '
fail=0
echo "== date / timezone =="
date
zone="$(readlink /etc/localtime)"
text="$(cat /etc/timezone)"
echo "Zoneinfo: $zone | /etc/timezone: $text"
[ "$zone" = "/usr/share/zoneinfo/$EXPECT_TZ" ] || { echo "FAIL: wrong zoneinfo"; fail=1; }
[ "$text" = "$EXPECT_TZ" ] || { echo "FAIL: wrong /etc/timezone"; fail=1; }
echo
echo "== locale =="
locale | head -4
[ "$LANG" = "$EXPECT_LOCALE" ] || { echo "FAIL: wrong LANG"; fail=1; }
[ "$LC_ALL" = "$EXPECT_LOCALE" ] || { echo "FAIL: wrong LC_ALL"; fail=1; }
echo
echo "== DNS =="
getent hosts www.google.com || { echo "FAIL: DNS resolution failed"; fail=1; }
echo
echo "== egress =="
json="$(curl -fsS --max-time 12 https://ipinfo.io/json)" || fail=1
if [ -n "${json:-}" ]; then
  echo "$json"
  country="$(printf "%s" "$json" | jq -r ".country // empty")"
  ip_timezone="$(printf "%s" "$json" | jq -r ".timezone // empty")"
  echo "Country: $country | IP timezone: $ip_timezone"
  [ "$country" = "US" ] || { echo "FAIL: egress is not in the US"; fail=1; }
else
  echo "FAIL: egress lookup failed"
fi
exit "$fail"
'
status=$?
set -e

if [ "$kill_switch" = 1 ]; then
  restart_stack() {
    docker start "$SANDBOX_GATEWAY" >/dev/null 2>&1 || true
    sleep 4
    docker restart "$SANDBOX_CONTAINER" >/dev/null 2>&1 || true
  }
  trap restart_stack EXIT
  echo
  echo "== kill-switch check (gateway stops now) =="
  docker stop "$SANDBOX_GATEWAY" >/dev/null
  if docker exec "$SANDBOX_CONTAINER" curl -fsS --max-time 8 https://api.ipify.org >/dev/null 2>&1; then
    echo "FAIL: the workspace still has network access without the gateway" >&2
    status=1
  else
    echo "PASS: no network access while the gateway is down (no direct-IP leak)."
  fi
fi
exit "$status"
