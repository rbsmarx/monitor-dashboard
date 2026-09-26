#!/usr/bin/env python3
import json
import os
import sys

def main():
    state_file, atual_json, limite = sys.argv[1], sys.argv[2], int(sys.argv[3])

    atual = json.loads(atual_json)
    chaves_atuais = {a["chave"]: a["mensagem"] for a in atual}

    if os.path.exists(state_file):
        with open(state_file, "r", encoding="utf-8") as f:
            try:
                estado = json.load(f)
            except Exception:
                estado = {}
    else:
        estado = {}

    notificar = []

    for chave, msg in chaves_atuais.items():
        contador = estado.get(chave, 0) + 1
        if contador >= limite:
            notificar.append(msg)
            contador = 0
        estado[chave] = contador

    for chave in list(estado.keys()):
        if chave not in chaves_atuais:
            estado[chave] = 0

    with open(state_file, "w", encoding="utf-8") as f:
        json.dump(estado, f)

    for msg in notificar:
        print(msg)

if __name__ == "__main__":
    main()
