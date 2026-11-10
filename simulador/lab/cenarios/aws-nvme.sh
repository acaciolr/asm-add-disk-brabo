# host: ip-10-20-1-25
# Oracle Restart 19c numa instância EC2 Nitro (r6i), discos EBS gp3 (NVMe), ASMLib.
# DG DATA = DATA01..DATA04 em nvme1n1p1..nvme4n1p1. Volume novo: vol0abc123 (vira nvme5n1).
# by • DBA BRABO
grid 19.0.0.0.0 "ip-10-20-1-25"
cfg POWER_LIMIT 1; cfg DISKSTRING "ORCL:*"; cfg ASMLIB_ESTILO orcl; cfg RATE 450
disco nvme0n1 50 "" pttype=gpt props="ID_SERIAL=Amazon Elastic Block Store_vol0root00000000001"
disco nvme0n1p1 50 nvme0n1 montagem=/ sig="TYPE=xfs;UUID=f1e2d3c4-b5a6-4789-8a7b-6c5d4e3f2a1b"
vols=(vol0a1b2c3d4e5f60001 vol0a1b2c3d4e5f60002 vol0a1b2c3d4e5f60003 vol0a1b2c3d4e5f60004)
for i in 1 2 3 4; do
  v=${vols[$((i-1))]}
  disco nvme${i}n1 1024 "" pttype=gpt props="ID_SERIAL=Amazon Elastic Block Store_$v;ID_SERIAL_SHORT=$v;ID_MODEL=Amazon Elastic Block Store"
  disco nvme${i}n1p1 1024 nvme${i}n1; asmlib_label DATA0$i nvme${i}n1p1
  byid "nvme-Amazon_Elastic_Block_Store_$v" nvme${i}n1
done
disco nvme5n1 1024 "" props="ID_SERIAL=Amazon Elastic Block Store_vol0abc123;ID_SERIAL_SHORT=vol0abc123;ID_MODEL=Amazon Elastic Block Store"
byid nvme-Amazon_Elastic_Block_Store_vol0abc123 nvme5n1; byid nvme-nvme.1d0f-766f6c30616263313233-416d617a6f6e20456c617374696320426c6f636b2053746f7265-00000001 nvme5n1
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
for i in 1 2 3 4; do disco_asm 1 $((i-1)) DATA0$i ORCL:DATA0$i DATA0$i 1048574 $(( 150000 + i*2048 )); done
