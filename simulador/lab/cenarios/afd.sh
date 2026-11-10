# host: dbafd01
# RAC 19c (dbafd01, dbafd02) com ASM Filter Driver. DG DATA = AFD:DATA1..DATA6, discos inteiros.
# Disco novo: sdk (512 GiB).
# by • DBA BRABO
grid 19.0.0.0.0 "dbafd01 dbafd02"
cfg POWER_LIMIT 1; cfg DISKSTRING "AFD:*"; cfg RATE 450
disco sda 100 "" pttype=dos; disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
i=0
for l in c d e f g h; do
  i=$((i+1)); disco sd$l 512 "" props="ID_SERIAL=36000c29d$i$i$i$i$i$i${i}4b2a9f1e7c3d5a0b"; echo "DATA$i|sd$l" >> "$M/afd.tsv"
done
disco sdk 512 "" props="ID_SERIAL=36000c29e77777774b2a9f1e7c3d5a0c;ID_WWN=0x6000c29e7777777"
byid scsi-36000c29e77777774b2a9f1e7c3d5a0c sdk; byid wwn-0x6000c29e7777777 sdk
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
for i in $(seq 1 6); do disco_asm 1 $((i-1)) DATA$i AFD:DATA$i DATA$i 524288 $(( 90000 + i*1024 )); done
