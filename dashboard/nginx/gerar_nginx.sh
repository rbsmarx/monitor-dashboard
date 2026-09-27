#!/bin/bash
set -euo pipefail

ENV_FILE="/Monitoramento/servicos.env"
source "$ENV_FILE"

if [[ -z "${DOMINIO_DASHBOARD:-}" ]]; then
  echo "[ERRO] DOMINIO_DASHBOARD não definido no servicos.env"
  exit 1
fi

CONF_PATH="/etc/nginx/sites-available/monitoramento-dashboard"

cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    server_name ${DOMINIO_DASHBOARD};

    location / {
        proxy_pass http://127.0.0.1:${DASHBOARD_PORTA};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf "$CONF_PATH" /etc/nginx/sites-enabled/monitoramento-dashboard
nginx -t && systemctl reload nginx

echo "[OK] Configuração criada para ${DOMINIO_DASHBOARD}"

if [[ "${DASHBOARD_HTTPS:-false}" == "true" ]]; then
  echo "[INFO] Solicitando certificado SSL via Certbot..."
  certbot --nginx -d "${DOMINIO_DASHBOARD}" \
    --non-interactive --agree-tos -m "${DASHBOARD_EMAIL_CERTBOT}" --redirect
fi

echo "[OK] Dashboard disponível em: https://${DOMINIO_DASHBOARD}"
