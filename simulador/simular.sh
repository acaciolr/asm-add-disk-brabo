#!/usr/bin/env bash
#==============================================================================
#   ____  ____    _      ____  ____      _    ____   ___
#  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#  SIMULADOR do ASM ADD DISK BRABO
#  Roda o script DE VERDADE dentro de um container com Grid/ASM, discos,
#  ASMLib, ASMFD, udev, multipath, AIX e cells Exadata FALSOS.
#
#  ./simular.sh --lista                      exemplos disponíveis
#  ./simular.sh <nº do exemplo>              roda o exemplo (ex.: ./simular.sh 2)
#  ./simular.sh --todos                      roda todos e grava em saidas/
#  ./simular.sh --shell <cenário>            shell dentro do cenário, para testar à vontade
#  ./simular.sh --cenario <c> -- <args>      roda o script com seus argumentos no cenário <c>
#  Requer: Docker. Nada sai do container (--network none).
#  by • DBA BRABO
#==============================================================================
set -u
cd "$(dirname "$0")" || exit 1
IMG=asm-add-disk-brabo-sim:1
SCRIPT=$(cd .. && pwd)/asm_add_disk_brabo.sh

construir() {
  docker image inspect "$IMG" >/dev/null 2>&1 && [[ -z ${SIM_REBUILD:-} ]] && return 0
  echo ">> Construindo a imagem do simulador ($IMG)..." >&2
  docker build -q -t "$IMG" . >/dev/null 2>&1 || { echo "Falha no docker build." >&2; exit 1; }
}

rodar() {  # rodar <cenário> <respostas> <comando>...
  local cen=$1 resp=$2; shift 2
  local host extra=()
  host=$(sed -n 's/^# host: *//p' "lab/cenarios/$cen.sh"); [[ -n $host ]] || host=dbnode01
  grep -q "^# sysfs" "lab/cenarios/$cen.sh" && extra+=(--security-opt apparmor=unconfined --mount type=tmpfs,dst=/sys/class/block --mount type=tmpfs,dst=/sys/class/scsi_host)
  local tty=() st=sim; [[ -t 0 && -t 1 && -n ${SIM_INTERATIVO:-} ]] && tty=(-it)
  [[ $resp == SEM_TTY ]] && { st=nao; resp=""; }
  docker run --rm "${tty[@]}" --network none --hostname "$host" "${extra[@]}" \
    -e SIM_RESPOSTAS="$resp" -e SIM_SHELL="${SIM_SHELL:-}" -e SIM_TTY="$st" \
    -v "$SCRIPT:/opt/dbabrabo/asm_add_disk_brabo.sh:ro" "$IMG" "$cen" "$@"
}

# saída do terminal virtual: tira o \r; com SIM_COR=nao tira também as cores
mostrar_respostas() { if [[ ${SIM_COR:-sim} == nao ]]; then sed -e 's/\r$//' -e 's/\x1b\[[0-9;]*m//g'; else sed -e 's/\r$//'; fi; }

exemplo() {  # lê exemplos.tsv: nº|cenário|respostas|título|comando[;;comando]
  local n=$1 linha cen resp tit cmds=()
  linha=$(awk -F'|' -v n="$n" '$1==n' exemplos.tsv)
  [[ -n $linha ]] || { echo "Exemplo $n não existe (veja --lista)." >&2; return 1; }
  IFS='|' read -r _ cen resp tit c <<<"$linha"
  while [[ $c == *';;'* ]]; do cmds+=("${c%%;;*}"); c=${c#*;;}; done; cmds+=("$c")
  rodar "$cen" "$resp" "${cmds[@]}" | mostrar_respostas
}

case ${1:-} in
  ""|-h|--help) sed -n '2,22p' "$0" | sed 's/^#//' ;;
  --lista) awk -F'|' 'NR>1 && $1!~/^#/{printf "  %-4s %-14s %s\n", $1, $2, $4}' exemplos.tsv ;;
  --shell) construir; SIM_SHELL=1 SIM_INTERATIVO=1 rodar "${2:?cenário}" "" ;;
  --cenario) construir; c=$2; shift 3; rodar "$c" "${SIM_RESPOSTAS:-}" "./asm_add_disk_brabo.sh $*" | mostrar_respostas ;;
  --todos) construir; mkdir -p saidas
           for n in $(awk -F'|' 'NR>1 && $1!~/^#/{print $1}' exemplos.tsv); do
             echo ">> exemplo $n" >&2; exemplo "$n" > "saidas/exemplo_$n.txt" 2>&1
           done ;;
  *) construir; exemplo "$1" ;;
esac
