# shellcheck shell=bash
# Simulador ASM ADD DISK BRABO — visão do ASM sobre o mundo (candidatos, rebalance). by • DBA BRABO
D=$M/dg.tsv     # num|nome|estado|tipo|au_mb|setor|compatibility|compatible.asm|req_mirror_free|atributos(;)
A=$M/asm.tsv    # grp|dnum|nome|path|fg|total|os_mb|header|mode|state|fg_type|site|free
O=$M/ops.tsv    # inst|op|state|power|work|relogio_inicio|sofar_inicio|rate
touch "$A" "$O"; RATE=${RATE:-1500}

dgnum() { awk -F'|' -v n="$1" '$2==n{print $1}' "$D"; }
em_asm() { awk -F'|' -v p="$1" '$4==p{f=1} END{exit !f}' "$A"; }
size_mb() { awk -v s="$1" 'BEGIN{u=substr(s,length(s)); v=substr(s,1,length(s)-1)+0; if(u=="T")v*=1048576; else if(u=="G")v*=1024; printf "%d\n", v}'; }

# discos que o ASM enxerga fora de diskgroup: path|header|os_mb
cands() {
  local l k p pat x mb ip c
  if [[ -s $M/asmlib.tsv ]]; then
    while IFS='|' read -r l k; do
      [[ ${ASMLIB_ESTILO:-orcl} == devasm ]] && p=/dev/oracleasm/disks/$l || p=ORCL:$l
      em_asm "$p" || echo "$p|PROVISIONED|$(dev_mb "$k")"
    done < "$M/asmlib.tsv"
  fi
  if [[ -s $M/afd.tsv ]]; then
    while IFS='|' read -r l k; do em_asm "AFD:$l" || echo "AFD:$l|PROVISIONED|$(dev_mb "$k")"; done < "$M/afd.tsv"
  fi
  IFS=',' read -r -a pats <<<"$DISKSTRING"
  for pat in "${pats[@]}"; do
    pat=${pat//\'/}; pat=${pat// /}
    case $pat in ORCL:*|AFD:*|o/*|"") continue ;; esac
    for x in $pat; do
      [[ -b $x || -c $x ]] || continue
      [[ $(stat -L -c %U "$x") == grid ]] || continue
      em_asm "$x" && continue
      if [[ $x == /dev/rhdisk* || $x == /dev/rdsk/* ]]; then mb=$(awk -F'|' -v d="${x#/dev/r}" '$1==d{print $7}' "$M/aix.tsv" 2>/dev/null); mb=${mb:-$(cat "$M/rdsk_mb" 2>/dev/null)}
      else mb=$(dev_mb "$(kname_de "$x")"); fi
      echo "$x|CANDIDATE|${mb:-0}"
    done
  done
  for c in "$M"/cells/*/; do
    [[ -d $c ]] || continue
    ip=$(cat "$c/ip")
    while IFS='|' read -r l s st am t g; do [[ -z $g ]] && echo "o/$ip/$l|CANDIDATE|$(size_mb "$s")"; done < "$c/griddisks.tsv"
  done
}

# rebalance: progresso pelo relógio virtual. ops.tsv guarda o ponto de partida;
# ops.v (gerado) tem as colunas que o script lê. Rebalance que termina some.
ops_atual() {
  : > "$O.v"; [[ -s $O ]] || return 0
  awk -F'|' -v OFS='|' -v t="$(relogio)" -v vf="$O.v" '{
     sofar=$7; if ($3=="RUN" && $4>0) sofar=$7+int((t-$6)*$8/60); if (sofar>$5) sofar=$5
     if ($3=="RUN" && sofar>=$5) next
     est=($3=="RUN" && $8>0) ? int(($5-sofar)/$8+0.99) : 0
     pass=($5>0 && sofar/$5>.93) ? "COMPACT" : "REBALANCE"
     print $1,$2,$3,$4,sofar,$5,($3=="RUN"?$8:0),est,"-",pass > vf
     print }' "$O" > "$O.n"; mv "$O.n" "$O"
}

