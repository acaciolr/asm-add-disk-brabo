#!/usr/bin/env python3
# ==============================================================================
#    ____  ____    _      ____  ____      _    ____   ___
#   |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#   | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#   | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#   |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#   Coloca as saídas do simulador (saidas/exemplo_*.txt) nos READMEs, entre
#   os marcadores <!-- SAIDA:<nº> --> ... <!-- /SAIDA:<nº> -->.
#   Uso: ./simular.sh --todos && python3 gerar_readme.py
#   by • DBA BRABO
# ==============================================================================
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
ANSI = re.compile(r'\x1b\[[0-9;]*m')

ROTULO = {
    'README.md': ('Saída (simulador)', 'linhas do monitor omitidas'),
    'README.en.md': ('Output (simulator)', 'monitor lines trimmed'),
}


def limpa(txt: str, omitidas: str) -> str:
    txt = ANSI.sub('', txt).replace('\r', '')
    linhas = [l.rstrip() for l in txt.splitlines()]
    # a linha de build da imagem não faz parte da saída
    linhas = [l for l in linhas if not l.startswith('>> Construindo')]
    while linhas and not linhas[-1]:
        linhas.pop()
    return '\n'.join(resume_monitor(linhas, omitidas))


MONITOR = re.compile(r'^\s+\d{4}-\d\d-\d\d \d\d:\d\d:\d\d inst=')


def resume_monitor(linhas: list, omitidas: str) -> list:
    # o monitor imprime uma linha por consulta: mostra as 3 primeiras e as 3 últimas
    saida, bloco_mon = [], []
    for l in linhas + ['']:
        if MONITOR.match(l):
            bloco_mon.append(l)
            continue
        if len(bloco_mon) > 8:
            n = len(bloco_mon) - 6
            bloco_mon = bloco_mon[:3] + [f'  [... {n} {omitidas} ...]'] + bloco_mon[-3:]
        saida += bloco_mon
        bloco_mon = []
        saida.append(l)
    return saida[:-1]


def bloco(n: str, arq: str) -> str:
    f = AQUI / 'saidas' / f'exemplo_{n}.txt'
    if not f.exists():
        sys.exit(f'faltando {f} (rode ./simular.sh --todos)')
    resumo, omitidas = ROTULO[arq]
    return (f'<details>\n<summary><b>{resumo}</b></summary>\n\n'
            f'```text\n{limpa(f.read_text(encoding="utf-8"), omitidas)}\n```\n\n</details>')


def main() -> None:
    for arq in ROTULO:
        p = RAIZ / arq
        s = p.read_text(encoding='utf-8')
        s2 = re.sub(r'<!-- SAIDA:(\w+) -->.*?<!-- /SAIDA:\1 -->',
                    lambda m: f'<!-- SAIDA:{m.group(1)} -->\n{bloco(m.group(1), arq)}\n<!-- /SAIDA:{m.group(1)} -->',
                    s, flags=re.S)
        p.write_text(s2, encoding='utf-8')
        print(f'{arq}: {len(re.findall(r"<!-- SAIDA:", s2))} saídas')


if __name__ == '__main__':
    main()
