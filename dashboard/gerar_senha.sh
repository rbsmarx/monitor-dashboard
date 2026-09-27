#!/bin/bash
# gerar_senha_hash.sh
# Gera um hash de senha compatível com Werkzeug (Flask) para uso no servicos.env

CONTAINER_NAME="monitoramento-dashboard"

echo "=== Gerador de Hash de Senha - Dashboard Monitoramento ==="
echo ""

read -s -p "Digite a nova senha: " SENHA
echo ""
read -s -p "Confirme a nova senha: " SENHA_CONFIRM
echo ""

if [ "$SENHA" != "$SENHA_CONFIRM" ]; then
    echo "? As senhas não coincidem. Abortando."
    exit 1
fi

if [ -z "$SENHA" ]; then
    echo "? Senha vazia não é permitida. Abortando."
    exit 1
fi

# Verifica se o container está rodando
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "? Container '$CONTAINER_NAME' não está rodando."
    echo "Containers disponíveis:"
    docker ps --format '{{.Names}}'
    exit 1
fi

HASH=$(docker exec "$CONTAINER_NAME" python3 -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('$SENHA'))")

if [ -z "$HASH" ]; then
    echo "? Falha ao gerar o hash."
    exit 1
fi

echo ""
echo "? Hash gerado com sucesso:"
echo ""
echo "DASHBOARD_SENHA_HASH='$HASH'"
echo ""
echo "Copie a linha acima e substitua no arquivo servicos.env"
