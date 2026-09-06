#!/usr/bin/env bash
set -euo pipefail
image=${1:?Usage: bash tests/chrony.sh IMAGE:TAG}
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
container=''
cleanup() {
  if [[ -n $container ]]; then docker rm -f "$container" >/dev/null; fi
}
trap cleanup EXIT

options=(--network none --cap-drop ALL
  --sysctl net.ipv4.ip_unprivileged_port_start=0 --read-only
  --tmpfs /run/chrony:rw,uid=65532,gid=65532,mode=0750
  --tmpfs /var/lib/chrony:rw,uid=65532,gid=65532,mode=0750
  --tmpfs /tmp:rw,mode=1777)

[[ $(docker image inspect --format '{{.Config.User}}' "$image") == 65532:65532 ]]
docker run --rm --network none --cap-drop ALL "$image" -v
docker run --rm --network none --cap-drop ALL "$image" -p -f /etc/chrony.conf
docker run --rm --network none --cap-drop ALL \
  --mount "type=bind,src=$repo/images/chrony/chrony.conf,dst=/etc/chrony.conf,readonly" \
  "$image" -p -f /etc/chrony.conf

tracking() {
  for ((attempt=0; attempt<30; attempt++)); do
    if docker exec "$container" /bin/chronyc -h /run/chrony/chronyd.sock tracking; then return; fi
    sleep 0.2
  done
  docker logs "$container" >&2
  return 1
}

container=$(docker run -d "${options[@]}" "$image")
tracking
docker logs "$container"
docker rm -f "$container" >/dev/null
container=''

# This isolated local source makes the protocol test independent of upstreams.
# Production defaults intentionally do not advertise an unsynchronized clock.
container=$(docker run -d "${options[@]}" "$image" -d -x -U -u chrony \
  'local stratum 10' 'allow 127.0.0.1' \
  'pidfile /run/chrony/chronyd.pid' \
  'bindcmdaddress /run/chrony/chronyd.sock' 'cmdport 0')
tracking
docker exec "$container" /bin/chronyd -Q -t 10 'server 127.0.0.1 iburst'
docker stop --time 5 "$container" >/dev/null
[[ $(docker inspect --format '{{.State.ExitCode}}' "$container") == 0 ]]
printf 'chrony startup, NTP response, and graceful shutdown passed\n'
