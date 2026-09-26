#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
STATE=${VPS_STATE_DIR:-/var/lib/plus5-vps/state}
ETC=${VPS_ETC_DIR:-/etc/plus5-vps}
ACCOUNT=${VPS_ACCOUNT:-plus5-vps}

install_deps=0
install_service=0

show_help() {
  cat <<'EOF'
Usage: sudo bash install-host.sh [OPTIONS]

Initializes the system layout and service account for the +5 Local Sync API.

Options:
  --install-deps     Install official Dart SDK and Caddy repositories and packages (Ubuntu/Debian)
  --install-service  Install systemd service unit to /etc/systemd/system/plus5-vps.service
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-deps)
      install_deps=1
      shift
      ;;
    --install-service)
      install_service=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 2
      ;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "Error: Run this host installation script as root (e.g., sudo bash tool/vps/install-host.sh)." >&2
  exit 1
fi

if [[ $install_deps -eq 1 ]]; then
  echo "==> Installing system dependencies (Ubuntu/Debian)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl tar coreutils openssl ufw apt-transport-https gpg

  # Install Dart SDK if missing
  if ! command -v dart >/dev/null 2>&1; then
    echo "==> Configuring official Dart SDK repository..."
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg --yes
    echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" > /etc/apt/sources.list.d/dart_stable.list
    apt-get update -y
    apt-get install -y dart
  else
    echo "==> Dart SDK is already installed: $(command -v dart)"
  fi

  # Install Caddy if missing
  if ! command -v caddy >/dev/null 2>&1; then
    echo "==> Configuring official Caddy repository..."
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
    curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -y
    apt-get install -y caddy
  else
    echo "==> Caddy is already installed: $(command -v caddy)"
  fi
else
  echo "==> Checking prerequisites..."
  dart_status="NOT INSTALLED"
  caddy_status="NOT INSTALLED"
  if command -v dart >/dev/null 2>&1; then dart_status="INSTALLED ($(command -v dart))"; fi
  if command -v caddy >/dev/null 2>&1; then caddy_status="INSTALLED ($(command -v caddy))"; fi
  echo "    Dart SDK: $dart_status"
  echo "    Caddy:    $caddy_status"
  if [[ "$dart_status" == "NOT INSTALLED" || "$caddy_status" == "NOT INSTALLED" ]]; then
    echo "    NOTE: Run with '--install-deps' to install Dart and Caddy automatically, or install them manually."
  fi
fi

echo "==> Creating service account '$ACCOUNT'..."
if ! id "$ACCOUNT" >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/plus5-vps --create-home --shell /usr/sbin/nologin "$ACCOUNT"
  echo "    Created system user '$ACCOUNT'."
else
  echo "    System user '$ACCOUNT' already exists."
fi

echo "==> Initializing directory layout..."
install -d -o root -g root -m 0755 "$ROOT" "$ROOT/releases"
install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 "$STATE" "$STATE/.local_data"
install -d -o root -g "$ACCOUNT" -m 0750 "$ETC"

if [[ ! -e "$ETC/local-sync.env" ]]; then
  install -o root -g "$ACCOUNT" -m 0640 /dev/null "$ETC/local-sync.env"
  echo "    Created template $ETC/local-sync.env (mode 0640, root:$ACCOUNT)."
  echo "    Generate secrets using: sudo bash tool/vps/generate-credentials.sh $ETC/local-sync.env"
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
service_src="$script_dir/systemd/plus5-vps.service"
if [[ -f "$service_src" ]]; then
  if [[ $install_service -eq 1 || -d /etc/systemd/system ]]; then
    echo "==> Installing systemd service unit to /etc/systemd/system/plus5-vps.service..."
    install -o root -g root -m 0644 "$service_src" /etc/systemd/system/plus5-vps.service
    if command -v systemctl >/dev/null 2>&1; then
      systemctl daemon-reload
      echo "    Ran systemctl daemon-reload."
    fi
  fi
fi

echo "==> Host initialization complete."
echo "    Next steps:"
echo "    1. Generate credentials:  sudo bash tool/vps/generate-credentials.sh"
echo "    2. Run preflight checks:  bash tool/vps/preflight.sh"
echo "    3. Import release:        sudo bash tool/vps/import-release.sh /path/to/release.tar.gz"
echo "    4. Configure Caddy:       sudo bash tool/vps/render-caddy.sh api.domain admin.domain /opt/plus5-vps/current/build/admin_web > /etc/caddy/Caddyfile"
