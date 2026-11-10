# host: racdb01
# rac-asmlib sem ssh root sem senha entre os nós (política da empresa).
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
echo racdb02 > "$M/ssh_falha"
