# Open OnDemand / Grafana configuration (templated; values are safely quoted)
export OOD_DNS="${ood_dns_q}"
export OOD_USERNAME="${ood_username_q}"
export OOD_PASSWORD="${ood_user_password_q}"
export OOD_USER_EMAIL="${ood_user_email_q}"
export CLIENT_ID="${client_id_q}"
export CLIENT_SECRET="${client_secret_q}"
export IDCS_URL="${idcs_url_q}"

# Optional overrides for Grafana (leave commented unless needed)
# export GF_SERVER_ROOT_URL="https://${ood_dns_q}/node/localhost/3000/"
# export GF_SERVER_DOMAIN="${ood_dns_q}"
