#!/bin/bash
#==============================================================================
#   ____  ____    _      ____  ____      _    ____   ___
#  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#  Simulador — ponto de entrada do container.
#  Uso: entrada.sh <cenário> '<comando 1>' ['<comando 2>' ...]
#  SIM_RESPOSTAS="DATA 2"  respostas digitadas nas confirmações (sem terminal)
#  SIM_SHELL=1             abre um shell no cenário montado
#  by • DBA BRABO
#==============================================================================
set -u
CEN=$1; shift
mkdir -p /sim/mundo /sim/nos; : > /sim/mundo/cfg
. /sim/lab/monta.sh
. "/sim/lab/cenarios/$CEN.sh" >/dev/null || { echo "Cenário inválido: $CEN" >&2; exit 1; }
. /sim/lab/lib.sh
chmod 777 "$M"; touch "$M"/{asm,ops,asmlib,afd}.tsv; find "$M" -type d -exec chmod 777 {} + ; find "$M" -type f -exec chmod 666 {} +

# relógio: começa na janela de manutenção, 2026-11-10 22:00:00 (-03)
export TZ='<-03>3'
/usr/bin/date -d "${SIM_INICIO:-2026-11-10 22:00:00}" +%s > "$M/relogio_base"
/usr/bin/date +%s > "$M/relogio_real0"; echo 0 > "$M/relogio_off"
sed -i "s/|T0|/|$(relogio)|/" "$M/ops.tsv"     # rebalance que o cenário deixou rodando
[[ -n ${DEPOIS_RELOGIO:-} ]] && eval "$DEPOIS_RELOGIO"

# "instância ASM": um processo com o nome do pmon, do usuário grid
if [[ -z ${SEM_ASM:-} ]]; then
  runuser -u grid -- bash -c "exec -a asm_pmon_$SID_LOCAL /usr/bin/sleep infinity" &
  /usr/bin/sleep 0.3
fi

cd /opt/dbabrabo || exit 1
[[ -n ${SIM_SHELL:-} ]] && exec bash -l
# Roda cada comando num terminal (pty, via expect): o script vê um tty de verdade
# (cores, confirmação digitada) e o "operador" digita as respostas de SIM_RESPOSTAS.
# SIM_TTY=nao roda sem terminal.
rc=0
for c in "$@"; do
  printf '[root@%s dbabrabo]# %s\n' "$(hostname -s)" "$c"
  if [[ ${SIM_TTY:-sim} == nao || -t 0 ]]; then bash -c "$c"; rc=$?; else /sim/lab/operador.exp "$c"; rc=$?; fi
  echo
done
exit "$rc"
