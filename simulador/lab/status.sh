#!/bin/bash
# Simulador ASM ADD DISK BRABO — saída "bonita" do sqlplus para o --status. by • DBA BRABO
. /sim/lab/lib.sh
sql=$1
. /sim/lab/asm_lib.sh
g=$(sed -n "s/.*where name = '\([A-Z0-9_]*\)'.*/\1/p" <<<"$sql"); n=$(awk -F'|' -v g="$g" '$2==g{print $1}' "$D")
echo
awk -F'|' -v g="$g" -v a="$A" 'BEGIN{while((getline l < a)>0){split(l,x,"|"); t[x[1]]+=x[6]; fr[x[1]]+=x[13]}}
 $2==g{u=fr[$1]; if($4=="NORMAL")u=int((fr[$1]-$9)/2); if($4=="HIGH")u=int((fr[$1]-$9)/3)
  printf "NAME                 STATE      TYPE      TOTAL_MB    FREE_MB USABLE_FILE_MB REQUIRED_MIRROR_FREE_MB      AU_MB SECTOR_SIZE\n"
  printf "-------------------- ---------- ------- ---------- ---------- -------------- ----------------------- ---------- -----------\n"
  printf "%-20s %-10s %-7s %10d %10d %14d %23d %10d %11d\n", $2,$3,($4=="EXTERNAL"?"EXTERN":$4),t[$1],fr[$1],u,$9,$5,$6}' "$D"
echo; echo "==== Failgroups ===="; echo
printf '%-30s %-7s %10s %10s %10s\n' FAILGROUP FAILGRO DISCOS TOTAL_MB FREE_MB
printf '%-30s %-7s %10s %10s %10s\n' ------------------------------ ------- ---------- ---------- ----------
awk -F'|' -v n="$n" '$1==n{k=$5"|"$11; c[k]++; t[k]+=$6; f[k]+=$13} END{for(k in c){split(k,a,"|"); printf "%-30s %-7s %10d %10d %10d\n", a[1],a[2],c[k],t[k],f[k]}}' "$A" | sort
echo; echo "==== Discos (gv\$asm_disk) do $g e candidatos (grupo 0) ===="
echo
echo "                                       ASM Disks - General Information (From GV\$ASM_DISK)"
echo
printf '%-4s %5s %5s %-32s %9s %-7s %-12s %-8s %-8s %-20s %s\n' "" "ASM" "ASM" "" "Total" "" "" "" "" "" ""
printf '%-4s %5s %5s %-32s %9s %-7s %-12s %-8s %-8s %-20s %s\n' "" "Disk" "Disk" "" "Disk" "Mount" "Header" "Mode" "Disk" "" ""
printf '%-4s %5s %5s %-32s %9s %-7s %-12s %-8s %-8s %-20s %s\n' "Inst" "Grp #" "#" "ASM Disk Name" "Space(MB)" "Status" "Status" "Status" "State" "Failgroup" "OS Disk Path Name"
printf '%-4s %5s %5s %-32s %9s %-7s %-12s %-8s %-8s %-20s %s\n' ---- ----- ----- -------------------------------- --------- ------- ------------ -------- -------- -------------------- ----------------------------------------
for ((i=1; i<=NINST; i++)); do
  awk -F'|' -v n="$n" -v i="$i" '$1==n{printf "%4d %5d %5d %-32s %9d %-7s %-12s %-8s %-8s %-20s %s\n", i,$1,$2,$3,$6,"CACHED",$8,$9,$10,$5,$4}' "$A"
done | sort -k4,4 -k1,1n
c=$(cands)
if [[ -n $c ]]; then
  for ((i=1; i<=NINST; i++)); do awk -F'|' -v i="$i" '{printf "%4d %5d %5d %-32s %9d %-7s %-12s %-8s %-8s %-20s %s\n", i,0,0,"",$3,"CLOSED",$2,"ONLINE","NORMAL","",$1}' <<<"$c"; done | sort -k11,11 -k1,1n
fi
echo; echo "==== Operações (gv\$asm_operation) ===="; echo
ops_atual
if [[ -s $O.v ]]; then
  printf '%7s %-5s %-4s %5s %10s %10s %10s %11s %10s\n' INST_ID OPERA STAT POWER SOFAR EST_WORK EST_RATE EST_MINUTES ERROR_CODE
  printf '%7s %-5s %-4s %5s %10s %10s %10s %11s %10s\n' ------- ----- ---- ----- ---------- ---------- ---------- ----------- ----------
  awk -F'|' '{printf "%7d %-5s %-4s %5d %10d %10d %10d %11d %10s\n", $1,$2,$3,$4,$5,$6,$7,$8,""}' "$O.v"
else
  echo "no rows selected"
fi
