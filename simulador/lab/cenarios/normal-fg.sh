# host: racdb01
# rac-asmlib com o DATA em NORMAL redundancy espelhado entre dois storages:
# failgroups FG_STG1 (DSK_DATA_01..08) e FG_STG2 (DSK_DATA_09..16).
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
sed -i 's/^1|DATA|MOUNTED|EXTERNAL|\(.*\)|0|$/1|DATA|MOUNTED|NORMAL|\1|524286|/' "$M/dg.tsv"
awk -F'|' -v OFS='|' '$1==1{n=$2+0; $5=(n<8?"FG_STG1":"FG_STG2")} {print}' "$M/asm.tsv" > "$M/.x" && mv "$M/.x" "$M/asm.tsv"
