# host: racdb01
# sysfs
# rac-asmlib com /sys/class/scsi_host falso (para o --rescan escrever nos scan).
# by • DBA BRABO
. /sim/lab/cenarios/rac-asmlib.sh
for h in 0 1 2; do mkdir -p /sys/class/scsi_host/host$h; : > /sys/class/scsi_host/host$h/scan; done
