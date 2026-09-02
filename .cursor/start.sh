#!/bin/bash
set -euo pipefail

dump_tailscaled_log() {
  if [[ -r /var/log/tailscaled.log ]]; then
    printf '%s\n' '--- last 50 lines of /var/log/tailscaled.log ---' >&2
    tail -n 50 /var/log/tailscaled.log >&2 || true
    printf '%s\n' '--- end /var/log/tailscaled.log ---' >&2
  else
    printf '%s\n' 'tailscaled log not readable: /var/log/tailscaled.log' >&2
  fi
}

: "${TAILSCALE_AUTHKEY:?TAILSCALE_AUTHKEY is required}"
: "${SSH_AUTHORIZED_KEYS:?SSH_AUTHORIZED_KEYS is required}"
printf '%s\n' 'start: required secrets are present'

conversation_id=""
bcid_deadline=$(( $(date +%s) + 30 ))
while [[ "$(date +%s)" -lt "$bcid_deadline" ]]; do
  conversation_id="${CURSOR_CONVERSATION_ID-}"
  if [[ -z "${conversation_id}" && -r /run/agent-store-fuse/self-store-id ]]; then
    conversation_id="$(tr -d '\n\r' < /run/agent-store-fuse/self-store-id)"
  fi
  if [[ -n "${conversation_id}" ]]; then
    break
  fi
  sleep 1
done
if [[ -z "${conversation_id}" ]]; then
  printf '%s\n' 'CURSOR_CONVERSATION_ID or /run/agent-store-fuse/self-store-id was not available within 30 seconds' >&2
  exit 1
fi
printf '%s\n' "bcid: ready (${conversation_id})"

printf '%s\n' \
  'net.ipv4.ip_forward = 1' \
  'net.ipv6.conf.all.forwarding = 1' \
  > /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf
printf '%s\n' 'sysctl: forwarding enabled'

install -d -m 0755 -o root -g root /var/run/tailscale
tailscaled \
  --outbound-http-proxy-listen=localhost:1054 \
  --socks5-server=localhost:1055 \
  > /var/log/tailscaled.log 2>&1 &
tailscaled_pid=$!
trap 'kill "$tailscaled_pid" 2>/dev/null || true' EXIT
ready=0
deadline=$(( $(date +%s) + 30 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -S /var/run/tailscale/tailscaled.sock ] && timeout 1s tailscale status --json >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$tailscaled_pid" 2>/dev/null; then
    printf '%s\n' 'tailscaled exited before LocalAPI became ready' >&2
    dump_tailscaled_log
    exit 1
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  printf '%s\n' 'tailscaled LocalAPI was not ready within 30 seconds' >&2
  dump_tailscaled_log
  exit 1
fi
printf '%s\n' "tailscaled: LocalAPI ready pid=${tailscaled_pid}"

agent_id="${conversation_id#bc-}"
agent_suffix="${agent_id%%-*}"
if [ -z "$agent_suffix" ]; then
  printf '%s\n' 'conversation id produced an empty hostname suffix' >&2
  exit 1
fi
if ! tailscale up \
  --timeout=60s \
  --auth-key="$TAILSCALE_AUTHKEY" \
  --hostname="cursor-agent-${agent_suffix}" \
  --ssh=false \
  --advertise-routes=172.30.0.0/24 \
  --advertise-exit-node
then
  printf '%s\n' 'tailscale up: failed' >&2
  dump_tailscaled_log
  exit 1
fi
ts_json="$(tailscale status --json)"
ts_hostname="$(printf '%s' "$ts_json" | jq -r '.Self.HostName // empty')"
ts_backend="$(printf '%s' "$ts_json" | jq -r '.BackendState // empty')"
ts_dns="$(printf '%s' "$ts_json" | jq -r '.Self.DNSName // empty')"
ts_ipv4="$(tailscale ip -4)"
if [ -d /sys/class/net/tailscale0 ]; then
  ts_iface=present
else
  ts_iface=missing
  printf '%s\n' 'tailscale: tailscale0 missing' >&2
fi
printf '%s\n' "tailscale up: done hostname=${ts_hostname} BackendState=${ts_backend} ipv4=${ts_ipv4} MagicDNS=${ts_dns} tailscale0=${ts_iface}"
tailscale version
tailscale version --daemon
tailscale status

tailscale serve reset
tailscale serve --bg --tcp 5901 tcp://127.0.0.1:5901
tailscale serve --bg --tcp 1054 tcp://127.0.0.1:1054
tailscale serve --bg --tcp 1055 tcp://127.0.0.1:1055
printf '%s\n' 'tailscale serve: 5901/1054/1055'

install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 0600 /home/ubuntu/.ssh/authorized_keys
printf '%s\n' 'ssh: authorized_keys written'

install -d -m 0755 -o root -g root /etc/ssh/sshd_config.d
printf '%s\n' \
  'PasswordAuthentication no' \
  'PermitRootLogin no' \
  > /etc/ssh/sshd_config.d/00-cloud-agent.conf
install -d -m 0755 -o root -g root /run/sshd
/usr/sbin/sshd -t
/usr/sbin/sshd -T | grep -Fx 'passwordauthentication no'
/usr/sbin/sshd -T | grep -Fx 'permitrootlogin no'
/usr/sbin/sshd
/usr/sbin/sshd -T | grep -Fx 'passwordauthentication no'
/usr/sbin/sshd -T | grep -Fx 'permitrootlogin no'
ss -H -ltn | awk '$4 == "0.0.0.0:22" { found=1 } END { exit !found }'
trap - EXIT
printf '%s\n' 'sshd: listening on 0.0.0.0:22'
printf '%s\n' 'start: complete'
