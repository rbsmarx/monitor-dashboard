#!/bin/bash
# ==========================================================
# Script de Monitoramento de VPS
# Autor: Monitoramento Automatizado
# Descrição: Coleta métricas de serviços, containers Docker,
#             bancos de dados (Supabase), RAM, rede, CPU,
#             disco, conexões e swap. Salva em log JSON lines.
# ==========================================================

set -euo pipefail

# --- Diretório base ---
BASE_DIR="/Monitoramento"
ENV_FILE="$BASE_DIR/servicos.env"

# --- Verifica se o .env existe ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERRO] Arquivo de configuração $ENV_FILE não encontrado." >&2
  exit 1
fi

# --- Carrega variáveis do .env ---
source "$ENV_FILE"

# --- Cria diretórios necessários (caso não existam) ---
mkdir -p "$DIR_LOG" "$DIR_RUN"

# --- Controle de execução simultânea (lock) ---
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Execução já em andamento. Abortando." >> "$ERROR_LOG_FILE"
  exit 0
fi

# --- Função de log de erro ---
log_erro() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ERROR_LOG_FILE"
}

# --- Hostname ---
HOST=${HOSTNAME_CUSTOM:-$(hostname)}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_EPOCH=$(date '+%s')

# ==========================================================
# 1. MONITORAMENTO DE SERVIÇOS (systemd)
# ==========================================================
SERVICOS_JSON="["
PRIMEIRO=true
ALERTAS=()
ALERTAS_KEYS=()

for item in "${SERVICOS[@]}"; do
  NOME="${item%%:*}"
  SERVICO="${item##*:}"

  if systemctl is-active --quiet "$SERVICO" 2>/dev/null; then
    STATUS="ativo"
  elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${SERVICO}.service"; then
    STATUS="parado"
    ALERTAS+=("Serviço $NOME ($SERVICO) está PARADO")
    ALERTAS_KEYS+=("servico_$SERVICO") 
  else
    STATUS="nao_encontrado"
    log_erro "Serviço $SERVICO (nome amigável: $NOME) não encontrado no systemd."
  fi

  if [ "$PRIMEIRO" = true ]; then
    PRIMEIRO=false
  else
    SERVICOS_JSON+=","
  fi
  SERVICOS_JSON+="{\"nome\":\"$NOME\",\"servico\":\"$SERVICO\",\"status\":\"$STATUS\"}"
done
SERVICOS_JSON+="]"

# ==========================================================
# 2. MONITORAMENTO DE CONTAINERS DOCKER (Proxy Reverso)
# ==========================================================
CONTAINERS_PROXY_JSON="["
PRIMEIRO=true

for item in "${CONTAINERS_PROXY[@]}"; do
  NOME="${item%%:*}"
  PADRAO="${item##*:}"

  CONTAINER_ENCONTRADO=$(docker ps --format "{{.Names}}" 2>/dev/null | grep "$PADRAO" | head -n1 || true)

  if [ -z "$CONTAINER_ENCONTRADO" ]; then
    STATUS="nao_encontrado"
    log_erro "Container proxy $NOME (padrão: $PADRAO) não encontrado em execução."
  else
    RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_ENCONTRADO" 2>/dev/null || echo "false")
    if [ "$RUNNING" = "true" ]; then
      STATUS="ativo"
    else
      STATUS="parado"
      ALERTAS+=("Container $NOME ($CONTAINER_ENCONTRADO) está PARADO")
      ALERTAS_KEYS+=("proxy_$NOME")
    fi
  fi

  if [ "$PRIMEIRO" = true ]; then
    PRIMEIRO=false
  else
    CONTAINERS_PROXY_JSON+=","
  fi
  CONTAINERS_PROXY_JSON+="{\"nome\":\"$NOME\",\"container\":\"${CONTAINER_ENCONTRADO:-desconhecido}\",\"status\":\"$STATUS\"}"
done
CONTAINERS_PROXY_JSON+="]"



# ==========================================================
# 3. MONITORAMENTO DE CONTAINERS DE BANCO DE DADOS (Supabase)
#    Status verificado em tempo real (leve).
#    Tamanho do banco lido de cache (atualizado a cada 5 min
#    pelo monitor_db_size.sh, pois consulta via psql é pesada).
# ==========================================================
CACHE_DB_FILE="$DIR_RUN/db_size_cache.json"

CONTAINERS_DB_JSON="["
PRIMEIRO=true

for item in "${CONTAINERS_DB[@]}"; do
  NOME="${item%%:*}"
  PADRAO="${item##*:}"

  CONTAINER_ENCONTRADO=$(docker ps --format "{{.Names}}" 2>/dev/null | grep "$PADRAO" | head -n1 || true)
  TAMANHO_MB=0
  STATUS="nao_encontrado"

  if [ -z "$CONTAINER_ENCONTRADO" ]; then
    log_erro "Container de banco $NOME (padrão: $PADRAO) não encontrado em execução."
  else
    RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_ENCONTRADO" 2>/dev/null || echo "false")
    if [ "$RUNNING" = "true" ]; then
      STATUS="ativo"
    else
      STATUS="parado"
      ALERTAS+=("Container de banco $NOME ($CONTAINER_ENCONTRADO) está PARADO")
      ALERTAS_KEYS+=("db_status_$NOME")
    fi
  fi

  # --- LÃª tamanho do cache (se existir e for JSON vÃ¡lido) ---
  if [ -f "$CACHE_DB_FILE" ]; then
    TAMANHO_MB=$(python3 -c "
import json,sys
try:
    with open('$CACHE_DB_FILE') as f:
        data = json.load(f)
    for c in data.get('containers_db', []):
        if c.get('nome') == '$NOME':
            print(c.get('tamanho_mb', 0))
            break
    else:
        print(0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)
  fi

  if (( $(echo "${TAMANHO_MB:-0} >= $LIMITE_DB_TAMANHO_MB" | bc -l) )); then
    ALERTAS+=("Banco $NOME está grande: ${TAMANHO_MB}MB")
    ALERTAS_KEYS+=("db_tamanho_$NOME")
  fi

  if [ "$PRIMEIRO" = true ]; then
    PRIMEIRO=false
  else
    CONTAINERS_DB_JSON+=","
  fi
  CONTAINERS_DB_JSON+="{\"nome\":\"$NOME\",\"container\":\"${CONTAINER_ENCONTRADO:-desconhecido}\",\"status\":\"$STATUS\",\"tamanho_mb\":${TAMANHO_MB:-0}}"
done
CONTAINERS_DB_JSON+="]"





# ==========================================================
# 4. MONITORAMENTO DE MEMÓRIA RAM E SWAP
# ==========================================================
read -r MEM_TOTAL MEM_USADA MEM_LIVRE MEM_DISPONIVEL <<< "$(free -m | awk '/^Mem:/{print $2, $3, $4, $7}')"
read -r SWAP_TOTAL SWAP_USADA <<< "$(free -m | awk '/^Swap:/{print $2, $3}')"

MEM_PERCENT=0
if [ "$MEM_TOTAL" -gt 0 ]; then
  MEM_PERCENT=$(awk -v u="$MEM_USADA" -v t="$MEM_TOTAL" 'BEGIN{printf "%.2f", (u/t)*100}')
fi

SWAP_PERCENT=0
if [ "${SWAP_TOTAL:-0}" -gt 0 ]; then
  SWAP_PERCENT=$(awk -v u="$SWAP_USADA" -v t="$SWAP_TOTAL" 'BEGIN{printf "%.2f", (u/t)*100}')
fi

if (( $(echo "$MEM_PERCENT >= $LIMITE_RAM_PERCENT" | bc -l) )); then
  ALERTAS+=("Uso de RAM alto: ${MEM_PERCENT}%")
  ALERTAS_KEYS+=("ram_alto")
fi
if (( $(echo "$SWAP_PERCENT >= $LIMITE_SWAP_PERCENT" | bc -l) )); then
  ALERTAS+=("Uso de SWAP alto: ${SWAP_PERCENT}%")
  ALERTAS_KEYS+=("swap_alto")
fi

# ==========================================================
# 5. MONITORAMENTO DE REDE (taxa de transmissão)
# ==========================================================
if [[ -z "$INTERFACE_REDE" ]]; then
  IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
  IFACE=${IFACE:-$(ls /sys/class/net | grep -v lo | head -n1)}
else
  IFACE="$INTERFACE_REDE"
fi

RX_FILE="$DIR_RUN/rx_bytes_prev"
TX_FILE="$DIR_RUN/tx_bytes_prev"
TIME_FILE="$DIR_RUN/net_time_prev"

RX_BYTES_ATUAL=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
TX_BYTES_ATUAL=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

RX_ANTERIOR=$(cat "$RX_FILE" 2>/dev/null || echo "$RX_BYTES_ATUAL")
TX_ANTERIOR=$(cat "$TX_FILE" 2>/dev/null || echo "$TX_BYTES_ATUAL")
TEMPO_ANTERIOR=$(cat "$TIME_FILE" 2>/dev/null || echo "$TIMESTAMP_EPOCH")

DELTA_TEMPO=$(( TIMESTAMP_EPOCH - TEMPO_ANTERIOR ))
[ "$DELTA_TEMPO" -le 0 ] && DELTA_TEMPO=1

DELTA_RX=$(( RX_BYTES_ATUAL - RX_ANTERIOR ))
DELTA_TX=$(( TX_BYTES_ATUAL - TX_ANTERIOR ))
[ "$DELTA_RX" -lt 0 ] && DELTA_RX=0
[ "$DELTA_TX" -lt 0 ] && DELTA_TX=0

RX_KBPS=$(awk -v d="$DELTA_RX" -v t="$DELTA_TEMPO" 'BEGIN{printf "%.2f", (d/1024)/t}')
TX_KBPS=$(awk -v d="$DELTA_TX" -v t="$DELTA_TEMPO" 'BEGIN{printf "%.2f", (d/1024)/t}')

echo "$RX_BYTES_ATUAL" > "$RX_FILE"
echo "$TX_BYTES_ATUAL" > "$TX_FILE"
echo "$TIMESTAMP_EPOCH" > "$TIME_FILE"

# --- Conexões TCP ativas ---
CONEXOES_TCP=$(ss -t state established 2>/dev/null | wc -l)
if [ "$CONEXOES_TCP" -ge "$LIMITE_CONEXOES_TCP" ]; then
  ALERTAS+=("Número de conexões TCP alto: $CONEXOES_TCP")
  ALERTAS_KEYS+=("conexoes_tcp")
fi

# ==========================================================
# 6. MONITORAMENTO DE CPU
# ==========================================================
read -r CPU_LINE < /proc/stat
CPU_VALS=($CPU_LINE)
IDLE1=${CPU_VALS[4]}
TOTAL1=0
for v in "${CPU_VALS[@]:1:7}"; do TOTAL1=$((TOTAL1+v)); done
sleep 1
read -r CPU_LINE2 < /proc/stat
CPU_VALS2=($CPU_LINE2)
IDLE2=${CPU_VALS2[4]}
TOTAL2=0
for v in "${CPU_VALS2[@]:1:7}"; do TOTAL2=$((TOTAL2+v)); done

DELTA_TOTAL=$((TOTAL2-TOTAL1))
DELTA_IDLE=$((IDLE2-IDLE1))
CPU_PERCENT=$(awk -v dt="$DELTA_TOTAL" -v di="$DELTA_IDLE" 'BEGIN{ if(dt>0) printf "%.2f", (1-di/dt)*100; else print "0.00"}')

if (( $(echo "$CPU_PERCENT >= $LIMITE_CPU_PERCENT" | bc -l) )); then
  ALERTAS+=("Uso de CPU alto: ${CPU_PERCENT}%")
  ALERTAS_KEYS+=("cpu_alto")
fi

# ==========================================================
# 7. MONITORAMENTO DE DISCO
# ==========================================================
DISCO_JSON="["
PRIMEIRO=true
for PART in $PARTICOES_MONITORAR; do
  if [ -d "$PART" ]; then
    read -r USO_PERCENT USADO DISPONIVEL <<< "$(df -h "$PART" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5, $3, $4}')"
    if [ "$PRIMEIRO" = true ]; then
      PRIMEIRO=false
    else
      DISCO_JSON+=","
    fi
    DISCO_JSON+="{\"particao\":\"$PART\",\"uso_percent\":${USO_PERCENT:-0},\"usado\":\"$USADO\",\"disponivel\":\"$DISPONIVEL\"}"
    if [ "${USO_PERCENT:-0}" -ge "$LIMITE_DISCO_PERCENT" ] 2>/dev/null; then
      ALERTAS+=("Uso de disco alto em $PART: ${USO_PERCENT}%")
      ALERTAS_KEYS+=("disco_$PART") 
    fi
  fi
done
DISCO_JSON+="]"

# ==========================================================
# 8. LOAD AVERAGE E UPTIME
# ==========================================================
LOAD_AVG=$(cut -d' ' -f1-3 /proc/loadavg)
UPTIME_SEG=$(awk '{print int($1)}' /proc/uptime)

# ==========================================================
# 9. MONTAGEM DO LOG (JSON Lines)
# ==========================================================
ALERTAS_JSON="[]"
if [ ${#ALERTAS[@]} -gt 0 ]; then
  ALERTAS_JSON="["
  for i in "${!ALERTAS[@]}"; do
    [ "$i" -gt 0 ] && ALERTAS_JSON+=","
    ALERTAS_JSON+="\"${ALERTAS[$i]}\""
  done
  ALERTAS_JSON+="]"
fi

LOG_LINE=$(cat <<EOF
{"timestamp":"$TIMESTAMP","host":"$HOST","servicos":$SERVICOS_JSON,"containers_proxy":$CONTAINERS_PROXY_JSON,"containers_db":$CONTAINERS_DB_JSON,"ram":{"total_mb":$MEM_TOTAL,"usada_mb":$MEM_USADA,"livre_mb":$MEM_LIVRE,"disponivel_mb":$MEM_DISPONIVEL,"uso_percent":$MEM_PERCENT},"swap":{"total_mb":${SWAP_TOTAL:-0},"usada_mb":${SWAP_USADA:-0},"uso_percent":$SWAP_PERCENT},"rede":{"interface":"$IFACE","rx_kbps":$RX_KBPS,"tx_kbps":$TX_KBPS},"conexoes_tcp":$CONEXOES_TCP,"cpu_percent":$CPU_PERCENT,"discos":$DISCO_JSON,"load_average":"$LOAD_AVG","uptime_segundos":$UPTIME_SEG,"alertas":$ALERTAS_JSON}
EOF
)

# Compacta em uma linha só (remove quebras acidentais)
echo "$LOG_LINE" | tr -d '\n' >> "$LOG_FILE"
echo "" >> "$LOG_FILE"


# ==========================================================
# 9.1 VERIFICAÇÃO DE ALERTAS CONSECUTIVOS (WhatsApp)
# ==========================================================
ALERTA_STATE_FILE="$DIR_RUN/alert_state.json"

if [ ${#ALERTAS[@]} -gt 0 ]; then
  ALERTAS_ATUAIS_JSON="["
  for i in "${!ALERTAS[@]}"; do
    [ "$i" -gt 0 ] && ALERTAS_ATUAIS_JSON+=","
    CHAVE_ESCAPADA=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "${ALERTAS_KEYS[$i]}")
    MSG_ESCAPADA=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "${ALERTAS[$i]}")
    ALERTAS_ATUAIS_JSON+="{\"chave\":$CHAVE_ESCAPADA,\"mensagem\":$MSG_ESCAPADA}"
  done
  ALERTAS_ATUAIS_JSON+="]"
else
  ALERTAS_ATUAIS_JSON="[]"
fi

MENSAGENS_NOTIFICAR=$(python3 "$BASE_DIR/verificar_alertas_consecutivos.py" "$ALERTA_STATE_FILE" "$ALERTAS_ATUAIS_JSON" "${LIMITE_ALERTAS_CONSECUTIVOS:-5}" || true)


if [[ -n "$MENSAGENS_NOTIFICAR" ]]; then
  source "$BASE_DIR/whatsapp_notifier.sh"

  enviar_whatsapp "⚠️ *ALERTA - $HOST ⚠️*
🔴 $MENSAGENS_NOTIFICAR
https://monitor.agaemetech.com.br"
fi




# ==========================================================
# 10. ROTAÇÃO DE LOGS ANTIGOS
# ==========================================================
find "$DIR_LOG" -name "*.log*" -mtime +"$RETENCAO_DIAS_LOG" -delete 2>/dev/null || true

# --- Libera lock ---
flock -u 200
exit 0
