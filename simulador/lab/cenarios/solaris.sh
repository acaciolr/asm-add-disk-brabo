# host: solsrv01
# Oracle Restart 19c em Solaris 11 SPARC. DG DATA = DATA_0000..0006 em /dev/rdsk/c0t*d0s6.
# O slice novo c0t5d0s6 já foi preparado pelo SA (dono grid:asmadmin, 660).
# by • DBA BRABO
grid 19.0.0.0.0 "solsrv01"
cfg SIM_OS SunOS; cfg POWER_LIMIT 1; cfg DISKSTRING "/dev/rdsk/c0t*d0s6"; cfg RATE 450
: > "$M/devices.tsv"; mkdir -p /dev/rdsk /var/opt/oracle; cp /etc/oracle/olr.loc /var/opt/oracle/olr.loc
echo 204800 > "$M/rdsk_mb"
for t in 1 2 3 4 6 7 8; do mknod /dev/rdsk/c0t${t}d0s6 c 118 $((t*8+6)); chown grid:asmadmin /dev/rdsk/c0t${t}d0s6; chmod 660 /dev/rdsk/c0t${t}d0s6; done
mknod /dev/rdsk/c0t5d0s6 c 118 46; chown grid:asmadmin /dev/rdsk/c0t5d0s6; chmod 660 /dev/rdsk/c0t5d0s6
dg 1 DATA EXTERNAL 1 512 19.0.0.0.0
i=0; for t in 1 2 3 4 6 7 8; do disco_asm 1 $i DATA_000$i /dev/rdsk/c0t${t}d0s6 DATA_000$i 204800 $(( 30000 + i*500 )); i=$((i+1)); done
