# shellcheck shell=bash
#==============================================================================
#   ____  ____    _      ____  ____      _    ____   ___
#  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#  Simulador — funções comuns dos comandos falsos.
#  O "mundo" (discos, ASM, cells) fica em /sim/mundo, em arquivos texto
#  separados por '|'. Cada comando falso lê e altera esses arquivos.
#  by • DBA BRABO
#==============================================================================
M=/sim/mundo
umask 000
[[ -r $M/cfg ]] && . "$M/cfg"

# devices.tsv: kname|tipo|maj:min|bytes|setor|pais(,)|montagem|pttype|assinatura|sujo|aberto|props(;)|dmname
dev_campo() { awk -F'|' -v k="$1" -v f="$2" '$1==k{print $f; exit}' "$M/devices.tsv"; }
dev_existe() { awk -F'|' -v k="$1" '$1==k{f=1} END{exit !f}' "$M/devices.tsv"; }
kname_de() {  # caminho -> kname (segue symlink; /dev/mapper/x -> dm-N)
  local p; p=$(readlink -f "$1" 2>/dev/null) || p=$1
  p=${p##*/}
  if ! dev_existe "$p"; then
    local k; k=$(awk -F'|' -v n="$p" '$13==n{print $1; exit}' "$M/devices.tsv")
    [[ -n $k ]] && p=$k
  fi
  printf '%s\n' "$p"
}
dev_filhos() { awk -F'|' -v k="$1" '{n=split($6,a,","); for(i=1;i<=n;i++) if(a[i]==k) print $1}' "$M/devices.tsv"; }
dev_mb() { local b; b=$(dev_campo "$1" 4); echo $(( ${b:-0} / 1048576 )); }
dev_set() {  # kname campo valor
  awk -F'|' -v OFS='|' -v k="$1" -v f="$2" -v v="$3" '$1==k{$f=v} {print}' "$M/devices.tsv" > "$M/.t" && mv "$M/.t" "$M/devices.tsv"
}
dev_prop() { dev_campo "$1" 12 | tr ';' '\n' | awk -F= -v k="$2" '$1==k{print substr($0,length(k)+2); exit}'; }

# relógio virtual: o sleep falso avança, o date falso mostra
relogio() {
  local base off real0
  base=$(cat "$M/relogio_base" 2>/dev/null || echo 0)
  real0=$(cat "$M/relogio_real0" 2>/dev/null || echo 0)
  off=$(cat "$M/relogio_off" 2>/dev/null || echo 0)
  if (( base > 0 )); then echo $(( base + $(/usr/bin/date +%s) - real0 + off )); else /usr/bin/date +%s; fi
}

humano() {  # bytes -> 512G
  awk -v b="$1" 'BEGIN{split("B K M G T P",u," "); i=1; while(b>=1024 && i<6){b/=1024; i++}
    if (b==int(b)) printf "%d%s\n", b, u[i]; else printf "%.1f%s\n", b, u[i]}'
}

# /sys/class/block falso (só nos cenários "# sysfs", que montam um tmpfs ali)
sysfs_dev() {  # kname
  local k=$1 S=/sys/class/block t p mm
  [[ -w $S ]] || return 0
  t=$(dev_campo "$k" 2); mm=$(dev_campo "$k" 3)
  mkdir -p "$S/$k/holders" "$S/$k/slaves"; echo "$mm" > "$S/$k/dev"
  [[ $t == part && $k != dm-* ]] && { echo "${k: -1}" > "$S/$k/partition"; echo 2048 > "$S/$k/start"; }
  if [[ $k == dm-* ]]; then
    mkdir -p "$S/$k/dm"; dev_campo "$k" 13 > "$S/$k/dm/name"
    for p in $(dev_campo "$k" 6 | tr ',' ' '); do
      ln -sfn "../../$p" "$S/$k/slaves/$p"; mkdir -p "$S/$p/holders"; ln -sfn "../../$k" "$S/$p/holders/$k"
    done
  fi
}
