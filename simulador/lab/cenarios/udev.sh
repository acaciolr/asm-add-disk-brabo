# host: orarac01
# RAC 19c (orarac01, orarac02) com regras udev (scsi_id na partição), sem ASMLib/AFD.
# DG RECO = /dev/asmdisks/DSK_RECO_01..04 (sdh1..sdk1). Disco novo: sdm (256 GiB).
# by • DBA BRABO
grid 19.0.0.0.0 "orarac01 orarac02"
cfg POWER_LIMIT 1; cfg DISKSTRING "/dev/asmdisks/*"; cfg RATE 450
disco sda 100 "" pttype=dos; disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=3c2b1a09-8f7e-4d6c-9b5a-493827160514"
R=/etc/udev/rules.d/99-oracle-asmdevices.rules; mkdir -p /etc/udev/rules.d /dev/asmdisks
echo '# Discos do ASM (time DBA) - nao editar a mao' > $R
i=0
for l in h i j k; do
  i=$((i+1)); n=$(printf '%02d' $i); w=36000c2961a${i}b2c3d4e5f60718293a4b5c$i
  disco sd$l 256 "" pttype=gpt props="ID_SERIAL=$w"; disco sd${l}1 256 sd$l
  echo "KERNEL==\"sd?1\", SUBSYSTEM==\"block\", PROGRAM==\"/usr/lib/udev/scsi_id -g -u -d /dev/\$parent\", RESULT==\"$w\", SYMLINK+=\"asmdisks/DSK_RECO_$n\", OWNER=\"grid\", GROUP=\"asmadmin\", MODE=\"0660\"" >> $R
  chown grid:asmadmin /dev/sd${l}1; ln -sfn /dev/sd${l}1 /dev/asmdisks/DSK_RECO_$n
done
cp -p $R /sim/nos/orarac02/rules.d/
disco sdm 256 "" props="ID_SERIAL=36000c2961a9b2c3d4e5f60718293a4b5c9;ID_WWN=0x6000c2961a9b2c3d"
byid scsi-36000c2961a9b2c3d4e5f60718293a4b5c9 sdm; byid wwn-0x6000c2961a9b2c3d sdm
dg 2 RECO EXTERNAL 4 512 19.0.0.0.0
for i in 1 2 3 4; do n=$(printf '%02d' $i); disco_asm 2 $((i-1)) DSK_RECO_$n /dev/asmdisks/DSK_RECO_$n DSK_RECO_$n 262142 $(( 120000 + i*512 )); done
