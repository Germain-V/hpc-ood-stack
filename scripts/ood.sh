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

# Ensure OOD local user (fallback when 'cluster' CLI is unavailable)
ensure_ood_user() {
  log "Ensuring OOD user exists: $OOD_USERNAME"
  if command -v cluster >/dev/null 2>&1; then
    if id "$OOD_USERNAME" >/dev/null 2>&1; then
      # User already exists; avoid invoking cluster add to prevent interactive prompts
      :
    else
      sudo cluster user add "$OOD_USERNAME" -n "$OOD_USERNAME" -p "$OOD_PASSWORD" --nossh || true
    fi
  fi
  if ! id "$OOD_USERNAME" >/dev/null 2>&1; then
    # Create OS user with home and default bash shell
    sudo useradd -m -s /bin/bash "$OOD_USERNAME" || true
  fi
  echo "$OOD_USERNAME:$OOD_PASSWORD" | sudo chpasswd || true
  # SSH setup similar to cluster tool (use absolute paths to avoid tilde expansion quirks)
  sudo -u "$OOD_USERNAME" mkdir -p "/home/$OOD_USERNAME/.ssh" || true
  sudo -u "$OOD_USERNAME" chmod 700 "/home/$OOD_USERNAME/.ssh" || true
  # Generate an SSH key only if it doesn't exist or is empty; if empty, remove first to avoid ssh-keygen prompt
  if ! sudo -u "$OOD_USERNAME" test -s "/home/$OOD_USERNAME/.ssh/id_rsa"; then
    sudo -u "$OOD_USERNAME" rm -f "/home/$OOD_USERNAME/.ssh/id_rsa" "/home/$OOD_USERNAME/.ssh/id_rsa.pub" || true
    sudo -u "$OOD_USERNAME" ssh-keygen -t rsa -b 2048 -q -N "" -f "/home/$OOD_USERNAME/.ssh/id_rsa" || true
  fi
  sudo -u "$OOD_USERNAME" cp -f "/home/$OOD_USERNAME/.ssh/id_rsa.pub" "/home/$OOD_USERNAME/.ssh/authorized_keys" || true
  sudo -u "$OOD_USERNAME" chmod 600 "/home/$OOD_USERNAME/.ssh/authorized_keys" || true
}

# Check if OOD_DNS environment variable exists
if [ -z "${OOD_DNS}" ]; then
    echo "Error: OOD_DNS environment variable is not set. Public IP is required."
    exit 1
fi

if [ -z "${OOD_USERNAME}" ]; then
    echo "Error: OOD_USERNAME environment variable is not set. Username is required."
    exit 1
fi
log "Starting OOD setup for ${OOD_DNS} (user: ${OOD_USERNAME})"
CRYPTO_PASSPHRASE=$(openssl rand -hex 40)

# Permissions
log "Setting SELinux to permissive (setenforce 0)"
sudo setenforce 0 || true

# Fast path: if Open OnDemand is already installed, only (re)configure portal and Grafana
if rpm -q ondemand >/dev/null 2>&1; then
  log "OOD already installed. Applying configuration updates only (fast path)."

  # Create OOD portal config
  log "Writing /etc/ood/config/ood_portal.yml"
  sudo cat << EOF > /etc/ood/config/ood_portal.yml
---
servername: ${OOD_DNS}
# Enable reverse proxy endpoints for node and rnode
# Note: do not include ^ or $ anchors here; the portal generator embeds this in a larger regex
host_regex: '(localhost|127\.0\.0\.1)'
node_uri: '/node'
rnode_uri: '/rnode'
# Use OIDC authentication
auth:
  - "AuthType openid-connect"
  - "Require valid-user"
# Use OIDC logout
logout_redirect: "/oidc?logout=https%3A%2F%2F${OOD_DNS}%2F"
oidc_uri: "/oidc"
oidc_provider_metadata_url: "${IDCS_URL}/.well-known/openid-configuration"
oidc_client_id: "${CLIENT_ID}"
oidc_client_secret: "${CLIENT_SECRET}"
oidc_remote_user_claim: "sub"
oidc_scope: "urn:opc:idm:t.user.me openid email"
oidc_session_inactivity_timeout: 28800
oidc_session_max_duration: 28800
oidc_state_max_number_of_cookies: "10 true"
oidc_settings:
  OIDCPassIDTokenAs: "serialized"
  OIDCPassRefreshToken: "On"
  OIDCPassClaimsAs: "environment"
  OIDCStripCookies: "mod_auth_openidc_session mod_auth_openidc_session_chunks mod_auth_openidc_session_0 mod_auth_openidc_session_1"
  OIDCResponseType: "code"

ssl:
  - 'SSLCertificateFile "/etc/letsencrypt/live/${OOD_DNS}/fullchain.pem"'
  - 'SSLCertificateKeyFile "/etc/letsencrypt/live/${OOD_DNS}/privkey.pem"'
EOF

  # Create Apache OIDC config
  log "Writing /etc/httpd/conf.d/auth_openidc.conf"
  sudo cat << EOF > /etc/httpd/conf.d/auth_openidc.conf
# Apache auth_openidc.conf
OIDCProviderMetadataURL ${IDCS_URL}/.well-known/openid-configuration
OIDCClientID ${CLIENT_ID}
OIDCClientSecret ${CLIENT_SECRET}
OIDCRedirectURI https://${OOD_DNS}/oidc
OIDCCryptoPassphrase ${CRYPTO_PASSPHRASE}
OIDCScope "urn:opc:idm:t.user.me openid email"
EOF

  # Update Apache config based on ood_portal.yml file
  log "Running ood-portal-generator to update Apache portal config"
  /opt/ood/ood-portal-generator/sbin/update_ood_portal

  # Ensure Apache unsets Origin headers for Grafana proxied path to avoid CORS rejection
  log "Installing Apache snippet to unset Origin for Grafana path"
  sudo tee /etc/httpd/conf.d/ood-grafana-origin-unset.conf > /dev/null <<'EOF'
<LocationMatch "^/node/(localhost|127\.0\.0\.1)/3000(/.*)?$">
  RequestHeader unset Origin
  RequestHeader unset Access-Control-Request-Method
  RequestHeader unset Access-Control-Request-Headers
</LocationMatch>
EOF

  # Ensure TLS certificate is issued/renewed
  log "Ensuring TLS certificate via cert-install.sh (fast path)"
  if [ -x "./cert-install.sh" ]; then
    OOD_USER_EMAIL="${OOD_USER_EMAIL:-${ood_user_email:-}}" ./cert-install.sh || true
  elif [ -x "/opt/oci-hpc/scripts/cert-install.sh" ]; then
    OOD_USER_EMAIL="${OOD_USER_EMAIL:-${ood_user_email:-}}" /opt/oci-hpc/scripts/cert-install.sh || true
  else
    log "cert-install.sh not found in current dir or /opt/oci-hpc/scripts; skipping in fast path"
  fi

  # Ensure OOD user exists even in fast path
  ensure_ood_user

  # Ensure cluster app env and cluster config exist
  log "Ensuring /etc/ood/config/apps/shell/env exists"
  sudo mkdir -p /etc/ood/config/apps/shell
  sudo tee /etc/ood/config/apps/shell/env > /dev/null << 'EOF'
OOD_SSHHOST_ALLOWLIST="localhost"
OOD_CLUSTERS="/etc/ood/config/clusters.d"
EOF
  log "Ensuring /etc/ood/config/clusters.d/hpc_cluster.yml exists"
  sudo mkdir -p /etc/ood/config/clusters.d
  sudo tee /etc/ood/config/clusters.d/hpc_cluster.yml > /dev/null << 'EOF'
---
v2:
  metadata:
    title: "OCI HPC"
  login:
    host: "localhost"
  job:
    adapter: "slurm"
    cluster: "cluster"
    bin: "/usr/bin"
    conf: "/etc/slurm/slurm.conf"

EOF

  # Restart Apache service
  log "Restarting Apache (httpd)"
  sudo systemctl restart httpd || sudo systemctl restart apache2 || true

  # Configure SELinux for OOD (persistent contexts + policy)
  log "Configuring SELinux contexts and policy for OOD"
  sudo tee -a /etc/selinux/targeted/contexts/files/file_contexts.local > /dev/null <<'EOC'
/run/ondemand-nginx(/.*)?        system_u:object_r:httpd_var_run_t:s0
/var/run/ondemand-nginx(/.*)?    system_u:object_r:httpd_var_run_t:s0
/var/lib/ondemand-nginx(/.*)?    system_u:object_r:httpd_sys_rw_content_t:s0
/var/log/ondemand-nginx(/.*)?    system_u:object_r:httpd_sys_rw_content_t:s0
EOC
  sudo restorecon -Rv /run/ondemand-nginx /var/run/ondemand-nginx /var/lib/ondemand-nginx /var/log/ondemand-nginx /etc/ood /var/www/ood || true
  sudo setsebool -P httpd_can_network_connect on || true
  # Install minimal policy to allow httpd to connect to OOD UDS socket
  sudo bash -lc 'cat > /root/ood_httpd_sock.te <<"EOT"
module ood_httpd_sock 1.1;

require {
  type httpd_t;
  type httpd_var_run_t;
  class sock_file connectto;
}

allow httpd_t httpd_var_run_t:sock_file connectto;
EOT' && \
  sudo semodule -r ood_httpd_sock || true && \
  sudo dnf install -y checkpolicy policycoreutils-python-utils || true && \
  sudo checkmodule -M -m -o /root/ood_httpd_sock.mod /root/ood_httpd_sock.te && \
  sudo semodule_package -o /root/ood_httpd_sock.pp -m /root/ood_httpd_sock.mod && \
  sudo semodule -i /root/ood_httpd_sock.pp || true

  # Ensure httpd setrlimit boolean for PAM limits and enable auditd
  sudo setsebool -P httpd_setrlimit on || true
  sudo restorecon -v /usr/sbin/unix_chkpwd || true
  sudo systemctl enable --now auditd || true

  # Create tmpfiles rule to pre-create /run/ondemand-nginx at boot
  sudo tee /etc/tmpfiles.d/ondemand-nginx.conf > /dev/null <<'EOT'
d /run/ondemand-nginx 0755 root root -
EOT
  sudo systemd-tmpfiles --create /etc/tmpfiles.d/ondemand-nginx.conf || true

  # Create a one-shot restorecon service for OOD paths at boot
  sudo tee /etc/systemd/system/restorecon-ood.service > /dev/null <<'EOT'
[Unit]
Description=Restore SELinux contexts for OOD
After=local-fs.target systemd-tmpfiles-setup.service

[Service]
Type=oneshot
ExecStart=/sbin/restorecon -Rv /run/ondemand-nginx /var/run/ondemand-nginx /var/lib/ondemand-nginx /var/log/ondemand-nginx /etc/ood /var/www/ood

[Install]
WantedBy=multi-user.target
EOT
  sudo systemctl daemon-reload || true
  sudo systemctl enable --now restorecon-ood.service || true

  # If Grafana is installed, configure for OOD subpath and create OOD app entry
  if systemctl list-unit-files | grep -q grafana-server.service || [ -f /etc/grafana/grafana.ini ]; then
    log "Configuring Grafana for OOD subpath in /etc/grafana/grafana.ini"
    GRAFANA_INI="/etc/grafana/grafana.ini"

    sudo sed -i -E "/^\[server\]/,/^\[/{s|^;?\s*root_url\s*=.*$|root_url = https://${OOD_DNS}/node/localhost/3000/|}" "$GRAFANA_INI" || true
    sudo sed -i -E "/^\[server\]/,/^\[/{s|^;?\s*serve_from_sub_path\s*=.*$|serve_from_sub_path = true|}" "$GRAFANA_INI" || true
    if ! grep -q "^root_url\s*=\s*https://${OOD_DNS}/node/localhost/3000/" "$GRAFANA_INI"; then
      sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[server]
root_url = https://${OOD_DNS}/node/localhost/3000/
serve_from_sub_path = true
EOT"
    fi

    sudo sed -i -E "/^\[security\]/,/^\[/{s|^;?\s*allow_embedding\s*=.*$|allow_embedding = true|}" "$GRAFANA_INI" || true
    if ! awk 'BEGIN{IGNORECASE=1} /^\[security\]/{insec=1} insec && /^allow_embedding/{found=1} END{exit(found?0:1)}' "$GRAFANA_INI"; then
      sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[security]
allow_embedding = true
cookie_samesite = none
cookie_secure = true
EOT"
    fi

    # Ensure [cors] settings to allow OOD origin
    sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*enabled\s*=.*$|enabled = true|}" "$GRAFANA_INI" || true
    sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_origins\s*=.*$|allow_origins = https://${OOD_DNS}|}" "$GRAFANA_INI" || true
    sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_credentials\s*=.*$|allow_credentials = true|}" "$GRAFANA_INI" || true
    sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_methods\s*=.*$|allow_methods = GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS|}" "$GRAFANA_INI" || true
    sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_headers\s*=.*$|allow_headers = Accept, Authorization, Content-Type, Origin, User-Agent, X-Requested-With, X-Grafana-Org-Id|}" "$GRAFANA_INI" || true
    if ! awk 'BEGIN{IGNORECASE=1} /^\[cors\]/{found=1} END{exit(found?0:1)}' "$GRAFANA_INI"; then
      sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[cors]
enabled = true
allow_origins = https://${OOD_DNS}
allow_credentials = true
allow_methods = GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
allow_headers = Accept, Authorization, Content-Type, Origin, User-Agent, X-Requested-With, X-Grafana-Org-Id
EOT"
    fi

    log "Ensuring OOD app manifest for Grafana exists"
    sudo mkdir -p /var/www/ood/apps/sys/oci_grafana
    sudo tee /var/www/ood/apps/sys/oci_grafana/manifest.yml > /dev/null << 'EOM'
---
name: Grafana
category: Monitoring
description: Grafana dashboards
icon: fas://chart-line
url: /node/localhost/3000/
EOM

    log "Restarting grafana-server and reloading httpd"
    sudo systemctl restart grafana-server || true
    sudo systemctl reload httpd || sudo systemctl restart httpd
  fi

  log "Fast path completed."
  exit 0
fi
# Allow Apache to run HTTP requests on the background
sudo setsebool -P httpd_can_network_connect 1

# Install EPEL repository (no full system update)
log "Installing epel-release"
timeout --foreground 8m sudo dnf install -y epel-release || true
# Enable modules needed by OOD
log "Enabling module streams ruby:3.1 nodejs:18"
timeout --foreground 5m sudo dnf module enable -y ruby:3.1 nodejs:18 || true

# Enable CodeReady and Developer Toolset repositories
log "Enabling OL8 codeready/distro/developer repositories"
timeout --foreground 2m sudo dnf config-manager --enable ol8_codeready_builder ol8_distro_builder ol8_developer || true

# Install Open OnDemand
# Pin to OOD 3.1 which previously completed reliably in your environment
log "Installing OOD 3.1 repo RPM"
timeout --foreground 4m sudo dnf install -y https://yum.osc.edu/ondemand/3.1/ondemand-release-web-3.1-1.el8.noarch.rpm || true
log "Installing packages: rclone ondemand"
timeout --foreground 10m sudo dnf install -y rclone ondemand || true

# Install Apache OIDC module
log "Installing mod_auth_openidc"
timeout --foreground 5m sudo dnf install -y mod_auth_openidc || true
sudo systemctl enable httpd

# Configure firewall
sudo firewall-cmd --zone=public --permanent --add-port=80/tcp
sudo firewall-cmd --zone=public --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# Install Python Pyenv dependencies (best effort)
log "Installing development dependencies (git, sqlite-devel, etc.)"
timeout --foreground 6m sudo dnf install -y git sqlite-devel readline-devel libffi-devel bzip2-devel || true

# Ensure TLS certificate is issued/renewed
log "Ensuring TLS certificate via cert-install.sh"
if [ -x "./cert-install.sh" ]; then
  OOD_USER_EMAIL="${OOD_USER_EMAIL:-${ood_user_email:-}}" ./cert-install.sh || true
elif [ -x "/opt/oci-hpc/scripts/cert-install.sh" ]; then
  OOD_USER_EMAIL="${OOD_USER_EMAIL:-${ood_user_email:-}}" /opt/oci-hpc/scripts/cert-install.sh || true
else
  log "cert-install.sh not found; ensuring certbot is installed (snap/pip fallback)"
  if ! command -v certbot >/dev/null 2>&1; then
    if ! command -v snap >/dev/null 2>&1; then
      timeout --foreground 3m sudo dnf install -y epel-release || true
      timeout --foreground 5m sudo dnf install -y snapd || true
      sudo systemctl enable --now snapd.socket || true
      [ -e /snap ] || sudo ln -s /var/lib/snapd/snap /snap || true
    fi
    if command -v snap >/dev/null 2>&1; then
      sudo snap install core || true
      sudo snap install certbot --classic || true
      [ -x /snap/bin/certbot ] && sudo ln -sf /snap/bin/certbot /usr/bin/certbot || true
    fi
    if ! command -v certbot >/dev/null 2>&1; then
      if command -v /usr/bin/python3 >/dev/null 2>&1; then
        sudo /usr/bin/python3 -m pip install --upgrade pip || true
        sudo /usr/bin/python3 -m pip install certbot || true
        [ -x /usr/local/bin/certbot ] && sudo ln -sf /usr/local/bin/certbot /usr/bin/certbot || true
      fi
    fi
  fi
  sudo systemctl stop httpd || true
  certbot certonly --standalone --non-interactive --agree-tos -m "${CERTBOT_EMAIL:-${OOD_USER_EMAIL:-}}" --cert-name "$OOD_DNS" -d "$OOD_DNS" --webroot-path /
  echo "0 0,12 * * * root sleep \$((RANDOM % 3600)) && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null
fi

# Configure OOD user
ensure_ood_user

# Create OOD portal config
log "Writing /etc/ood/config/ood_portal.yml"
sudo cat << EOF > /etc/ood/config/ood_portal.yml
---
servername: ${OOD_DNS}
# Enable reverse proxy endpoints for node and rnode
# Note: do not include ^ or $ anchors here; the portal generator embeds this in a larger regex
host_regex: '(localhost|127\.0\.0\.1)'
node_uri: '/node'
rnode_uri: '/rnode'
# Use OIDC authentication
auth:
  - "AuthType openid-connect"
  - "Require valid-user"
# Use OIDC logout
logout_redirect: "/oidc?logout=https%3A%2F%2F${OOD_DNS}%2F"
oidc_uri: "/oidc"
oidc_provider_metadata_url: "${IDCS_URL}/.well-known/openid-configuration"
oidc_client_id: "${CLIENT_ID}"
oidc_client_secret: "${CLIENT_SECRET}"
oidc_remote_user_claim: "sub"
oidc_scope: "urn:opc:idm:t.user.me openid email"
oidc_session_inactivity_timeout: 28800
oidc_session_max_duration: 28800
oidc_state_max_number_of_cookies: "10 true"
oidc_settings:
  OIDCPassIDTokenAs: "serialized"
  OIDCPassRefreshToken: "On"
  OIDCPassClaimsAs: "environment"
  OIDCStripCookies: "mod_auth_openidc_session mod_auth_openidc_session_chunks mod_auth_openidc_session_0 mod_auth_openidc_session_1"
  OIDCResponseType: "code"

ssl:
  - 'SSLCertificateFile "/etc/letsencrypt/live/${OOD_DNS}/fullchain.pem"'
  - 'SSLCertificateKeyFile "/etc/letsencrypt/live/${OOD_DNS}/privkey.pem"'
EOF

# Create Apache OIDC config
log "Writing /etc/httpd/conf.d/auth_openidc.conf"
sudo cat << EOF > /etc/httpd/conf.d/auth_openidc.conf
# Apache auth_openidc.conf
OIDCProviderMetadataURL ${IDCS_URL}/.well-known/openid-configuration
OIDCClientID ${CLIENT_ID}
OIDCClientSecret ${CLIENT_SECRET}
OIDCRedirectURI https://${OOD_DNS}/oidc
OIDCCryptoPassphrase ${CRYPTO_PASSPHRASE}
OIDCScope "urn:opc:idm:t.user.me openid email"
EOF

# Update Apache config based on ood_portal.yml file
log "Running ood-portal-generator to update Apache portal config"
/opt/ood/ood-portal-generator/sbin/update_ood_portal

# Ensure Apache unsets Origin headers for Grafana proxied path to avoid CORS rejection
log "Installing Apache snippet to unset Origin for Grafana path"
sudo tee /etc/httpd/conf.d/ood-grafana-origin-unset.conf > /dev/null <<'EOF'
<LocationMatch "^/node/(localhost|127\.0\.0\.1)/3000(/.*)?$">
  RequestHeader unset Origin
  RequestHeader unset Access-Control-Request-Method
  RequestHeader unset Access-Control-Request-Headers
</LocationMatch>
EOF

# Restart Apache service
log "Ensuring firewalld is enabled and started"
sudo systemctl enable firewalld || true
sudo systemctl start firewalld || true

# Add /etc/ood/apps/shell/env
log "Writing /etc/ood/config/apps/shell/env"
sudo mkdir -p /etc/ood/config/apps/shell
sudo tee /etc/ood/config/apps/shell/env > /dev/null << 'EOF'
OOD_SSHHOST_ALLOWLIST="localhost"
OOD_CLUSTERS="/etc/ood/config/clusters.d"
EOF

# Add Cluster YML
log "Writing /etc/ood/config/clusters.d/hpc_cluster.yml"
sudo mkdir -p /etc/ood/config/clusters.d
sudo tee /etc/ood/config/clusters.d/hpc_cluster.yml > /dev/null << 'EOF'
---
v2:
  metadata:
    title: "OCI HPC"
  login:
    host: "localhost"
  job:
    adapter: "slurm"
    cluster: "cluster"
    bin: "/usr/bin"
    conf: "/etc/slurm/slurm.conf"

EOF

log "Restarting httpd"
sudo systemctl restart httpd || sudo systemctl restart apache2 || true

# Configure SELinux for OOD (persistent contexts + policy)
log "Configuring SELinux contexts and policy for OOD"
sudo tee -a /etc/selinux/targeted/contexts/files/file_contexts.local > /dev/null <<'EOC'
/run/ondemand-nginx(/.*)?        system_u:object_r:httpd_var_run_t:s0
/var/run/ondemand-nginx(/.*)?    system_u:object_r:httpd_var_run_t:s0
/var/lib/ondemand-nginx(/.*)?    system_u:object_r:httpd_sys_rw_content_t:s0
/var/log/ondemand-nginx(/.*)?    system_u:object_r:httpd_sys_rw_content_t:s0
EOC
sudo restorecon -Rv /run/ondemand-nginx /var/run/ondemand-nginx /var/lib/ondemand-nginx /var/log/ondemand-nginx /etc/ood /var/www/ood || true
sudo setsebool -P httpd_can_network_connect on || true
# Install minimal policy to allow httpd to connect to OOD UDS socket
sudo bash -lc 'cat > /root/ood_httpd_sock.te <<"EOT"
module ood_httpd_sock 1.0;

require {
  type httpd_t;
  type httpd_var_run_t;
  class sock_file connectto;
}

allow httpd_t httpd_var_run_t:sock_file connectto;
EOT' && \
sudo dnf install -y checkpolicy policycoreutils-python-utils || true && \
sudo checkmodule -M -m -o /root/ood_httpd_sock.mod /root/ood_httpd_sock.te && \
sudo semodule_package -o /root/ood_httpd_sock.pp -m /root/ood_httpd_sock.mod && \
sudo semodule -i /root/ood_httpd_sock.pp || true

# If Grafana is installed, configure it to serve from OOD subpath and create OOD app entry
if systemctl list-unit-files | grep -q grafana-server.service || [ -f /etc/grafana/grafana.ini ]; then
  log "Configuring Grafana for OOD subpath in /etc/grafana/grafana.ini"
  GRAFANA_INI="/etc/grafana/grafana.ini"

  # Ensure [server] settings
  sudo sed -i -E "/^\[server\]/,/^\[/{s|^;?\s*root_url\s*=.*$|root_url = https://${OOD_DNS}/node/localhost/3000/|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[server\]/,/^\[/{s|^;?\s*serve_from_sub_path\s*=.*$|serve_from_sub_path = true|}" "$GRAFANA_INI" || true

  # If keys not present inside [server], append at end
  if ! grep -q "^root_url\s*=\s*https://${OOD_DNS}/node/localhost/3000/" "$GRAFANA_INI"; then
    sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[server]
root_url = https://${OOD_DNS}/node/localhost/3000/
serve_from_sub_path = true
EOT"
  fi

  # Ensure [security] allow_embedding
  sudo sed -i -E "/^\[security\]/,/^\[/{s|^;?\s*allow_embedding\s*=.*$|allow_embedding = true|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[security\]/,/^\[/{s|^;?\s*cookie_samesite\s*=.*$|cookie_samesite = none|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[security\]/,/^\[/{s|^;?\s*cookie_secure\s*=.*$|cookie_secure = true|}" "$GRAFANA_INI" || true
  if ! awk 'BEGIN{IGNORECASE=1} /^
\[security\]/{insec=1} insec && /^allow_embedding/{found=1} END{exit(found?0:1)}' "$GRAFANA_INI"; then
    sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[security]
allow_embedding = true
cookie_samesite = none
cookie_secure = true
EOT"
  fi

  # Ensure [cors] settings to allow OOD origin
  sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*enabled\s*=.*$|enabled = true|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_origins\s*=.*$|allow_origins = https://${OOD_DNS}|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_credentials\s*=.*$|allow_credentials = true|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_methods\s*=.*$|allow_methods = GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS|}" "$GRAFANA_INI" || true
  sudo sed -i -E "/^\[cors\]/,/^\[/{s|^;?\s*allow_headers\s*=.*$|allow_headers = Accept, Authorization, Content-Type, Origin, User-Agent, X-Requested-With, X-Grafana-Org-Id|}" "$GRAFANA_INI" || true
  if ! awk 'BEGIN{IGNORECASE=1} /^\[cors\]/{found=1} END{exit(found?0:1)}' "$GRAFANA_INI"; then
    sudo bash -c "cat >> '$GRAFANA_INI' <<EOT
[cors]
enabled = true
allow_origins = https://${OOD_DNS}
allow_credentials = true
allow_methods = GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS
allow_headers = Accept, Authorization, Content-Type, Origin, User-Agent, X-Requested-With, X-Grafana-Org-Id
EOT"
  fi

  # Create OOD system app for Grafana
  log "Creating OOD app manifest for Grafana"
  sudo mkdir -p /var/www/ood/apps/sys/oci_grafana
  sudo tee /var/www/ood/apps/sys/oci_grafana/manifest.yml > /dev/null << 'EOM'
---
name: Grafana
category: Monitoring
description: Grafana dashboards
icon: fas://chart-line
url: /node/localhost/3000/
EOM

  # Restart services to apply changes
  log "Restarting grafana-server and reloading httpd"
  sudo systemctl restart grafana-server || true
  sudo systemctl reload httpd || sudo systemctl restart httpd
fi

log "OOD setup script completed successfully."