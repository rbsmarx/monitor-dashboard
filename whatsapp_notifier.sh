#!/bin/bash
# ==========================================================
# Envio de mensagens via WhatsApp (Evolution API)
# ==========================================================

enviar_whatsapp() {
  local mensagem="$1"

  if [[ -z "${EVOLUTION_API_URL:-}" || -z "${EVOLUTION_API_KEY:-}" || -z "${EVOLUTION_INSTANCE:-}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WHATSAPP] Configuração incompleta. Envio abortado." >> "${ERROR_LOG_FILE:-/dev/null}"
    return 1
  fi

  IFS=',' read -ra NUMEROS <<< "${WHATSAPP_NUMEROS:-}"

  local texto_json
  texto_json=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$mensagem")

  for numero in "${NUMEROS[@]}"; do
    numero=$(echo "$numero" | tr -d '[:space:]')
    [[ -z "$numero" ]] && continue

    curl -s -X POST "${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}" \
      -H "Content-Type: application/json" \
      -H "apikey: ${EVOLUTION_API_KEY}" \
      -d "{\"number\": \"${numero}\", \"text\": ${texto_json}}" \
      > /dev/null 2>&1 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WHATSAPP] Falha ao enviar para $numero" >> "${ERROR_LOG_FILE:-/dev/null}"
  done
}
