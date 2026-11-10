# host: exa01dbadm01
# Exadata X8M-2 on-premises, 2 nós de banco (exa01dbadm01/02), 3 cells HC no DATA e no RECO
# (HIGH redundancy, 12 griddisks por cell). Storage expansion: as cells exa01celadm04 e
# exa01celadm05 chegaram com os griddisks DATA_* e RECO_* já criados (UNUSED).
#   EXA_NOVAS="04"            só a cell 04, sem griddisks (para --exa-create-griddisk)
#   EXA_PREFIXO=DATAC1        nomes no padrão novo do OEDA (DATAC1/RECOC1)
# by • DBA BRABO
grid 19.0.0.0.0 "exa01dbadm01 exa01dbadm02"
cfg POWER_LIMIT 4; cfg DISKSTRING "o/*/*"; cfg RATE 120000
: > "$M/devices.tsv"
PD=${EXA_PREFIXO:-DATA}; PR=${EXA_PREFIXO_RECO:-RECO}
SD=5695488; SR=1458176          # MB: DATA 5562G e RECO 1424G por griddisk
mkdir -p /etc/oracle/cell/network-config
: > /etc/oracle/cell/network-config/cellip.ora
cell() {  # cell <nn> <ip1> <ip2> <no_dg: sim|nao> <griddisks: sim|nao>
  local h=exa01celadm$1 C=$M/cells/exa01celadm$1 i cd
  mkdir -p "$C"; echo "$h" > "$C/nome"; echo online > "$C/status"; echo "$2;$3" > "$C/ip"
  : > "$C/griddisks.tsv"; : > "$C/celldisks.tsv"
  echo "cell=\"$2;$3\"" >> /etc/oracle/cell/network-config/cellip.ora   # expansão: as cells novas já entram no cellip.ora
  for i in $(seq 0 11); do
    cd=$(printf 'CD_%02d_%s' $i "$h")
    if [[ $5 == sim ]]; then echo "$cd|HardDisk|normal|0" >> "$C/celldisks.tsv"
      if [[ $4 == sim ]]; then
        echo "${PD}_$cd|${SD}M|active|ONLINE|HardDisk|$PD" >> "$C/griddisks.tsv"; echo "${PR}_$cd|${SR}M|active|ONLINE|HardDisk|$PR" >> "$C/griddisks.tsv"
      else
        echo "${PD}_$cd|${SD}M|active|UNUSED|HardDisk|" >> "$C/griddisks.tsv"; echo "${PR}_$cd|${SR}M|active|UNUSED|HardDisk|" >> "$C/griddisks.tsv"
      fi
    else echo "$cd|HardDisk|normal|7.1T" >> "$C/celldisks.tsv"; fi
  done
}
cell 01 192.168.10.1 192.168.10.2 sim sim
cell 02 192.168.10.3 192.168.10.4 sim sim
cell 03 192.168.10.5 192.168.10.6 sim sim
if [[ ${EXA_NOVAS:-04 05} == "04" ]]; then cell 04 192.168.10.7 192.168.10.8 nao nao
else cell 04 192.168.10.7 192.168.10.8 nao sim; cell 05 192.168.10.9 192.168.10.10 nao sim; fi
dg 1 "$PD" HIGH 4 512 19.0.0.0.0 $(( SD * 12 )) "appliance.mode=TRUE;cell.smart_scan_capable=TRUE;compatible.rdbms=19.0.0.0.0;content.type=data"
dg 2 "$PR" HIGH 4 512 19.0.0.0.0 $(( SR * 12 )) "appliance.mode=TRUE;cell.smart_scan_capable=TRUE;compatible.rdbms=19.0.0.0.0;content.type=recovery"
for c in 01 02 03; do
  ip=$(cat "$M/cells/exa01celadm$c/ip")
  for i in $(seq 0 11); do
    nm=$(printf 'CD_%02d_EXA01CELADM%s' $i $c); lc=$(printf 'CD_%02d_exa01celadm%s' $i $c)
    disco_asm 1 $(( (10#$c-1)*12 + i )) "${PD}_$nm" "o/$ip/${PD}_$lc" "EXA01CELADM$c" $SD 2600000
    disco_asm 2 $(( (10#$c-1)*12 + i )) "${PR}_$nm" "o/$ip/${PR}_$lc" "EXA01CELADM$c" $SR 802816
  done
done
