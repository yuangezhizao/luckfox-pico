#!/bin/bash
set -euo pipefail

curl --fail --location --max-redirs 3 --proto "=https" --tlsv1.2 --retry 3 --retry-max-time 120 --connect-timeout 15 --max-time 90 --create-dirs --output "$HOME/.cursor/skills/grilling/SKILL.md" "https://raw.githubusercontent.com/mattpocock/skills/85f83d3fde1d3a90d5c9a657f6998c79a6c37308/skills/productivity/grilling/SKILL.md"
export DEBIAN_FRONTEND=noninteractive
apt-get update
# --force-confold: the luckfox FROM image ships a modified sshd_config; upgrading openssh-server otherwise prompts on stdin. DEBIAN_FRONTEND alone is not enough.
apt-get install -y -o Dpkg::Options::=--force-confold openssh-server
rm -rf /var/lib/apt/lists/*

# Rotate host keys once per Build snapshot; the stamp keeps a later install on the same snapshot from changing fingerprints.
hostkey_stamp=/etc/ssh/.cursor-hostkeys-generated
if [[ ! -e "$hostkey_stamp" ]]; then
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A
  : > "$hostkey_stamp"
  chmod 0644 "$hostkey_stamp"
fi
