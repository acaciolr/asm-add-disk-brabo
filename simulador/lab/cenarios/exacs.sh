# host: exa01dbadm01
# A mesma Exadata, mas é um Exadata Cloud@Customer (tem dbaascli/creg): o script recusa.
# by • DBA BRABO
. /sim/lab/cenarios/exadata.sh
mkdir -p /var/opt/oracle/creg; printf '#!/bin/sh\necho dbaascli\n' > /usr/bin/dbaascli; chmod +x /usr/bin/dbaascli
