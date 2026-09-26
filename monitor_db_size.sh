#!/bin/bash
# ==========================================================
# Script de monitoramento do TAMANHO dos bancos Supabase
# Executado separadamente via cron (baixa frequência),
# pois consultas via psql são mais pesadas.
# Salva resultado em cache JSON lido pelo monitor.sh principal.
# ==========================================================

set -euo pipefail

BASE_DIR="/Monitoramento"
ENV_FILE="$BASE_DIR/servicos.env"
CACHE_FILE="$BASE_DIR/run/db_size_cache.json"
ERROR_LOG_FILE="$BASE_DIR/logs/monitor_error.log"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERRO] Arquivo de configuração $ENV_FILE não encontrado." >&2
  exit 1
fi

source "$ENV_FILE"

mkdir -p "$BASE_DIR/run"

log_erro() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DB_SIZE] $1" >> "$ERROR_LOG_FILE"
}

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CONTAINERS_DB_JSON="["
PRIMEIRO=true

for item in "${CONTAINERS_DB[@]}"; do
  NOME="${item%%:*}"
  PADRAO="${item##*:}"

  CONTAINER_ENCONTRADO=$(docker ps --format "{{.Names}}" 2>/dev/null | grep "$PADRAO" | head -n1 || true)
  TAMANHO_MB=0

  if [ -n "$CONTAINER_ENCONTRADO" ]; then
    TAMANHO_BYTES=$(docker exec "$CONTAINER_ENCONTRADO" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB_NOME" -tAc \
      "SELECT pg_database_size('$POSTGRES_DB_NOME');" 2>/dev/null | tr -d '[:space:]' || echo "")

    if [[ "$TAMANHO_BYTES" =~ ^[0-9]+$ ]]; then
      TAMANHO_MB=$(awk -v b="$TAMANHO_BYTES" 'BEGIN{printf "%.2f", b/1024/1024}')
    else
      log_erro "Não foi possível obter o tamanho do banco $NOME ($CONTAINER_ENCONTRADO)."
    fi
  else
    log_erro "Container de banco $NOME (padrão: $PADRAO) não encontrado em execução."
  fi

  if [ "$PRIMEIRO" = true ]; then
    PRIMEIRO=false
  else
    CONTAINERS_DB_JSON+=","
  fi
  CONTAINERS_DB_JSON+="{\"nome\":\"$NOME\",\"container\":\"${CONTAINER_ENCONTRADO:-desconhecido}\",\"tamanho_mb\":$TAMANHO_MB}"
done
CONTAINERS_DB_JSON+="]"

# --- Salva cache (arquivo temporário + move, evita leitura parcial) ---
TMP_FILE="${CACHE_FILE}.tmp"
echo "{\"timestamp\":\"$TIMESTAMP\",\"containers_db\":$CONTAINERS_DB_JSON}" > "$TMP_FILE"
mv "$TMP_FILE" "$CACHE_FILE"

exit 0
