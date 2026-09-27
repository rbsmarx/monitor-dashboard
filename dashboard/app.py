#!/usr/bin/env python3
import os
import json
import re
from functools import wraps
from flask import Flask, request, Response, jsonify, render_template

app = Flask(__name__)

BASE_DIR = "/Monitoramento"
ENV_FILE = os.path.join(BASE_DIR, "servicos.env")
LOG_FILE = os.path.join(BASE_DIR, "logs", "monitor.log")

# ==========================================================
# Carrega variáveis do servicos.env (parser simples)
# ==========================================================
def carregar_env(caminho):
    config = {}
    if not os.path.exists(caminho):
        return config
    with open(caminho, "r", encoding="utf-8") as f:
        for linha in f:
            linha = linha.strip()
            if not linha or linha.startswith("#"):
                continue
            m = re.match(r'^([A-Z0-9_]+)\s*=\s*"?([^"\n]*)"?$', linha)
            if m:
                config[m.group(1)] = m.group(2)
    return config

ENV = carregar_env(ENV_FILE)

USUARIO = ENV.get("DASHBOARD_USUARIO", "admin")
SENHA_HASH = ENV.get("DASHBOARD_SENHA_HASH", "")
LIMITE_REGISTROS = int(ENV.get("DASHBOARD_LIMITE_REGISTROS", "200"))

from werkzeug.security import check_password_hash

# ==========================================================
# Autenticação HTTP Basic
# ==========================================================
def checar_credenciais(usuario, senha):
    if usuario != USUARIO:
        return False
    if not SENHA_HASH:
        return False
    return check_password_hash(SENHA_HASH, senha)

def autenticacao_necessaria():
    return Response(
        "Acesso restrito. Informe usuário e senha.\n",
        401,
        {"WWW-Authenticate": 'Basic realm="Dashboard de Monitoramento"'},
    )

def requer_login(f):
    @wraps(f)
    def decorador(*args, **kwargs):
        auth = request.authorization
        if not auth or not checar_credenciais(auth.username, auth.password):
            return autenticacao_necessaria()
        return f(*args, **kwargs)
    return decorador

# ==========================================================
# Leitura do log (JSON Lines)
# ==========================================================
def ler_ultimos_registros(limite=200):
    registros = []
    if not os.path.exists(LOG_FILE):
        return registros
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        linhas = f.readlines()[-limite:]
    for linha in linhas:
        linha = linha.strip()
        if not linha:
            continue
        try:
            registros.append(json.loads(linha))
        except json.JSONDecodeError:
            continue
    return registros

# ==========================================================
# Rotas
# ==========================================================
@app.route("/")
@requer_login
def index():
    return render_template("index.html")

@app.route("/api/dados")
@requer_login
def api_dados():
    registros = ler_ultimos_registros(LIMITE_REGISTROS)
    return jsonify(registros)

@app.route("/api/status")
@requer_login
def api_status():
    registros = ler_ultimos_registros(1)
    if not registros:
        return jsonify({"erro": "Sem dados disponíveis"}), 404
    return jsonify(registros[-1])

@app.route("/health")
def health():
    # Endpoint sem autenticação, apenas para checagem interna (não expõe dados)
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    porta = int(ENV.get("DASHBOARD_PORTA", "8501"))
    app.run(host="127.0.0.1", port=porta)
