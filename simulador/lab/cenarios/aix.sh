# host: aixrac01
# RAC 19c em AIX 7.2 (aixrac01, aixrac02), discos raw /dev/rhdisk*. DG DATA = DATA_0000..0007.
# LUNs novas: hdisk12 e hdisk13 (no aixrac02 elas são hdisk14 e hdisk15), reserve_policy=single_path.
# by • DBA BRABO
grid 19.0.0.0.0 "aixrac01 aixrac02"
cfg SIM_OS AIX; cfg POWER_LIMIT 1; cfg DISKSTRING "/dev/rhdisk*"; cfg RATE 450
: > "$M/aix.tsv"; : > "$M/devices.tsv"
echo "hdisk0|Available|00f9a1b2c3d4e5f6|rootvg|single_path|3E213600A0B80001|146800" >> "$M/aix.tsv"
for i in $(seq 2 9); do
  echo "hdisk$i|Available|none|None|no_reserve|3E2136005076802810E9D8000000000000$i|524288" >> "$M/aix.tsv"
  mknod /dev/rhdisk$i c 20 $i; mknod /dev/hdisk$i b 20 $i; chown grid:asmadmin /dev/rhdisk$i; chmod 660 /dev/rhdisk$i
done
for i in 12 13; do
  echo "hdisk$i|Available|none|None|single_path|3E2136005076802810E9D80000000000$i|524288" >> "$M/aix.tsv"
  mknod /dev/rhdisk$i c 20 $i; mknod /dev/hdisk$i b 20 $i; chmod 600 /dev/rhdisk$i
  r=$((i+2)); mknod /dev/rhdisk$r c 20 $r; chmod 600 /dev/rhdisk$r; echo "hdisk$i|hdisk$r" >> "$M/aixmap.tsv"; echo "/dev/rhdisk$i|/dev/rhdisk$r" >> "$M/map.tsv"
done
echo "hdisk10|Available|00f9a1b2c3d4ffff|oravg|single_path|3E213600A0B80010|262144" >> "$M/aix.tsv"
dg 1 DATA EXTERNAL 4 512 19.0.0.0.0
for i in $(seq 0 7); do disco_asm 1 $i DATA_000$i /dev/rhdisk$((i+2)) DATA_000$i 524288 $(( 60000 + i*1000 )); done
