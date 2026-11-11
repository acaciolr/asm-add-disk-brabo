# host: vbrac1
# vbox-asmlib3 com um filesystem ACFS OFFLINE no vbrac3 (TARGET ONLINE): recurso de
# ASM fora do estado esperado no Clusterware — a adição deve parar antes de tudo.
# by • DBA BRABO
. /sim/lab/cenarios/vbox-asmlib3.sh
echo "ora.data.acfsvol01.acfs|ora.acfs.type|vbrac3|OFFLINE|ONLINE|" >> "$M/crs_extra.tsv"
