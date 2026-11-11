# shellcheck shell=bash
# Simulador ASM ADD DISK BRABO — funções para montar um cenário (o "mundo"). by • DBA BRABO
. /sim/lab/lib.sh
GRID_HOME=/u01/app/19.0.0/grid

cfg() { printf '%s=%q\n' "$1" "$2" >> "$M/cfg"; eval "$1=\$2"; }

grid() {  # grid <versão> <nós> [sid_local]
  local n
  groupadd -g 54321 oinstall; groupadd -g 54327 asmdba; groupadd -g 54328 asmadmin
  useradd -u 54331 -g oinstall -G asmdba,asmadmin grid
  mkdir -p "$GRID_HOME/bin" "$GRID_HOME/lib" /u01/app/grid /etc/oracle /dev/disk/by-id /dev/mapper
  cp /sim/lab/grid/* "$GRID_HOME/bin/"; chown -R grid:oinstall /u01
  echo "olrconfig_loc=$GRID_HOME/cdata/$(hostname -s).olr" > /etc/oracle/olr.loc
  echo "crs_home=$GRID_HOME" >> /etc/oracle/olr.loc
  echo "${3:-+ASM1}:$GRID_HOME:N" > /etc/oratab
  cfg VER "$1"; cfg NODES "$2"; cfg LOCAL "$(hostname -s)"; cfg SID_LOCAL "${3:-+ASM1}"
  set -- $2; cfg NINST "$#"
  for n in $NODES; do [[ $n == "$(hostname -s)" ]] || mkdir -p "/sim/nos/$n/rules.d"; done
}

mm_de() {  # kname -> maj:min no padrão do Linux
  local k=$1 i l n
  case $k in
    sd[a-z]|sd[a-z][a-z])
      l=${k#sd}; i=0
      for ((n=0; n<${#l}; n++)); do i=$(( i*26 + $(printf '%d' "'${l:n:1}") - 96 )); done; i=$((i-1))
      if (( i < 16 )); then echo "8:$((i*16))"; else echo "65:$(((i-16)*16))"; fi ;;
    nvme*n1) n=${k#nvme}; n=${n%n1}; echo "259:$((n*2))" ;;
    dm-*) echo "253:${k#dm-}" ;;
    xvd[a-z]) i=$(( $(printf '%d' "'${k#xvd}") - 97 )); echo "202:$((i*16))" ;;
  esac
}

# disco <kname> <tamanho em GiB> [pais] [k=v ...]   (tipo deduzido: sdX1/nvme..p1 = part, dm-N = mpath)
#   opções: tipo= montagem= pttype= sig= sujo=1 aberto=<proc> props=<K=V;K=V> dm=<nome> mb=<MiB exato> setor=
disco() {
  local k=$1 g=$2 pais=${3:-} tipo=disk mnt="" pt="" sig="" sujo="" ab="" props="" dm="" setor=512 mb="" mm o pm
  shift 3 2>/dev/null || shift $#
  for o; do case $o in tipo=*) tipo=${o#*=} ;; montagem=*) mnt=${o#*=} ;; pttype=*) pt=${o#*=} ;; sig=*) sig=${o#*=} ;;
    sujo=*) sujo=1 ;; aberto=*) ab=${o#*=} ;; props=*) props=${o#*=} ;; dm=*) dm=${o#*=} ;; setor=*) setor=${o#*=} ;; mb=*) mb=${o#*=} ;; esac; done
  if [[ -n $pais && $tipo == disk && $k != dm-* ]]; then tipo=part; fi
  [[ $k == dm-* && $tipo == disk ]] && tipo=mpath
  if [[ $tipo == part && $k != dm-* ]]; then pm=$(dev_campo "$pais" 3); mm="${pm%:*}:$(( ${pm#*:} + ${k: -1} ))"; else mm=$(mm_de "$k"); fi
  local bytes=$(( g * 1073741824 )); [[ -n $mb ]] && bytes=$(( mb * 1048576 ))
  [[ $tipo == part && -z $mb ]] && bytes=$(( bytes - 2097152 ))
  echo "$k|$tipo|$mm|$bytes|$setor|$pais|$mnt|$pt|$sig|$sujo|$ab|$props|$dm" >> "$M/devices.tsv"
  mknod "/dev/$k" b "${mm%:*}" "${mm#*:}"; chgrp disk "/dev/$k"; chmod 660 "/dev/$k"
  [[ -n $dm ]] && ln -sfn "../$k" "/dev/mapper/$dm"
  sysfs_dev "$k"
  return 0
}
byid() { ln -sfn "../../$2" "/dev/disk/by-id/$1"; }

asmlib_label() {  # label kname
  local mm; mm=$(dev_campo "$2" 3)
  echo "$1|$2" >> "$M/asmlib.tsv"
  if [[ -n ${ASMLIB_V3:-} ]]; then   # v3: sem /dev/oracleasm/disks; device com o dono do iofilter
    dev_set "$2" 9 "TYPE=oracleasm;LABEL=$1"; mkdir -p /dev/disk/by-label; ln -sfn "../../$2" "/dev/disk/by-label/$1"
    chown grid:asmdba "/dev/$2"; chmod 660 "/dev/$2"; return 0
  fi
  mkdir -p /dev/oracleasm/disks
  mknod "/dev/oracleasm/disks/$1" b "${mm%:*}" "${mm#*:}"; chown grid:asmadmin "/dev/oracleasm/disks/$1"; chmod 660 "/dev/oracleasm/disks/$1"
}

# dg <num> <nome> <EXTERNAL|NORMAL|HIGH|FLEX|EXTEND> <au_mb> <setor> <compatible.asm> [req_mirror_free] [atributos]
dg() { echo "$1|$2|MOUNTED|$3|$4|$5|$6|$6|${7:-0}|${8:-}" >> "$M/dg.tsv"; }
# disco_asm <grp> <num> <nome> <path> <failgroup> <os_mb> <free_mb> [site] [fg_type] [mode] [state]
disco_asm() { echo "$1|$2|$3|$4|$5|$6|$6|MEMBER|${10:-ONLINE}|${11:-NORMAL}|${9:-REGULAR}|${8:--}|$7" >> "$M/asm.tsv"; }
