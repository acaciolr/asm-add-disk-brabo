# host: racdb01
# RAC 19c de 2 nós (racdb01, racdb02) com ASMLib. DG DATA (EXTERNAL, 16 x 512 GiB,
# discos particionados GPT, labels DSK_DATA_01..16) e DG RECO. Discos novos:
#   sdt, sdu  512 GiB livres (os bons)      sdv 512 GiB com lixo no início
#   sdw       256 GiB (tamanho diferente)   sdx 512 GiB com header ASM antigo
#   sdb       /u01 montado                  sda disco do SO (LVM)
# by • DBA BRABO
grid 19.0.0.0.0 "racdb01 racdb02"
cfg POWER_LIMIT 1; cfg DISKSTRING "ORCL:*"; cfg ASMLIB_ESTILO orcl
disco sda 100 "" pttype=dos
disco sda1 1 sda montagem=/boot sig="TYPE=xfs;UUID=6c1f0b2e-1d7a-4f43-9a51-0c3e9f1b7d21"
disco sda2 99 sda sig="TYPE=LVM2_member;UUID=Qm3kTz-8pXr-4hFh-dE2s-oA1x-Kc9L-7vB2nW"
disco sdb 200 "" montagem=/u01 sig="TYPE=xfs;UUID=a3f6c2d9-77b1-4f0e-8d0a-2b9e6c1f4a83"
i=0
for l in c d e f g h i j k l m n o p q r; do
  i=$((i+1)); n=$(printf '%02d' $i)
  disco sd$l 512 "" pttype=gpt props="ID_SERIAL=36000c29${n}a1b2c3d4e5f6a7b8c9d0e1f2;ID_WWN=0x6000c29${n}a1b2c3d4"
  disco sd${l}1 512 sd$l
  asmlib_label DSK_DATA_$n sd${l}1
done
disco sds 200 "" pttype=gpt props="ID_SERIAL=36000c2917b2c3d4e5f6a7b8c9d0e1f20"; disco sds1 200 sds; asmlib_label DSK_RECO_01 sds1
s=0
for l in t u v w x; do
  s=$((s+1)); g=512; [[ $l == w ]] && g=256
  o=(); [[ $l == v ]] && o+=(sujo=1)
  disco sd$l $g "" ${o[@]+"${o[@]}"} props="ID_SERIAL=36000c29f$s$s$s$s$s$s${s}e8d2c41b9a7f03e5;ID_WWN=0x6000c29f$s$s$s$s$s$s${s}e8d2;ID_SCSI_SERIAL=6000c29f$s$s$s$s"
  byid "scsi-36000c29f$s$s$s$s$s$s${s}e8d2c41b9a7f03e5" sd$l
  byid "wwn-0x6000c29f$s$s$s$s$s$s${s}e8d2" sd$l
done
echo "sdx|MEMBER|OLD_DATA" > "$M/cabecalhos.tsv"
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
dg 2 RECO EXTERNAL 4 512 19.0.0.0.0
for i in $(seq 1 16); do n=$(printf '%02d' $i); disco_asm 1 $((i-1)) DSK_DATA_$n ORCL:DSK_DATA_$n DSK_DATA_$n 524286 $(( 81920 + i*1024 )); done
disco_asm 2 0 DSK_RECO_01 ORCL:DSK_RECO_01 DSK_RECO_01 204798 61440
printf 'ORACLEASM_ENABLED=true\nORACLEASM_UID=grid\nORACLEASM_GID=asmadmin\nORACLEASM_SCANBOOT=true\nORACLEASM_SCANORDER=""\nORACLEASM_SCANEXCLUDE=""\n' > /etc/sysconfig/oracleasm
cfg RATE 450
cat > /home/grid/.profile_infra <<'P'
# perfil do time de infra (exemplo 17)
export ORACLE_BASE=/u01/app/grid
export ORACLE_HOME=/u01/app/19.0.0/grid
export ORACLE_SID=+ASM1
export PATH=$ORACLE_HOME/bin:$PATH
P
chown grid:oinstall /home/grid/.profile_infra; chmod 644 /home/grid/.profile_infra
