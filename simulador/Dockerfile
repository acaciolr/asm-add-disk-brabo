#==============================================================================
#   ____  ____    _      ____  ____      _    ____   ___
#  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#  Simulador do ASM ADD DISK BRABO: Oracle Linux 7 com Grid/ASM, storage,
#  ASMLib, ASMFD, udev, multipath, AIX e cells Exadata FALSOS.
#  Nenhum Oracle de verdade, nenhum disco de verdade.
#  by • DBA BRABO
#==============================================================================
FROM oraclelinux:7-slim
RUN yum -y install procps-ng util-linux hostname expect && yum clean all && rm -rf /var/cache/yum
COPY lab/ /sim/lab/
RUN chmod +x /sim/lab/bin/* /sim/lab/grid/* /sim/lab/*.sh /sim/lab/*.exp \
 && for f in /sim/lab/bin/*; do ln -sf "$f" "/usr/sbin/$(basename "$f")"; done \
 && mkdir -p /usr/lib/udev && ln -sf /sim/lab/bin/scsi_id /usr/lib/udev/scsi_id
ENTRYPOINT ["/sim/lab/entrada.sh"]
