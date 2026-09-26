#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
fail=0
need() { if command -v "$1" >/dev/null 2>&1; then printf 'OK  command: %s\n' "$1"; else printf 'MISS command: %s\n' "$1"; fail=1; fi; }
need bash
need tar
need sha256sum
need curl
need dart
need systemctl
need awk
for p in /etc/os-release /opt /var/lib; do
  if [[ -e "$p" ]]; then printf 'OK  path: %s\n' "$p"; else printf 'MISS path: %s\n' "$p"; fail=1; fi
done
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  printf 'OS: %s %s\n' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-}"
  if [[ ${ID:-} != ubuntu ]]; then printf 'WARN expected Ubuntu; detected %s\n' "${ID:-unknown}"; fi
fi
if command -v free >/dev/null 2>&1; then free -h | awk 'NR==1 || NR==2'; else printf 'WARN free command unavailable\n'; fi
if command -v df >/dev/null 2>&1; then df -h "$ROOT" 2>/dev/null || df -h /opt; fi
if command -v ss >/dev/null 2>&1; then
  for port in 80 443 8787; do
    if ss -lnt "( sport = :$port )" | awk 'NR>1 {found=1} END {exit !found}'; then printf 'BUSY listening TCP port %s\n' "$port"; else printf 'OK  TCP port %s not listening locally\n' "$port"; fi
  done
else
  printf 'WARN ss unavailable; cannot check local listening ports\n'
fi
if [[ -d "$ROOT" ]]; then
  [[ -w "$ROOT" ]] && printf 'OK  writable deployment root: %s\n' "$ROOT" || { printf 'MISS not writable deployment root: %s\n' "$ROOT"; fail=1; }
else
  printf 'WARN deployment root does not exist yet: %s\n' "$ROOT"
fi
if [[ $fail -ne 0 ]]; then exit 1; fi
printf 'Preflight checks passed (warnings may still need review).\n'
