# host: dbprd01
# Oracle Restart 19c (single instance) com ASMLib. DG DATA com labels DATA_0001..0006.
# sdj já tem uma partição sdj1 criada pelo time de storage, vazia.
# by • DBA BRABO
grid 19.0.0.0.0 "dbprd01"
cfg POWER_LIMIT 2; cfg DISKSTRING "ORCL:*"; cfg ASMLIB_ESTILO orcl; cfg RATE 450
disco sda 80 "" pttype=dos; disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=11d2b2e3-0f6b-4d52-9e57-5c1e4f2a9b10"; disco sda2 79 sda sig="TYPE=LVM2_member;UUID=Zt8kQp-1aB2-cD3e-fG4h-iJ5k-lM6n-oP7qRs"
i=0
for l in b c d e f g; do
  i=$((i+1)); n=$(printf '%04d' $i)
  disco sd$l 256 "" pttype=gpt props="ID_SERIAL=3600508b1001c7e3f8a2b4d6e8f0a1b$i"; disco sd${l}1 256 sd$l
  asmlib_label DATA_$n sd${l}1
done
disco sdj 256 "" pttype=gpt props="ID_SERIAL=3600508b1001c7e3f8a2b4d6e8f0a1c9"; disco sdj1 256 sdj
byid scsi-3600508b1001c7e3f8a2b4d6e8f0a1c9 sdj; byid scsi-3600508b1001c7e3f8a2b4d6e8f0a1c9-part1 sdj1
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
for i in $(seq 1 6); do n=$(printf '%04d' $i); disco_asm 1 $((i-1)) DATA_$n ORCL:DATA_$n DATA_$n 262142 $(( 40000 + i*512 )); done
printf 'ORACLEASM_ENABLED=true\nORACLEASM_UID=grid\nORACLEASM_GID=asmadmin\nORACLEASM_SCANORDER=""\n' > /etc/sysconfig/oracleasm
