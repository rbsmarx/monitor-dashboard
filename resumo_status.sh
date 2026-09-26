#!/bin/bash
set -euo pipefail
BASE_DIR="/Monitoramento"
ENV_FILE="$BASE_DIR/servicos.env"
source "$ENV_FILE"
source "$BASE_DIR/whatsapp_notifier.sh"

export PYTHONIOENCODING="utf-8"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"


MENSAGEM=$(python3 - <<PYEOF
# -*- coding: utf-8 -*-
import json

with open("$LOG_FILE", "r", encoding="utf-8") as f:
    linhas = [l for l in f.readlines() if l.strip()]

if not linhas:
    print("Sem dados de monitoramento disponíveis.")
    raise SystemExit

registro = json.loads(linhas[-1])
m = []
m.append(f"📈 *Status do Monitoramento - {registro['host']} *")
m.append(f" *{registro['timestamp']}*")
m.append("")
m.append(f"💽 RAM: {registro['ram']['uso_percent']}%")
m.append(f"💿 SWAP: {registro['swap']['uso_percent']}%")
m.append(f"🖥️ CPU: {registro['cpu_percent']}%")
m.append(f"📡 Conexões TCP: {registro['conexoes_tcp']}")
m.append(f"⏱️ Uptime: {registro['uptime_segundos']//3600}h")
m.append("")
m.append("💾 *Discos:*")
for d in registro["discos"]:
    m.append(f"  {d['particao']}: {d['uso_percent']}%")
m.append("")
m.append("⚙️ *Serviços:*")
for s in registro["servicos"]:
    e = "🟢" if s["status"] == "ativo" else "🔴"
    m.append(f"  {e} {s['nome']}: {s['status']}")
m.append("")
m.append("🖥️ *Proxy:*")
for c in registro["containers_proxy"]:
    e = "🟢" if c["status"] == "ativo" else "🔴"
    m.append(f"  {e} {c['nome']}: {c['status']}")
m.append("")
m.append("💾 *Bancos de Dados:*")
for c in registro["containers_db"]:
    e = "🟢" if c["status"] == "ativo" else "🔴"
    m.append(f"  {e} {c['nome']}: {c['status']} ({c['tamanho_mb']}MB)")
m.append("")
if registro["alertas"]:
    m.append("⚠️ *Alertas ativos no último ciclo:*")
    for a in registro["alertas"]:
        m.append(f"  - {a}")
else:
    m.append("✅ Nenhum alerta ativo.")

print("\n".join(m))
PYEOF
)

enviar_whatsapp "$MENSAGEM"
