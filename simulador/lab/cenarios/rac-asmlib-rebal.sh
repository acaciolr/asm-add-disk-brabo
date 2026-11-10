# host: racdb01
# rac-asmlib logo depois de um ADD: DSK_DATA_17 já entrou e o rebalance (power 4) está rodando.
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
disco sdt1 512 sdt; dev_set sdt 8 gpt; asmlib_label DSK_DATA_17 sdt1
disco_asm 1 16 DSK_DATA_17 ORCL:DSK_DATA_17 DSK_DATA_17 524286 300000
echo "1|REBAL|RUN|4|65535|T0|21400|1800" > "$M/ops.tsv"
