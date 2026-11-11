# host: vbrac1
# RAC 26ai (Grid/ASM 23.x) de 3 nós em VirtualBox (vbrac1, vbrac2, vbrac3), ASMLib v3
# (OL9/UEK7: SEM /dev/oracleasm/disks) e discos SEM /dev/disk/by-id (só ID_PATH).
# Reproduz a mudança real validada no lab: DATA NORMAL com usable_file_mb NEGATIVO,
# discos de 25 e 30 GB todos com TOTAL_MB 25596 no ASM (compatible.asm 23 → o ADD
# precisa de SIZE 25596M, senão ORA-15410). Disco novo: sdp 30 GB (SATA, ligado a quente).
# by • DBA BRABO
GRID_HOME=/u01/app/23.0.0/grid
grid 23.0.0.0.0 "vbrac1 vbrac2 vbrac3"
cfg POWER_LIMIT 1; cfg DISKSTRING "ORCL:*"; cfg ASMLIB_ESTILO orcl; cfg ASMLIB_V3 1; cfg CLUSTER vbrac-cluster
disco sda 60 "" pttype=dos
disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=1d0c7e55-0f2b-4f1e-9b7a-6a4c2d9e8f10"
disco sda2 59 sda sig="TYPE=LVM2_member;UUID=Zt8kQp-1aB2-cD3e-F4gH-i5J6-kL7m-N8oP9q"
i=0
for l in b c d e f g; do
  i=$((i+1)); n=$(printf '%02d' $i); g=25; (( i >= 5 )) && g=30
  disco sd$l $g "" pttype=gpt props="ID_PATH=pci-0000:00:14.0-scsi-0:0:$i:0"
  disco sd${l}1 $g sd$l
  asmlib_label DATA$n sd${l}1
done
i=0
for l in h i j; do i=$((i+1)); disco sd$l 5 "" pttype=gpt props="ID_PATH=pci-0000:00:14.0-scsi-0:0:$((i+6)):0"; disco sd${l}1 5 sd$l; asmlib_label OCR0$i sd${l}1; done
i=0
for l in k l; do i=$((i+1)); disco sd$l 25 "" pttype=gpt props="ID_PATH=pci-0000:00:14.0-scsi-0:0:$((i+9)):0"; disco sd${l}1 25 sd$l; asmlib_label RECO0$i sd${l}1; done
# disco novo: VDI de 30 GB no SATA porta 5, sem serial (sem by-id)
disco sdp 30 "" props="ID_PATH=pci-0000:00:0d.0-ata-6.0"
dg 1 DATA NORMAL 4 512 23.0.0.0.0 25596
dg 2 OCR NORMAL 4 512 23.0.0.0.0 5116
dg 3 RECO NORMAL 4 512 23.0.0.0.0 25596
for i in 1 2 3 4 5 6; do
  n=$(printf '%02d' $i); os=25598; (( i >= 5 )) && os=30718
  echo "1|$((i-1))|DATA$n|ORCL:DATA$n|DATA$n|25596|$os|MEMBER|ONLINE|NORMAL|REGULAR|-|2672" >> "$M/asm.tsv"
done
for i in 1 2 3; do disco_asm 2 $((i-1)) OCR0$i ORCL:OCR0$i OCR0$i 5116 2380; done
for i in 1 2; do disco_asm 3 $((i-1)) RECO0$i ORCL:RECO0$i RECO0$i 25596 15400; done
printf 'ORACLEASM_ENABLED=true\nORACLEASM_UID=grid\nORACLEASM_GID=asmdba\nORACLEASM_SCANBOOT=true\nORACLEASM_SCANORDER=""\nORACLEASM_SCANEXCLUDE=""\n' > /etc/sysconfig/oracleasm
cfg RATE 120
