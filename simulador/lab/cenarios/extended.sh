# host: racdb01
# rac-asmlib como cluster estendido entre dois sites: DATA tipo EXTEND (12.2+),
# SITEA/FG_SITEA (DSK_DATA_01..08), SITEB/FG_SITEB (DSK_DATA_09..16) e um disco de quorum.
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
sed -i 's/^1|DATA|MOUNTED|EXTERNAL|\(.*\)|0|$/1|DATA|MOUNTED|EXTEND|\1|524286|/' "$M/dg.tsv"
awk -F'|' -v OFS='|' '$1==1{n=$2+0; $5=(n<8?"FG_SITEA":"FG_SITEB"); $12=(n<8?"SITEA":"SITEB")} {print}' "$M/asm.tsv" > "$M/.x" && mv "$M/.x" "$M/asm.tsv"
disco sdz 1 "" pttype=gpt props="ID_SERIAL=36000c29ffff0000quorum0001"; disco sdz1 1 sdz; asmlib_label DSK_QUORUM_01 sdz1
disco_asm 1 16 DSK_QUORUM_01 ORCL:DSK_QUORUM_01 FG_QUORUM 1022 990 "-" QUORUM
