# host: racprd01
# sysfs
# RAC 19c (racprd01, racprd02) em storage FC com multipath (2 caminhos por LUN) e ASMLib
# (ORACLEASM_SCANORDER=dm). DG DATA = ASM_DATA01..08 em mpatha..mpathh (partição 1).
# LUNs novas: mpathk e mpathl, sem partição.
# by • DBA BRABO
grid 19.0.0.0.0 "racprd01 racprd02"
cfg POWER_LIMIT 1; cfg DISKSTRING "ORCL:*"; cfg ASMLIB_ESTILO orcl; cfg RATE 450
disco sda 100 "" pttype=dos; disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=0b6e1c2d-3f4a-4b5c-8d6e-7f8091a2b3c4"
mp=(a b c d e f g h k l); idx=1; dmn=0
for x in "${mp[@]}"; do
  w=$(printf '3600a098038304437%02d5d4a6e4f6b4a%02d' $idx $idx)
  p1=$(printf "sd\\x$(printf %x $((97+idx*2-1)))"); p2=$(printf "sd\\x$(printf %x $((97+idx*2)))")
  [[ $idx -ge 13 ]] && { p1=sda$idx; p2=sdb$idx; }
  disco $p1 500 "" props="ID_SERIAL=$w"; disco $p2 500 "" props="ID_SERIAL=$w"
  disco dm-$dmn 500 "$p1,$p2" dm=mpath$x props="DM_NAME=mpath$x;DM_UUID=mpath-$w"
  byid dm-uuid-mpath-$w dm-$dmn; byid dm-name-mpath$x dm-$dmn
  if [[ $x < k ]]; then
    dev_set dm-$dmn 8 gpt
    disco dm-$((dmn+1)) 500 dm-$dmn tipo=part dm=mpath${x}1 props="DM_NAME=mpath${x}1;DM_UUID=part1-mpath-$w"
    asmlib_label ASM_DATA0$idx dm-$((dmn+1)); dmn=$((dmn+2))
  else dmn=$((dmn+1)); fi
  idx=$((idx+1))
done
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
for i in $(seq 1 8); do disco_asm 1 $((i-1)) ASM_DATA0$i ORCL:ASM_DATA0$i ASM_DATA0$i 511998 $(( 70000 + i*1024 )); done
printf 'ORACLEASM_ENABLED=true\nORACLEASM_UID=grid\nORACLEASM_GID=asmadmin\nORACLEASM_SCANORDER="dm"\nORACLEASM_SCANEXCLUDE="sd"\n' > /etc/sysconfig/oracleasm
