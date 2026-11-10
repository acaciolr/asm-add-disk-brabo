# host: racdb01
# rac-asmlib com nomes inconsistentes no DATA: DSK_DATA_4 (sem zero) convive com DSK_DATA_04.
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
sed -i 's/^DSK_DATA_04|/DSK_DATA_4|/' "$M/asmlib.tsv"; mv /dev/oracleasm/disks/DSK_DATA_04 /dev/oracleasm/disks/DSK_DATA_4
awk -F'|' -v OFS='|' '$3=="DSK_DATA_04"{$3="DSK_DATA_4"; $4="ORCL:DSK_DATA_4"; $5="DSK_DATA_4"} {print}' "$M/asm.tsv" > "$M/.x" && mv "$M/.x" "$M/asm.tsv"
