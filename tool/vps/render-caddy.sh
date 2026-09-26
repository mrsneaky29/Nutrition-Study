#!/usr/bin/env bash
set -euo pipefail

api_host=${1:?Usage: render-caddy.sh API_HOST ADMIN_HOST ADMIN_WEB_ROOT}
admin_host=${2:?Usage: render-caddy.sh API_HOST ADMIN_HOST ADMIN_WEB_ROOT}
admin_root=${3:?Usage: render-caddy.sh API_HOST ADMIN_HOST ADMIN_WEB_ROOT}
host_re='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
for host in "$api_host" "$admin_host"; do
  [[ $host =~ $host_re && $host != *..* ]] || { echo "Invalid DNS hostname: $host" >&2; exit 2; }
done
[[ $api_host != "$admin_host" ]] || { echo "API and admin hostnames must differ" >&2; exit 2; }
[[ $admin_root == /* ]] || { echo "Admin web root must be an absolute path" >&2; exit 2; }
cat <<EOF
$api_host {
  encode zstd gzip
  reverse_proxy 127.0.0.1:8787 {
    header_up X-Forwarded-Proto https
    header_up X-Forwarded-For {remote_host}
    header_up X-Real-IP {remote_host}
  }
}

$admin_host {
  encode zstd gzip
  root * $admin_root
  try_files {path} /index.html
  file_server
}
EOF
