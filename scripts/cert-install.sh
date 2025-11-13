#!/bin/bash

set -euo pipefail

log() {
  echo "==> $(date -u +%FT%T%Z) $*"
}

# Load configuration if present
if [ -f /opt/oci-hpc/ood.env ]; then
  set -a
  . /opt/oci-hpc/ood.env
  set +a
fi

if [ -z "${OOD_DNS:-}" ]; then
  echo "Error: OOD_DNS environment variable is not set."
  exit 1
fi

CERTBOT_EMAIL="${CERTBOT_EMAIL:-${OOD_USER_EMAIL:-}}"
if [ -z "$CERTBOT_EMAIL" ]; then
  echo "Error: CERTBOT_EMAIL or OOD_USER_EMAIL must be set for certbot registration."
  exit 1
fi

ensure_certbot() {
  if command -v certbot >/dev/null 2>&1; then return 0; fi

  # Try snapd path
  if ! command -v snap >/dev/null 2>&1; then
    sudo dnf install -y epel-release || true
    sudo dnf install -y snapd || true
    sudo systemctl enable --now snapd.socket || true
    [ -e /snap ] || sudo ln -s /var/lib/snapd/snap /snap || true
  fi
  if command -v snap >/dev/null 2>&1; then
    sudo snap install core || true
    sudo snap install certbot --classic || true
    if [ -x /snap/bin/certbot ]; then
      sudo ln -sf /snap/bin/certbot /usr/bin/certbot || true
    fi
  fi
  if command -v certbot >/dev/null 2>&1; then return 0; fi

  # Fallback: pip install
  if command -v /usr/bin/python3 >/dev/null 2>&1; then
    sudo /usr/bin/python3 -m pip install --upgrade pip || true
    sudo /usr/bin/python3 -m pip install certbot || true
    if [ -x /usr/local/bin/certbot ]; then
      sudo ln -sf /usr/local/bin/certbot /usr/bin/certbot || true
    fi
  fi

  command -v certbot >/dev/null 2>&1
}

log "Ensuring certbot is installed"
if ! ensure_certbot; then
  echo "Error: certbot installation failed."
  exit 1
fi
CERTBOT_BIN="$(command -v certbot)"

# Stop Apache to free ports for standalone challenge
log "Stopping httpd before certificate issuance"
sudo systemctl stop httpd || sudo systemctl stop apache2 || true

# Issue or renew certificate for ${OOD_DNS}
log "Requesting/renewing certificate with certbot for ${OOD_DNS}"
if [ -d "/etc/letsencrypt/live/${OOD_DNS}" ]; then
  # Try a quiet renew if cert already exists
  "$CERTBOT_BIN" renew -q || "$CERTBOT_BIN" certonly --standalone --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --cert-name "$OOD_DNS" -d "$OOD_DNS"
else
  "$CERTBOT_BIN" certonly --standalone --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --cert-name "$OOD_DNS" -d "$OOD_DNS"
fi

# Configure auto-renewal via crontab (idempotent)
log "Configuring certbot auto-renewal in crontab"
if ! sudo grep -q "certbot renew -q" /etc/crontab; then
  echo "0 0,12 * * * root sleep \$((RANDOM % 3600)) && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null
fi

# Ensure deploy hook to reload Apache after successful renewal
log "Installing certbot deploy hook to reload Apache"
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/00-reload-httpd > /dev/null <<'EOF'
#!/bin/bash
systemctl reload httpd 2>/dev/null || systemctl restart httpd 2>/dev/null || true
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/00-reload-httpd

log "Certificate setup completed for ${OOD_DNS}"

