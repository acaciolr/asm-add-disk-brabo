#!/usr/bin/env bash
#==============================================================================
#   ____  ____    _      ____  ____      _    ____   ___
#  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
#  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
#  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
#  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
#
#        ASM ADD DISK BRABO — adição SEGURA de discos no Oracle ASM
#==============================================================================
# Script   : asm_add_disk_brabo.sh
# Versão   : 1.1.0 (2026-11-10) — + modo Exadata (griddisks via cellcli)
# Autor    : Acácio Lima Rocha — DBA BRABO — https://dbabrabo.com.br
#
# PADRÃO = DRY-RUN. Nada é alterado sem --execute.
# Documentação completa e exemplos:  ./asm_add_disk_brabo.sh --help
#
# Suporta: Linux (ASMLib, ASMFD/AFD, udev; disco SCSI/virtio/xvd/NVMe/
#          multipath/AWS EBS) | AIX (rhdisk raw) | Solaris e outros via
#          --add-only | Standalone, Oracle Restart, RAC e Flex ASM |
#          Diskgroups EXTERNAL/NORMAL/HIGH/FLEX/EXTENDED | ASM 11.2 a 23ai |
#          Exadata on-premises (griddisks via cellcli, com criação opcional)
#==============================================================================

set -o nounset
set -o pipefail
shopt -u patsub_replacement 2>/dev/null || true
umask 077
export LC_ALL=C
PATH="/usr/sbin:/sbin:/usr/bin:/bin:${PATH:-}"; export PATH

readonly SCRIPT_NAME="asm_add_disk_brabo.sh"
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DATE="2026-11-10"
RUN_TS=$(date '+%Y%m%d_%H%M%S')

#------------------------------------------------------------------------------
# Parâmetros (defaults)
#------------------------------------------------------------------------------
ACTION="add"; ACTION_SET=0
DG=""; DISKS_IN=()
POWER=""; NO_REBAL=0; MON_WAIT=0; WAIT_TIMEOUT=0; POLL=30; SET_POWER=""
METHOD="auto"
PREFIX=""; WIDTH=""; START_NUM=""; LABELS_IN=""; NAMES_IN=""
PART_MODE="auto"; PTTYPE="auto"; USE_EXISTING_PART=0
FAILGROUPS_IN=""; SITES_IN=""; ALLOW_NEW_FG=0
GRID_USER=""; GRID_HOME=""; ASM_SID=""; ORA_BASE=""; ENV_FILE=""
OWNER=""; GROUP=""; PERM=""
NODES_IN=""; REMOTE_MODE="auto"
SIZE_TOL=2; ALLOW_SIZE_MISMATCH=0; ALLOW_DIRTY=0; ALLOW_RUNNING_OP=0
ALLOW_UNHEALTHY=0; FIX_AIX_ATTRS=0
EXECUTE=0; ASSUME_YES=0; NO_COLOR=0
EXA_CELLS=""; EXA_PREFIX=""; EXA_USER="root"; EXA_CREATE=0; EXA_SIZE=""; EXA_ALLOW_PARTIAL=0
LOG_DIR="/var/log/dbabrabo"

#------------------------------------------------------------------------------
# Estado de execução
#------------------------------------------------------------------------------
OS=""; CUR_USER=""; TMPD=""; LOG_FILE=""; LOCK_HELD=0; PHASE="init"
LOCK_DIR="/var/tmp/asm_add_disk_brabo.lock"
UNDO=(); MANUAL_Q=(); WARN_COUNT=0; GEN_OUT=()
ASM_VER=""; INST_COUNT=1; ASM_POWER_LIMIT=""; ASM_DISKSTRING=""
IS_RAC=0; NODES=(); LOCAL_NODE=""; REMOTE_NODES=()
DG_NUM=0; DG_STATE=""; DG_TYPE=""; DG_TOTAL=0; DG_FREE=0; DG_USABLE=0
DG_AU=0; DG_SECTOR=0; DG_COMPAT=""; DG_COMPAT_ASM=""; DG_OSMB_REF=0
DG_USES_SITE=0; DG_DEFAULT_FG=1; DG_FGS=""
DG_OWNER=""; DG_GROUP=""; DG_MODE=""
DG_PART_STYLE=""; DG_PTTYPE=""
PATH_STYLE=""; UDEV_DIR=""; NAME_EQ_LABEL=0
ORACLEASM_BIN=""; AFD_MAP=""; AFD_RAW=""; ASM_MM=" "
PART_EFF="no"; PTTYPE_EFF="gpt"; POWER_EFF=""; POWER_CLAUSE=""
OWNER_EFF=""; GROUP_EFF=""; PERM_EFF=""
SITECOL="'-'"; PASSCOL="'-'"; SQL_LIST="''"
UDEV_FILE=""; UDEV_TLINE=""; UDEV_KEY=""; UDEV_OLDVAL=""; UDEV_OLDLABEL=""
UDEV_TDEV=""; UDEV_PART_RULE=0; UDEV_PROG=""; UDEV_KGLOB=""
DG_IS_EXA=0; EXA_DISKTYPE="HardDisk"; EXA_REF_COUNT=0; EXA_REF_SIZE_MB=0; EXA_SIZE_STR=""
EXA_HOSTS=(); EXA_CNAMES=(); EXA_CREATE_PLAN=()

# Diskgroup atual
DGD_NUM=(); DGD_NAME=(); DGD_PATH=(); DGD_FG=(); DGD_TOTAL=(); DGD_OSMB=()
DGD_HDR=(); DGD_MODE=(); DGD_STATE=(); DGD_FGT=(); DGD_SITE=()
# Todos os discos vistos pelo ASM
ALL_GRP=(); ALL_NAME=(); ALL_PATH=(); ALL_HDR=(); ALL_OSMB=()
# Discos novos
N_IN=(); N_REAL=(); N_KNAME=(); N_TYPE=(); N_USE=(); N_MB=(); N_SS=()
N_ID=(); N_BYID=(); N_ISPART=(); N_PART=(); N_NEEDPART=(); N_LABEL=()
N_NAME=(); N_ASMPATH=(); N_FG=(); N_SITE=(); N_RDEV=(); N_AIXFIX=()
N_RFIX=(); N_WARN=(); N_UDEVPREV=(); N_GD=()

#------------------------------------------------------------------------------
# Saída / log
#------------------------------------------------------------------------------
C_R=""; C_G=""; C_Y=""; C_B=""; C_C=""; C_W=""; C_0=""
setup_colors() {
  if [[ -t 1 ]] && (( ! NO_COLOR )); then
    C_R=$'\033[1;31m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_B=$'\033[1;34m'
    C_C=$'\033[1;36m'; C_W=$'\033[1m'; C_0=$'\033[0m'
  fi
}
ts()      { date '+%Y-%m-%d %H:%M:%S'; }
info()    { printf '%s %s[INFO]%s %s\n' "$(ts)" "$C_B" "$C_0" "$*"; }
ok()      { printf '%s %s[ OK ]%s %s\n' "$(ts)" "$C_G" "$C_0" "$*"; }
warn()    { WARN_COUNT=$((WARN_COUNT+1)); printf '%s %s[WARN]%s %s\n' "$(ts)" "$C_Y" "$C_0" "$*"; }
err()     { printf '%s %s[ERRO]%s %s\n' "$(ts)" "$C_R" "$C_0" "$*" >&2; }
die()     { err "$1"; exit "${2:-1}"; }
dry()     { printf '         %s[DRY-RUN]%s %s\n' "$C_C" "$C_0" "$*"; }
section() { printf '\n%s==[ %s ]==%s\n' "$C_W" "$*" "$C_0"; }
is_uint() { [[ ${1:-} =~ ^[0-9]+$ ]]; }
epoch()   { awk 'BEGIN{srand(); print srand()}'; }
upper()   { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
trim()    { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

banner() {
cat <<'EOF'

   ____  ____    _      ____  ____      _    ____   ___
  |  _ \| __ )  / \    | __ )|  _ \    / \  | __ ) / _ \
  | | | |  _ \ / _ \   |  _ \| |_) |  / _ \ |  _ \| | | |
  | |_| | |_) / ___ \  | |_) |  _ <  / ___ \| |_) | |_| |
  |____/|____/_/   \_\ |____/|_| \_\/_/   \_\____/ \___/
EOF
  printf '  %sASM ADD DISK BRABO%s v%s (%s) — adição segura de discos no Oracle ASM\n' \
    "$C_W" "$C_0" "$SCRIPT_VERSION" "$SCRIPT_DATE"
  printf '  by • DBA BRABO — dbabrabo.com.br\n\n'
}

#------------------------------------------------------------------------------
# HELP
#------------------------------------------------------------------------------
usage() {
  banner
cat <<'EOF'
USO
  asm_add_disk_brabo.sh -g <DISKGROUP> -d <DISCO>[,<DISCO>...] [opções]            (dry-run)
  asm_add_disk_brabo.sh -g <DISKGROUP> -d <DISCO>[,<DISCO>...] [opções] --execute  (executa)

  >>> O PADRÃO É DRY-RUN: sem --execute NADA é alterado. O script roda TODAS as
  >>> validações, calcula labels/nomes e mostra o plano e os comandos exatos.

AÇÕES (uma por execução; padrão = adicionar)
  (padrão)              Provisiona no SO (partição + ASMLib/AFD/udev/permissão),
                        faz scan em todos os nós, valida a descoberta em TODAS as
                        instâncias ASM e executa o ALTER DISKGROUP ... ADD DISK.
  --provision-only      Só provisiona e valida a descoberta. NÃO executa o ALTER.
  --add-only            Disco já provisionado: só valida e executa o ALTER.
                        -d aceita caminho ASM (ORCL:X, AFD:X, /dev/oracleasm/disks/X,
                        /dev/rhdiskN, /dev/...) ou apenas o label (X).
  --status              Diskgroup, failgroups, discos (gv$asm_disk) e rebalance.
  --scan                Lista os discos do SO e classifica LIVRE / EM USO / SUJO.
  --rescan              Rescan de barramento (SCSI no Linux, cfgmgr no AIX) em
                        todos os nós + --scan. Exige --execute.
  --set-power <N>       ALTER DISKGROUP <DG> REBALANCE POWER N NOWAIT. Exige --execute.
  --monitor             Acompanha o rebalance (gv$asm_operation) até terminar.

PARÂMETROS PRINCIPAIS
  -g, --diskgroup <DG>        Diskgroup (ex.: DATA, RECO, REDO, OCR).
  -d, --disk <DEV>            Disco(s). Repetível ou separado por vírgula.
                              Linux: /dev/sdj, sdj, /dev/nvme3n1, /dev/xvdf,
                                     /dev/mapper/mpathk, /dev/disk/by-id/...
                              AIX  : hdisk12, /dev/hdisk12, /dev/rhdisk12
      --execute               Executa de verdade.
      --yes                   Dispensa a confirmação digitada (automação).
                              Só use com --execute e com MUITO cuidado.

REBALANCE
  -p, --power <N>             Power: 0-1024 (COMPATIBLE.ASM >= 11.2.0.2) ou 1-11.
                              Padrão: ASM_POWER_LIMIT da instância.
      --no-rebalance          ADD com REBALANCE POWER 0 (os dados NÃO são
                              redistribuídos; rode --set-power depois).
      --wait                  Após o ADD, acompanha o rebalance até o fim.
      --nowait                Retorna logo após o ADD (padrão).
      --wait-timeout <min>    Limite do acompanhamento (0 = sem limite). O rebalance
                              continua no ASM mesmo que o script pare de acompanhar.
      --poll <seg>            Intervalo de consulta (padrão 30, mínimo 5).

LABEL / NOME ASM (padrão: detecção automática do padrão do diskgroup)
      --prefix <TXT>          Força o prefixo (ex.: DSK_DATA_).
      --width <N>             Força o zero-padding (2 → _07, 3 → _007, 0 → sem padding).
      --start <N>             Força o número inicial (aborta se já estiver em uso).
      --labels <L1,L2,...>    Labels explícitos (ASMLib/AFD/udev), um por disco.
      --names <N1,N2,...>     Nomes ASM explícitos (cláusula NAME), um por disco.

PROVISIONAMENTO
      --method <M>            auto | asmlib | afd | udev | raw     (padrão: auto)
      --partition             Força a criação de partição única (início 1MiB).
      --no-partition          Força o uso do disco inteiro.
      --pttype <T>            gpt | msdos (padrão: igual aos discos atuais; >2TiB = gpt)
      --use-existing-partition  Aceita -d apontando para partição existente e vazia.
      --owner <u> --group <g> --perm <modo>
                              Permissão do device (raw/AIX). Padrão: igual aos atuais.
      --fix-aix-attrs         AIX/RAC: ajusta reserve_policy=no_reserve em todos os nós.

EXADATA (on-premises; detectado automaticamente pelos paths o/... do diskgroup)
      --exa-cell <c1,c2>      Cell(s) (hostname da cell) cujos griddisks entram no DG.
                              Substitui -d. Executado como root no nó de banco.
      --exa-prefix <P>        Prefixo dos griddisks (padrão: deduzido do DG, ex.: DATA, RECO).
      --exa-user <u>          Usuário ssh nas cells: root (padrão) ou celladmin.
      --exa-create-griddisk   Também CRIA os griddisks na cell (CREATE GRIDDISK ALL
                              HARDDISK|FLASHDISK PREFIX=<P>, SIZE=<igual ao DG>).
                              Exige que a cell NÃO tenha griddisk com esse prefixo.
      --exa-size <tam>        Tamanho do griddisk na criação (padrão: OS_MB exato dos
                              griddisks atuais do DG). Ex.: 5562G, 1.5T, 870400M.
      --exa-allow-partial     Aceita cell com quantidade de griddisks diferente dos
                              failgroups atuais (desbalanceia o DG).
      ExaCS / ExaCC / ExaDB-D (dbaascli/creg) são RECUSADOS: use o console OCI/dbaascli.

FAILGROUP / SITE (NORMAL, HIGH, FLEX, EXTENDED)
      --failgroup <FG>        Um failgroup para todos ou lista FG1,FG2 (um por disco).
      --allow-new-failgroup   Permite criar failgroup que ainda não existe.
      --site <S>              Site (Extended Diskgroup 12.2+): um para todos ou lista.

AMBIENTE GRID (padrão: autodetecção via asm_pmon, olr.loc, oratab)
      --grid-user <u>         Dono do Grid (ex.: grid, oracle).
      --grid-home <dir>       Grid Home (ex.: /u01/app/19.0.0/grid).
      --asm-sid <sid>         SID local do ASM (ex.: +ASM1).
      --oracle-base <dir>     ORACLE_BASE do Grid.
      --env-file <arq>        Arquivo de ambiente carregado antes (ex.: .profile_infra).
                              As variáveis ORACLE_HOME/ORACLE_SID detectadas prevalecem.

CLUSTER
      --nodes <n1,n2>         Força a lista de nós (padrão: olsnodes).
      --remote <modo>         auto   : ssh root sem senha se houver, senão manual
                              ssh    : exige ssh (BatchMode) como root em todos os nós
                              manual : mostra os comandos por nó e espera você digitar OK
                              none   : apenas standalone / Oracle Restart

TRAVAS DE SEGURANÇA (desligue só sabendo exatamente o porquê)
      --size-tolerance <%>    Diferença de tamanho aceita vs. discos do DG (padrão 2).
      --allow-size-mismatch   Tamanho diferente vira apenas aviso.
      --allow-dirty           Aceita disco com bytes não-zerados no início/fim
                              (sem assinatura). O script NUNCA apaga nada.
      --allow-running-rebalance  Aceita adicionar com rebalance em curso no DG.
      --allow-unhealthy-dg    Aceita DG com disco OFFLINE/DROPPING/HUNG.

LOG / SAÍDA
      --log-dir <dir>         Padrão /var/log/dbabrabo (log + snapshots antes/depois).
      --no-color
  -h, --help                  Esta ajuda.
  -V, --version               Versão.

O QUE É VALIDADO ANTES DE QUALQUER ALTERAÇÃO
  * root, bash >= 4, lock contra execução concorrente, ASM no ar, conexão SYSASM.
  * Diskgroup MOUNTED, sem rebalance em curso, sem disco OFFLINE/DROPPING/HUNG.
  * Exadata (o/...): ambiente cloud recusado; cell online; griddisks active/UNUSED,
    sem diskgroup, mesmo diskType e MESMO tamanho dos atuais; quantidade por cell =
    griddisks por failgroup do DG; celldisks normal e com freeSpace (na criação);
    todos os griddisks vistos como CANDIDATE em TODAS as instâncias ASM.
  * Para cada disco: é disco inteiro (ou mpath); NÃO é caminho de multipath; sem
    partição, sem filhos/holders, não montado, não é swap/LVM/md, não está aberto
    por processo, sem assinatura (blkid/wipefs), sem marca ASMLib, sem header ASM
    (kfed), início e fim zerados, maj:min NÃO usado por nenhum disco ASM/ASMLib/AFD,
    tamanho e setor compatíveis com o DG, disco não repetido na linha de comando.
  * RAC: disco visível e limpo em TODOS os nós (by-id/WWN no Linux, unique_id no AIX),
    ASMLib/AFD/udev consistentes nos nós.
  * O caminho novo casa com asm_diskstring.
  * Antes do ALTER: TODAS as instâncias ASM (gv$asm_disk) enxergam cada disco
    como CANDIDATE/PROVISIONED/FORMER. Se não, para ANTES do ALTER.
  * Labels/nomes: prefixo dominante, zero-padding e próximo número livre (máximo + 1),
    considerando o DG, o ASMLib/AFD/udev e as regras existentes. Números com zero à
    esquerda são tratados em base 10 (08 e 09 não viram octal). Inconsistências como
    DSK_DATA_4 junto de DSK_DATA_04 são reportadas.
  * Failgroups: DG NORMAL/HIGH com failgroup nomeado exige --failgroup; o script
    mostra o balanceamento por failgroup depois do ADD.
  * Confirmação digitada (nome do DG + quantidade de discos), snapshot antes/depois e
    roteiro de reversão impresso se algo falhar no meio.

AMBIENTES SUPORTADOS
  Linux   : OL/RHEL/SLES 6 a 9 | ASMLib (v2/v3) | ASMFD | udev | multipath |
            VMware/KVM/Hyper-V | AWS EBS (Nitro/NVMe) | OCI | Azure | GCP
  AIX     : rhdisk raw (chown/chmod + reserve_policy) | RAC com mapeamento por unique_id
  Solaris e outros: provisione o slice manualmente e use --add-only
  Grid    : Standalone/Oracle Restart, RAC, Flex ASM | ASM 11.2, 12.1, 12.2, 18c, 19c,
            21c, 23ai
  DG      : EXTERNAL, NORMAL, HIGH, FLEX, EXTENDED (com SITE)
  Exadata : on-premises X2 a X11M (HC, EF, XT), cells via ssh root/celladmin

EXEMPLOS
  # 1) Ver o que seria feito (dry-run) para um disco no DATA
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt

  # 2) Adicionar dois discos com power 4, sem esperar o rebalance
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt,/dev/sdu -p 4 --execute

  # 3) Adicionar e acompanhar o rebalance até o fim (no máximo 3h)
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt -d /dev/sdu -p 8 --wait --wait-timeout 180 --execute

  # 4) Adicionar SEM rebalance agora e rebalancear na janela
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt --no-rebalance --execute
  ./asm_add_disk_brabo.sh -g DATA --set-power 8 --execute

  # 5) Reduzir o power de um rebalance que está pesando no I/O
  ./asm_add_disk_brabo.sh -g DATA --set-power 2 --execute

  # 6) Acompanhar o rebalance / ver o status do diskgroup
  ./asm_add_disk_brabo.sh -g DATA --monitor --poll 60
  ./asm_add_disk_brabo.sh -g DATA --status

  # 7) Descobrir quais discos estão livres (somente leitura)
  ./asm_add_disk_brabo.sh --scan
  ./asm_add_disk_brabo.sh --rescan --execute        # LUN nova ainda não apareceu

  # 8) DG com nomes inconsistentes (DSK_DATA_4 e DSK_DATA_04): força o padrão
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt --prefix DSK_DATA_ --width 2

  # 9) Labels e nomes explícitos
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt,/dev/sdu \
      --labels DSK_DATA_17,DSK_DATA_18 --names DSK_DATA_17,DSK_DATA_18 --execute

  # 10) AWS EBS em instância Nitro (o nome /dev/sdX pode mudar no reboot: use by-id)
  ./asm_add_disk_brabo.sh -g DATA -d /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0abc123 -p 4 --execute

  # 11) Storage com multipath
  ./asm_add_disk_brabo.sh -g DATA -d /dev/mapper/mpathk,/dev/mapper/mpathl --execute

  # 12) ASMFD (AFD), disco inteiro
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdk --method afd --no-partition --execute

  # 13) udev (a regra é gerada a partir da regra de um disco atual do DG)
  ./asm_add_disk_brabo.sh -g RECO -d /dev/sdm --execute

  # 14) DG NORMAL com failgroups nomeados (um disco em cada failgroup)
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt,/dev/sdu --failgroup FG_STG1,FG_STG2 --execute

  # 15) Extended Diskgroup (12.2+)
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt --site SITEA --failgroup FG_SITEA --execute

  # 16) RAC sem ssh entre os nós: o script mostra os comandos de cada nó e espera OK
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt --remote manual --execute

  # 17) Ambiente Grid explícito (ex.: perfil .profile_infra)
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt --grid-user grid \
      --grid-home /u01/app/19.0.0/grid --asm-sid +ASM1 --env-file /home/grid/.profile_infra

  # 18) Provisionar hoje e adicionar na janela
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt,/dev/sdu --provision-only --execute
  ./asm_add_disk_brabo.sh -g DATA --add-only -d DSK_DATA_17,DSK_DATA_18 -p 4 --execute

  # 19) AIX (RAC) ajustando reserve_policy
  ./asm_add_disk_brabo.sh -g DATA -d hdisk12,hdisk13 --fix-aix-attrs -p 4 --execute

  # 20) Solaris ou outro SO (provisionamento manual) — só o ADD
  ./asm_add_disk_brabo.sh -g DATA --add-only -d /dev/rdsk/c0t5d0s6 --names DATA_0007 --execute

  # 21) Partição já criada e vazia
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdj1 --use-existing-partition --execute

  # 22) Automação (Ansible/cron): sem prompt, ssh obrigatório, acompanha o rebalance
  ./asm_add_disk_brabo.sh -g DATA -d /dev/sdt -p 4 --remote ssh --wait --execute --yes

  # 23) Exadata: storage expansion — griddisks já criados na cell nova (dry-run)
  ./asm_add_disk_brabo.sh -g DATA --exa-cell exa01celadm04

  # 24) Exadata: adicionar duas cells novas no DATA com power 8 e acompanhar
  ./asm_add_disk_brabo.sh -g DATA --exa-cell exa01celadm04,exa01celadm05 -p 8 --wait --execute

  # 25) Exadata: criar os griddisks RECO (mesmo tamanho do DG) e adicionar
  ./asm_add_disk_brabo.sh -g RECO --exa-cell exa01celadm04 --exa-create-griddisk -p 4 --execute

  # 26) Exadata: só criar os griddisks hoje (sem ALTER) e adicionar na janela
  ./asm_add_disk_brabo.sh -g DATA --exa-cell exa01celadm04 --exa-create-griddisk --provision-only --execute
  ./asm_add_disk_brabo.sh -g DATA --exa-cell exa01celadm04 -p 8 --execute

  # 27) Exadata: acesso às cells como celladmin, prefixo explícito
  ./asm_add_disk_brabo.sh -g DATAC1 --exa-cell exa01celadm04 --exa-prefix DATAC1 --exa-user celladmin

CÓDIGOS DE SAÍDA
  0 OK | 1 erro de uso ou pré-check (nada alterado) | 2 cancelado pelo usuário
  3 falha durante a execução (veja o roteiro de reversão no log) | 4 lock | 130 sinal
EOF
}

#------------------------------------------------------------------------------
# Argumentos
#------------------------------------------------------------------------------
need_arg() { [[ $# -ge 2 && -n ${2:-} ]] || die "A opção $1 exige um valor (veja --help)."; }
set_action() {
  if (( ACTION_SET )) && [[ $ACTION != "$1" ]]; then die "Ações conflitantes: --$ACTION e --$1."; fi
  ACTION=$1; ACTION_SET=1
}

parse_args() {
  local t=()
  if [[ $# -eq 0 ]]; then usage; exit 1; fi
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)                 usage; exit 0 ;;
      -V|--version)              echo "$SCRIPT_NAME $SCRIPT_VERSION ($SCRIPT_DATE)"; exit 0 ;;
      -g|--diskgroup)            need_arg "$@"; DG=$2; shift 2 ;;
      -d|--disk)                 need_arg "$@"; IFS=',' read -r -a t <<<"$2"; DISKS_IN+=(${t[@]+"${t[@]}"}); shift 2 ;;
      -p|--power)                need_arg "$@"; POWER=$2; shift 2 ;;
      --no-rebalance)            NO_REBAL=1; shift ;;
      --wait)                    MON_WAIT=1; shift ;;
      --nowait)                  MON_WAIT=0; shift ;;
      --wait-timeout)            need_arg "$@"; WAIT_TIMEOUT=$2; shift 2 ;;
      --poll)                    need_arg "$@"; POLL=$2; shift 2 ;;
      --method)                  need_arg "$@"; METHOD=$2; shift 2 ;;
      --prefix)                  need_arg "$@"; PREFIX=$2; shift 2 ;;
      --width)                   need_arg "$@"; WIDTH=$2; shift 2 ;;
      --start)                   need_arg "$@"; START_NUM=$2; shift 2 ;;
      --labels)                  need_arg "$@"; LABELS_IN=$2; shift 2 ;;
      --names)                   need_arg "$@"; NAMES_IN=$2; shift 2 ;;
      --partition)               PART_MODE="yes"; shift ;;
      --no-partition)            PART_MODE="no"; shift ;;
      --pttype)                  need_arg "$@"; PTTYPE=$2; shift 2 ;;
      --use-existing-partition)  USE_EXISTING_PART=1; shift ;;
      --owner)                   need_arg "$@"; OWNER=$2; shift 2 ;;
      --group)                   need_arg "$@"; GROUP=$2; shift 2 ;;
      --perm)                    need_arg "$@"; PERM=$2; shift 2 ;;
      --fix-aix-attrs)           FIX_AIX_ATTRS=1; shift ;;
      --failgroup)               need_arg "$@"; FAILGROUPS_IN=$2; shift 2 ;;
      --allow-new-failgroup)     ALLOW_NEW_FG=1; shift ;;
      --site)                    need_arg "$@"; SITES_IN=$2; shift 2 ;;
      --grid-user)               need_arg "$@"; GRID_USER=$2; shift 2 ;;
      --grid-home)               need_arg "$@"; GRID_HOME=${2%/}; shift 2 ;;
      --asm-sid)                 need_arg "$@"; ASM_SID=$2; shift 2 ;;
      --oracle-base)             need_arg "$@"; ORA_BASE=$2; shift 2 ;;
      --env-file)                need_arg "$@"; ENV_FILE=$2; shift 2 ;;
      --nodes)                   need_arg "$@"; NODES_IN=$2; shift 2 ;;
      --remote)                  need_arg "$@"; REMOTE_MODE=$2; shift 2 ;;
      --size-tolerance)          need_arg "$@"; SIZE_TOL=$2; shift 2 ;;
      --allow-size-mismatch)     ALLOW_SIZE_MISMATCH=1; shift ;;
      --allow-dirty)             ALLOW_DIRTY=1; shift ;;
      --allow-running-rebalance) ALLOW_RUNNING_OP=1; shift ;;
      --allow-unhealthy-dg)      ALLOW_UNHEALTHY=1; shift ;;
      --provision-only)          set_action "provision-only"; shift ;;
      --add-only)                set_action "add-only"; shift ;;
      --status)                  set_action "status"; shift ;;
      --scan)                    set_action "scan"; shift ;;
      --rescan)                  set_action "rescan"; shift ;;
      --set-power)               need_arg "$@"; set_action "set-power"; SET_POWER=$2; shift 2 ;;
      --monitor)                 set_action "monitor"; shift ;;
      --execute)                 EXECUTE=1; shift ;;
      --yes)                     ASSUME_YES=1; shift ;;
      --log-dir)                 need_arg "$@"; LOG_DIR=${2%/}; shift 2 ;;
      --exa-cell)                need_arg "$@"; EXA_CELLS=$2; shift 2 ;;
      --exa-prefix)              need_arg "$@"; EXA_PREFIX=$2; shift 2 ;;
      --exa-user)                need_arg "$@"; EXA_USER=$2; shift 2 ;;
      --exa-create-griddisk)     EXA_CREATE=1; shift ;;
      --exa-size)                need_arg "$@"; EXA_SIZE=$2; shift 2 ;;
      --exa-allow-partial)       EXA_ALLOW_PARTIAL=1; shift ;;
      --no-color)                NO_COLOR=1; shift ;;
      *) die "Parâmetro desconhecido: '$1' (use --help)." ;;
    esac
  done
}

validate_args() {
  local d clean=() seen=" "
  for d in ${DISKS_IN[@]+"${DISKS_IN[@]}"}; do
    d=$(trim "$d"); [[ -n $d ]] || continue
    [[ $seen == *" $d "* ]] && die "Disco informado em duplicidade: $d"
    seen+="$d "; clean+=("$d")
  done
  DISKS_IN=(${clean[@]+"${clean[@]}"})

  case $ACTION in
    add|provision-only|add-only)
      [[ -n $DG ]] || die "-g/--diskgroup é obrigatório."
      if [[ -n $EXA_CELLS ]]; then
        (( ${#DISKS_IN[@]} == 0 )) || die "No modo Exadata use --exa-cell (não -d)."
      else
        (( ${#DISKS_IN[@]} > 0 )) || die "-d/--disk é obrigatório (ou --exa-cell para Exadata)."
      fi ;;
    status|monitor|set-power)
      [[ -n $DG ]] || die "-g/--diskgroup é obrigatório para --$ACTION."
      (( ${#DISKS_IN[@]} == 0 )) || die "--$ACTION não aceita -d." ;;
    scan|rescan)
      (( ${#DISKS_IN[@]} == 0 )) || die "--$ACTION não aceita -d." ;;
  esac
  if [[ -n $DG ]]; then
    DG=$(upper "$DG")
    [[ $DG =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "Nome de diskgroup inválido: '$DG'."
  fi
  [[ -z $POWER ]] || is_uint "$POWER" || die "--power deve ser inteiro (recebido '$POWER')."
  (( NO_REBAL )) && [[ -n $POWER && $POWER != 0 ]] && die "--no-rebalance conflita com --power $POWER."
  [[ $ACTION != set-power ]] || is_uint "$SET_POWER" || die "--set-power deve ser inteiro."
  case $METHOD in auto|asmlib|afd|udev|raw) ;; *) die "--method inválido: $METHOD" ;; esac
  case $REMOTE_MODE in auto|ssh|manual|none) ;; *) die "--remote inválido: $REMOTE_MODE" ;; esac
  case $PTTYPE in auto|gpt|msdos) ;; *) die "--pttype inválido: $PTTYPE" ;; esac
  [[ -z $WIDTH ]] || { is_uint "$WIDTH" && (( WIDTH <= 6 )); } || die "--width deve ser inteiro entre 0 e 6."
  [[ -z $START_NUM ]] || is_uint "$START_NUM" || die "--start deve ser inteiro."
  is_uint "$SIZE_TOL" || die "--size-tolerance deve ser inteiro."
  is_uint "$WAIT_TIMEOUT" || die "--wait-timeout deve ser inteiro (minutos)."
  { is_uint "$POLL" && (( POLL >= 5 )); } || die "--poll deve ser inteiro >= 5."
  [[ -z $PERM || $PERM =~ ^[0-7]{3,4}$ ]] || die "--perm inválido: $PERM"
  [[ -z $ENV_FILE || -r $ENV_FILE ]] || die "--env-file não legível: $ENV_FILE"
  [[ -z $PREFIX || $PREFIX =~ ^[A-Za-z][A-Za-z0-9_.+-]*$ ]] || die "--prefix inválido: $PREFIX"
  if (( ASSUME_YES )) && [[ $REMOTE_MODE == manual ]]; then
    die "--yes não combina com --remote manual (o modo manual exige interação)."
  fi
  if [[ $ACTION == add-only && ( -n $LABELS_IN || $PART_MODE != auto || $USE_EXISTING_PART == 1 ) ]]; then
    die "--add-only não aceita opções de provisionamento (--labels/--partition/--use-existing-partition)."
  fi
  if [[ -n $EXA_CELLS ]]; then
    [[ $ACTION == add || $ACTION == provision-only ]] || die "--exa-cell só vale para a ação padrão (adicionar) ou --provision-only."
    [[ $ACTION != provision-only ]] || (( EXA_CREATE )) || die "Exadata --provision-only só faz sentido com --exa-create-griddisk."
    local c arr=()
    IFS=',' read -r -a arr <<<"$EXA_CELLS"
    for c in "${arr[@]}"; do c=$(trim "$c"); [[ $c =~ ^[A-Za-z0-9._-]+$ ]] || die "Nome de cell inválido: '$c'"; done
  fi
  if (( EXA_CREATE )) || [[ -n $EXA_PREFIX || -n $EXA_SIZE || $EXA_USER != root || $EXA_ALLOW_PARTIAL == 1 ]]; then
    [[ -n $EXA_CELLS ]] || die "Opções --exa-* exigem --exa-cell."
  fi
  [[ -z $EXA_PREFIX || $EXA_PREFIX =~ ^[A-Za-z][A-Za-z0-9_]{0,15}$ ]] || die "--exa-prefix inválido: $EXA_PREFIX"
  [[ -z $EXA_SIZE || $EXA_SIZE =~ ^[0-9]+(\.[0-9]+)?[MGT]$ ]] || die "--exa-size inválido: $EXA_SIZE (ex.: 5562G, 1.5T, 870400M)"
  [[ $EXA_USER == root || $EXA_USER == celladmin ]] || die "--exa-user deve ser root ou celladmin."
  (( ASSUME_YES && ! EXECUTE )) && warn "--yes sem --execute não tem efeito (dry-run)."
  return 0
}

#------------------------------------------------------------------------------
# Runtime: log, tmp, lock, traps
#------------------------------------------------------------------------------
init_runtime() {
  OS=$(uname -s)
  case $OS in Linux|AIX|SunOS) ;; *) die "Sistema operacional $OS não suportado." ;; esac
  CUR_USER=$(id -un 2>/dev/null || /usr/xpg4/bin/id -un 2>/dev/null || whoami)
  (( BASH_VERSINFO[0] >= 4 )) || die "Requer bash >= 4 (atual: $BASH_VERSION)."

  if [[ $CUR_USER != root && $LOG_DIR == /var/log/dbabrabo ]]; then
    LOG_DIR="${HOME:-/tmp}/dbabrabo_logs"
  fi
  mkdir -p "$LOG_DIR" 2>/dev/null; chmod 700 "$LOG_DIR" 2>/dev/null
  [[ -d $LOG_DIR && -w $LOG_DIR ]] || die "Diretório de log sem escrita: $LOG_DIR (use --log-dir)."
  LOG_FILE="$LOG_DIR/asm_add_disk_brabo_${DG:-NODG}_${ACTION}_${RUN_TS}.log"
  : > "$LOG_FILE" || die "Não consegui criar o log $LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1

  TMPD="/tmp/asm_add_brabo.$$.$RANDOM"
  mkdir -m 755 "$TMPD" 2>/dev/null || die "Não consegui criar o diretório temporário $TMPD"
}

acquire_lock() {
  local p
  if mkdir "$LOCK_DIR" 2>/dev/null; then echo $$ > "$LOCK_DIR/pid"; LOCK_HELD=1; return 0; fi
  p=$(cat "$LOCK_DIR/pid" 2>/dev/null)
  if [[ -n $p ]] && kill -0 "$p" 2>/dev/null; then
    die "Outra execução do script está em andamento neste host (PID $p). Lock: $LOCK_DIR" 4
  fi
  warn "Lock órfão encontrado (PID ${p:-?} não existe mais). Removendo."
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || die "Não consegui obter o lock $LOCK_DIR" 4
  echo $$ > "$LOCK_DIR/pid"; LOCK_HELD=1
}

on_exit() {
  local rc=$? u
  set +o nounset
  if (( rc != 0 )) && (( ${#UNDO[@]} > 0 )); then
    printf '\n'
    err "A execução parou DEPOIS de alterações. NADA foi revertido automaticamente."
    printf '%s  Alterações já feitas e como revertê-las (revise antes de executar!):%s\n' "$C_Y" "$C_0"
    for u in "${UNDO[@]}"; do printf '    %s\n' "$u"; done
  fi
  [[ -n $TMPD && -d $TMPD ]] && rm -rf "$TMPD"
  (( LOCK_HELD )) && rm -rf "$LOCK_DIR"
  [[ -n $LOG_FILE ]] && printf '\n  Log completo: %s\n\n' "$LOG_FILE"
  exit "$rc"
}

on_signal() {
  case $PHASE in
    alter)   warn "Sinal $1 com o ALTER DISKGROUP já enviado. O ASM continua o ADD/rebalance (não é cancelado). Verifique com --status." ;;
    monitor) warn "Monitor interrompido ($1). O rebalance continua no ASM; use --monitor para voltar a acompanhar." ;;
  esac
  err "Interrompido ($1)."
  exit 130
}

require_root() { [[ $CUR_USER == root ]] || die "Esta ação precisa ser executada como root."; }

#------------------------------------------------------------------------------
# Execução de comandos (respeita DRY-RUN)
#------------------------------------------------------------------------------
run_mod() {
  local disp rc
  disp=$(printf '%q ' "$@")
  if (( ! EXECUTE )); then dry "$disp"; return 0; fi
  info "EXEC: $disp"
  "$@"; rc=$?
  (( rc == 0 )) || err "Comando falhou (rc=$rc): $disp"
  return "$rc"
}

SSH_BASE=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o LogLevel=ERROR)
r_ro()    { local n=$1; shift; "${SSH_BASE[@]}" -n "root@$n" "$*"; }
r_stdin() { local n=$1; shift; "${SSH_BASE[@]}" "root@$n" "$*"; }
r_mod() {
  local n=$1 c=$2
  if (( ! EXECUTE )); then dry "[$n] $c"; return 0; fi
  if [[ $REMOTE_MODE == manual ]]; then MANUAL_Q+=("[$n]  $c"); return 0; fi
  info "EXEC [$n]: $c"
  r_ro "$n" "$c"
}
flush_manual() {
  local q a
  (( ${#MANUAL_Q[@]} > 0 )) || return 0
  section "AÇÃO MANUAL NOS OUTROS NÓS"
  echo "Execute COMO ROOT, NA ORDEM, cada comando no nó indicado entre colchetes:"
  echo
  for q in "${MANUAL_Q[@]}"; do printf '  %s\n' "$q"; done
  echo
  tty_ok || die "Sem terminal para o modo manual." 3
  while :; do
    printf 'Depois de executar TODOS os comandos acima sem erro, digite OK (ou ABORTAR): '
    read -r a < /dev/tty || die "Cancelado." 3
    case $a in OK|ok) break ;; ABORTAR|abortar) die "Abortado pelo operador durante a etapa manual." 3 ;; esac
  done
  MANUAL_Q=()
}
tty_ok() { { : < /dev/tty; } 2>/dev/null; }

confirm_typed() {  # $1 = resposta esperada, $2 = pergunta
  local a
  if (( ASSUME_YES )); then warn "Confirmação dispensada por --yes."; return 0; fi
  tty_ok || die "Sem terminal interativo para a confirmação. Use --yes (com MUITO cuidado)." 2
  printf '%s%s%s' "$C_Y" "$2" "$C_0"
  read -r a < /dev/tty || die "Cancelado." 2
  [[ $a == "$1" ]] || die "Confirmação não confere ('$a' ≠ '$1'). Nada foi alterado." 2
}

#------------------------------------------------------------------------------
# Grid / SQL
#------------------------------------------------------------------------------
as_grid() {
  local cmd=$1 pre=""
  [[ -n $ENV_FILE ]] && pre=". '$ENV_FILE' >/dev/null 2>&1; "
  pre+="ORACLE_HOME='$GRID_HOME'; ORACLE_SID='$ASM_SID'; PATH='$GRID_HOME/bin':\$PATH; "
  pre+="LD_LIBRARY_PATH='$GRID_HOME/lib'; LIBPATH='$GRID_HOME/lib'; NLS_LANG=AMERICAN_AMERICA.AL32UTF8; "
  pre+="export ORACLE_HOME ORACLE_SID PATH LD_LIBRARY_PATH LIBPATH NLS_LANG; "
  [[ -n $ORA_BASE ]] && pre+="ORACLE_BASE='$ORA_BASE'; export ORACLE_BASE; "
  if [[ $CUR_USER == "$GRID_USER" ]]; then sh -c "$pre$cmd"; else su "$GRID_USER" -c "$pre$cmd"; fi
}

grid_env_root() {  # roda ferramenta do Grid como root com o ambiente correto
  env ORACLE_HOME="$GRID_HOME" ORACLE_SID="$ASM_SID" ORACLE_BASE="$ORA_BASE" \
      LD_LIBRARY_PATH="$GRID_HOME/lib" LIBPATH="$GRID_HOME/lib" "$@"
}

sql_query() {  # $1 = SQL (terminado em ;). Saída: linhas não vazias.
  local sql=$1 f out rc
  f="$TMPD/q_${RANDOM}_${RANDOM}.sql"
  {
    echo "whenever sqlerror exit 3"
    echo "whenever oserror exit 4"
    echo "set heading off feedback off pagesize 0 linesize 32767 trimspool on trimout on"
    echo "set verify off echo off tab off timing off serveroutput off"
    printf '%s\n' "$sql"
    echo "exit"
  } > "$f"
  chmod 644 "$f"
  out=$(as_grid "sqlplus -S -L '/ as sysasm' @'$f'" 2>&1); rc=$?
  if (( rc != 0 )) || printf '%s\n' "$out" | grep -qE '^(ORA-|SP2-|ERROR at line)'; then
    err "Falha SQL (rc=$rc)."
    printf '%s\n' "$sql" | sed 's/^/      SQL> /' >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  printf '%s\n' "$out" | sed '/^[[:space:]]*$/d'
}

sqlt() {  # SQL via stdin com placeholders __DG__ __DGNUM__ __LIST__ __SITECOL__ __PASSCOL__
  local t; t=$(cat)
  t=${t//__DGNUM__/$DG_NUM}; t=${t//__DG__/$DG}; t=${t//__LIST__/$SQL_LIST}
  t=${t//__SITECOL__/$SITECOL}; t=${t//__PASSCOL__/$PASSCOL}
  sql_query "$t"
}

sql_pretty() {  # SQL formatado para leitura humana
  local f="$TMPD/p_${RANDOM}.sql"
  { echo "set lines 220 pages 1000 feedback off verify off trimout on"; printf '%s\n' "$1"; echo "exit"; } > "$f"
  chmod 644 "$f"
  as_grid "sqlplus -S -L '/ as sysasm' @'$f'" 2>&1
}

version_ge() {  # $1 >= $2 ?
  awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x,".");m=split(b,y,".");k=(n>m?n:m)
    for(i=1;i<=k;i++){xi=(i<=n?x[i]+0:0);yi=(i<=m?y[i]+0:0);if(xi>yi)exit 0;if(xi<yi)exit 1}exit 0}'
}

detect_grid() {
  section "Ambiente Grid / ASM"
  local line pid f out
  line=$(ps -eo pid,args 2>/dev/null | awk '$2 ~ /^asm_pmon_\+ASM[0-9]*$/ {print $1" "$2; exit}')
  [[ -n $line ]] || die "Instância ASM não encontrada neste host (processo asm_pmon_+ASM*). O ASM precisa estar no ar."
  pid=${line%% *}
  [[ -n $ASM_SID ]] || ASM_SID=${line#* asm_pmon_}
  if [[ -z $GRID_USER ]]; then
    if [[ $OS == Linux ]]; then GRID_USER=$(stat -c %U "/proc/$pid" 2>/dev/null)
    else GRID_USER=$(ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}'); fi
  fi
  [[ -n $GRID_USER ]] && id "$GRID_USER" >/dev/null 2>&1 || die "Dono do Grid não identificado. Use --grid-user."
  if [[ -z $GRID_HOME ]]; then
    for f in /etc/oracle/olr.loc /var/opt/oracle/olr.loc; do
      [[ -r $f ]] && GRID_HOME=$(awk -F= '$1=="crs_home"{print $2; exit}' "$f")
      [[ -n $GRID_HOME ]] && break
    done
  fi
  if [[ -z $GRID_HOME ]]; then
    for f in /etc/oratab /var/opt/oracle/oratab; do
      [[ -r $f ]] || continue
      GRID_HOME=$(awk -F: -v s="$ASM_SID" '$1==s{print $2; exit}' "$f")
      [[ -z $GRID_HOME ]] && GRID_HOME=$(awk -F: '$1 ~ /^\+ASM/{print $2; exit}' "$f")
      [[ -n $GRID_HOME ]] && break
    done
  fi
  if [[ -z $GRID_HOME && $OS == Linux ]]; then
    f=$(readlink -f "/proc/$pid/exe" 2>/dev/null); [[ -n $f ]] && GRID_HOME=${f%/bin/oracle}
  fi
  [[ -n $GRID_HOME && -x $GRID_HOME/bin/sqlplus ]] || die "Grid Home não identificado ou inválido ('$GRID_HOME'). Use --grid-home."
  if [[ -z $ORA_BASE && -x $GRID_HOME/bin/orabase ]]; then
    ORA_BASE=$(as_grid "'$GRID_HOME/bin/orabase'" 2>/dev/null | tail -1)
  fi

  out=$(sql_query "select instance_name||'|'||version from v\$instance;") \
    || die "Não consegui conectar no ASM como SYSASM (usuário $GRID_USER, SID $ASM_SID, home $GRID_HOME)."
  [[ ${out%%|*} == +ASM* ]] || die "A instância conectada (${out%%|*}) não é ASM."
  ASM_VER=${out#*|}
  version_ge "$ASM_VER" "11.2" || die "ASM $ASM_VER não suportado (mínimo 11.2)."
  version_ge "$ASM_VER" "12.2" && SITECOL="nvl(d.site_name,'-')"
  version_ge "$ASM_VER" "12.1" && PASSCOL="o.pass"

  out=$(sql_query "select (select count(*) from gv\$instance)||'|'||(select value from v\$parameter where name='asm_power_limit')||'|'||(select nvl(value,'-') from v\$parameter where name='asm_diskstring') from dual;") \
    || die "Falha lendo parâmetros do ASM."
  IFS='|' read -r INST_COUNT ASM_POWER_LIMIT ASM_DISKSTRING <<<"$out"

  ok "ASM: SID=$ASM_SID versão=$ASM_VER instâncias=$INST_COUNT"
  info "Grid: user=$GRID_USER home=$GRID_HOME base=${ORA_BASE:-?}"
  info "asm_power_limit=$ASM_POWER_LIMIT | asm_diskstring=$ASM_DISKSTRING"
}

detect_cluster() {
  local out n m found
  NODES=(); REMOTE_NODES=()
  if [[ -n $NODES_IN ]]; then
    IFS=',' read -r -a NODES <<<"$NODES_IN"
  else
    out=$(as_grid "'$GRID_HOME/bin/olsnodes'" 2>/dev/null) && while read -r n; do [[ -n $n ]] && NODES+=("$n"); done <<<"$out"
  fi
  LOCAL_NODE=$(as_grid "'$GRID_HOME/bin/olsnodes' -l" 2>/dev/null | head -1)
  [[ -n $LOCAL_NODE ]] || LOCAL_NODE=$(hostname | cut -d. -f1)
  if (( ${#NODES[@]} > 1 )); then
    IS_RAC=1
    found=0
    for n in "${NODES[@]}"; do
      n=$(trim "$n")
      if [[ $(upper "${n%%.*}") == "$(upper "${LOCAL_NODE%%.*}")" ]]; then found=1; continue; fi
      REMOTE_NODES+=("$n")
    done
    (( found )) || die "O nó local ($LOCAL_NODE) não está na lista de nós (${NODES[*]})."
    ok "Cluster: RAC com ${#NODES[@]} nós (${NODES[*]}) | local=$LOCAL_NODE"
  else
    IS_RAC=0
    (( INST_COUNT > 1 )) && die "gv\$instance mostra $INST_COUNT instâncias ASM mas os nós não foram listados. Use --nodes."
    ok "Standalone / Oracle Restart (nó $LOCAL_NODE)"
  fi
  for m in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
    [[ $m =~ ^[A-Za-z0-9._-]+$ ]] || die "Nome de nó inválido: $m"
  done
}

setup_remote() {
  local n bad=()
  if (( ! IS_RAC )); then REMOTE_MODE="none"; return 0; fi
  [[ $REMOTE_MODE == none ]] && die "Em RAC, --remote none não é permitido (o disco precisa ser preparado em todos os nós)."
  if [[ $REMOTE_MODE == auto || $REMOTE_MODE == ssh ]]; then
    for n in "${REMOTE_NODES[@]}"; do r_ro "$n" true >/dev/null 2>&1 || bad+=("$n"); done
    if (( ${#bad[@]} > 0 )); then
      [[ $REMOTE_MODE == ssh ]] && die "ssh root sem senha (BatchMode) falhou para: ${bad[*]}"
      (( ASSUME_YES )) && die "ssh indisponível para ${bad[*]} e --yes impede o modo manual."
      REMOTE_MODE="manual"
      warn "ssh root sem senha indisponível para ${bad[*]} — usando modo MANUAL nos nós remotos."
    else
      REMOTE_MODE="ssh"
    fi
  fi
  ok "Execução remota: $REMOTE_MODE (nós: ${REMOTE_NODES[*]})"
}

#------------------------------------------------------------------------------
# Diskgroup
#------------------------------------------------------------------------------
load_dg() {
  local row
  row=$(sqlt <<'SQL'
select group_number||'|'||state||'|'||type||'|'||total_mb||'|'||free_mb||'|'||usable_file_mb||'|'||(allocation_unit_size/1048576)||'|'||sector_size||'|'||compatibility from v$asm_diskgroup where name = '__DG__';
SQL
) || die "Falha consultando v\$asm_diskgroup."
  [[ -n $row ]] || die "Diskgroup '$DG' não existe."
  IFS='|' read -r DG_NUM DG_STATE DG_TYPE DG_TOTAL DG_FREE DG_USABLE DG_AU DG_SECTOR DG_COMPAT <<<"$(printf '%s\n' "$row" | head -1)"
  [[ $DG_STATE == MOUNTED ]] || die "Diskgroup $DG não está MOUNTED nesta instância (estado: $DG_STATE)."
  row=$(sqlt <<'SQL'
select a.value from v$asm_attribute a where a.group_number = __DGNUM__ and a.name = 'compatible.asm';
SQL
) || die "Falha lendo compatible.asm."
  DG_COMPAT_ASM=$(trim "${row:-$DG_COMPAT}")
}

load_ops() {  # imprime operações do DG atual
  sqlt <<'SQL'
select o.inst_id||'|'||o.operation||'|'||o.state||'|'||o.power||'|'||o.sofar||'|'||o.est_work||'|'||o.est_rate||'|'||o.est_minutes||'|'||nvl(to_char(o.error_code),'-')||'|'||__PASSCOL__ from gv$asm_operation o where o.group_number = __DGNUM__ order by o.inst_id;
SQL
}

check_dg_health() {
  section "Diskgroup $DG"
  local rows inst st ops unhealthy=0 i
  rows=$(sqlt <<'SQL'
select inst_id||'|'||state from gv$asm_diskgroup where name = '__DG__' order by inst_id;
SQL
) || die "Falha consultando gv\$asm_diskgroup."
  while IFS='|' read -r inst st; do
    [[ -n $inst ]] || continue
    [[ $st == MOUNTED ]] || warn "DG $DG está '$st' na instância ASM $inst (o disco precisará ser visível lá também)."
  done <<<"$rows"

  ops=$(load_ops) || die "Falha consultando gv\$asm_operation."
  if [[ -n $ops ]]; then
    warn "Operação em andamento no $DG:"; printf '%s\n' "$ops" | sed 's/^/        inst|op|state|power|sofar|est_work|rate|est_min|erro|pass => /'
    (( ALLOW_RUNNING_OP )) || die "Existe rebalance/operação em andamento no $DG. Aguarde terminar (--monitor) ou use --allow-running-rebalance."
  fi

  load_dg_disks
  for ((i=0; i<${#DGD_PATH[@]}; i++)); do
    [[ ${DGD_PATH[$i]} == o/* ]] && DG_IS_EXA=$((DG_IS_EXA+1))
    if [[ ${DGD_MODE[$i]} != ONLINE || ( ${DGD_STATE[$i]} != NORMAL && ${DGD_STATE[$i]} != ADDING ) ]]; then
      warn "Disco ${DGD_NAME[$i]} (${DGD_PATH[$i]}): mode=${DGD_MODE[$i]} state=${DGD_STATE[$i]}"; unhealthy=1
    fi
  done
  (( unhealthy == 0 || ALLOW_UNHEALTHY )) || die "Diskgroup com discos não saudáveis. Resolva antes ou use --allow-unhealthy-dg."
  if (( DG_IS_EXA > 0 && DG_IS_EXA != ${#DGD_PATH[@]} )); then
    die "Diskgroup mistura griddisks Exadata (o/...) com outros discos. Cenário não suportado."
  fi
  if (( DG_IS_EXA )); then
    DG_IS_EXA=1
    [[ -n $EXA_CELLS ]] || die "Diskgroup $DG é Exadata (griddisks o/...). Use --exa-cell <cell> em vez de -d (veja --help, seção EXADATA)."
  elif [[ -n $EXA_CELLS ]]; then
    die "--exa-cell informado, mas o $DG não é um diskgroup Exadata."
  fi

  ok "DG=$DG tipo=$DG_TYPE estado=$DG_STATE discos=${#DGD_PATH[@]} total=${DG_TOTAL}MB livre=${DG_FREE}MB usable=${DG_USABLE}MB"
  info "AU=${DG_AU}MB setor=$DG_SECTOR compatible.asm=$DG_COMPAT_ASM | tamanho de referência dos discos: ${DG_OSMB_REF}MB"
}

load_dg_disks() {
  local rows a b c d e f g h k l m cnt line
  DGD_NUM=(); DGD_NAME=(); DGD_PATH=(); DGD_FG=(); DGD_TOTAL=(); DGD_OSMB=()
  DGD_HDR=(); DGD_MODE=(); DGD_STATE=(); DGD_FGT=(); DGD_SITE=()
  rows=$(sqlt <<'SQL'
select d.disk_number||'|'||nvl(d.name,'-')||'|'||d.path||'|'||nvl(d.failgroup,'-')||'|'||d.total_mb||'|'||nvl(d.os_mb,d.total_mb)||'|'||d.header_status||'|'||d.mode_status||'|'||d.state||'|'||nvl(d.failgroup_type,'REGULAR')||'|'||__SITECOL__ from v$asm_disk d where d.group_number = __DGNUM__ order by d.disk_number;
SQL
) || die "Falha consultando os discos do $DG."
  while IFS='|' read -r a b c d e f g h k l m; do
    [[ -n $a ]] || continue
    DGD_NUM+=("$a"); DGD_NAME+=("$b"); DGD_PATH+=("$c"); DGD_FG+=("$d"); DGD_TOTAL+=("$e")
    DGD_OSMB+=("$f"); DGD_HDR+=("$g"); DGD_MODE+=("$h"); DGD_STATE+=("$k"); DGD_FGT+=("$l"); DGD_SITE+=("$m")
  done <<<"$rows"
  (( ${#DGD_PATH[@]} > 0 )) || die "Nenhum disco encontrado no $DG."

  # tamanho de referência = OS_MB mais frequente entre os discos REGULAR
  line=$(for ((cnt=0; cnt<${#DGD_OSMB[@]}; cnt++)); do
           [[ ${DGD_FGT[$cnt]} == QUORUM ]] || echo "${DGD_OSMB[$cnt]}"
         done | sort | uniq -c | sort -k1,1nr -k2,2nr | head -1)
  DG_OSMB_REF=$(awk '{print $2}' <<<"$line")
  is_uint "$DG_OSMB_REF" || DG_OSMB_REF=0

  DG_USES_SITE=0; DG_DEFAULT_FG=1; DG_FGS=" "
  for ((cnt=0; cnt<${#DGD_PATH[@]}; cnt++)); do
    [[ ${DGD_SITE[$cnt]} != - ]] && DG_USES_SITE=1
    [[ ${DGD_FGT[$cnt]} == QUORUM ]] && continue
    [[ ${DGD_FG[$cnt]} == "${DGD_NAME[$cnt]}" ]] || DG_DEFAULT_FG=0
    [[ $DG_FGS == *" ${DGD_FG[$cnt]} "* ]] || DG_FGS+="${DGD_FG[$cnt]} "
  done
}

load_all_asm_disks() {
  local rows a b c d e
  ALL_GRP=(); ALL_NAME=(); ALL_PATH=(); ALL_HDR=(); ALL_OSMB=()
  rows=$(sqlt <<'SQL'
select d.group_number||'|'||nvl(d.name,'-')||'|'||d.path||'|'||d.header_status||'|'||nvl(d.os_mb,0) from v$asm_disk d order by d.path;
SQL
) || die "Falha consultando v\$asm_disk."
  while IFS='|' read -r a b c d e; do
    [[ -n $c ]] || continue
    ALL_GRP+=("$a"); ALL_NAME+=("$b"); ALL_PATH+=("$c"); ALL_HDR+=("$d"); ALL_OSMB+=("$e")
  done <<<"$rows"
}

#------------------------------------------------------------------------------
# Utilitários de device
#------------------------------------------------------------------------------
majmin() {  # maj:min decimal (segue symlink)
  local p=$1 out
  case $OS in
    Linux) out=$(stat -L -c '%t %T' "$p" 2>/dev/null) || return 1
           printf '%d:%d\n' "0x${out% *}" "0x${out#* }" ;;
    *)     out=$(ls -lL "$p" 2>/dev/null | awk '{sub(",","",$5); print $5":"$6}')
           [[ -n $out ]] || return 1; echo "$out" ;;
  esac
}

kfed_read() {
  [[ -x $GRID_HOME/bin/kfed ]] || return 1
  grid_env_root "$GRID_HOME/bin/kfed" read "$1" 2>/dev/null
}

kfed_header_status() {  # imprime "STATUS GRUPO" se houver header ASM; vazio se não
  local out hs gn
  out=$(kfed_read "$1") || return 0
  grep -q 'KFBTYP_DISKHEAD' <<<"$out" || return 0
  hs=$(awk '/kfdhdb.hdrsts:/{print $NF; exit}' <<<"$out")
  gn=$(awk '/kfdhdb.grpname:/{print $2; exit}' <<<"$out")
  echo "${hs:-?} ${gn:-?}"
}

nonzero_bytes() {  # $1=device $2=offset em MB $3=qtde MB
  dd if="$1" bs=1048576 skip="$2" count="$3" 2>/dev/null | tr -d '\000' | wc -c | tr -d ' '
}

asm_path_to_os() {
  case $1 in
    ORCL:*) echo "/dev/oracleasm/disks/${1#ORCL:}" ;;
    AFD:*)  awk -v l="${1#AFD:}" 'toupper($1)==toupper(l){print $2; exit}' <<<"$AFD_MAP" ;;
    /*)     echo "$1" ;;
  esac
}

load_afd_map() {
  AFD_RAW=$(as_grid "'$GRID_HOME/bin/asmcmd' afd_lslbl" 2>&1) || true
  AFD_MAP=$(awk '$NF ~ /^\/dev\// {print $1, $NF}' <<<"$AFD_RAW")
}

collect_asm_majmins() {
  local i op x l p
  ASM_MM=" "
  for ((i=0; i<${#ALL_PATH[@]}; i++)); do
    op=$(asm_path_to_os "${ALL_PATH[$i]}")
    [[ -n $op && -e $op ]] && ASM_MM+="$(majmin "$op") "
  done
  if [[ $OS == Linux ]]; then
    for x in /dev/oracleasm/disks/*; do [[ -b $x ]] && ASM_MM+="$(majmin "$x") "; done
    while read -r l p; do [[ -n $p && -e $p ]] && ASM_MM+="$(majmin "$p") "; done <<<"$AFD_MAP"
  fi
}

lsblk_kname_of_mm() {  # maj:min -> kname
  lsblk -nlo KNAME,MAJ:MIN 2>/dev/null | awk -v m="$1" '{gsub(/ /,"",$2)} $2==m{print $1; exit}'
}

perm_octal() {
  awk '{p=substr($1,2,9); s=""; for(i=0;i<3;i++){v=0
        if(substr(p,i*3+1,1)=="r")v+=4; if(substr(p,i*3+2,1)=="w")v+=2; if(substr(p,i*3+3,1)~/[xst]/)v+=1; s=s v}
        print s}'
}

linux_parent_of() {  # kname de partição -> kname do disco pai
  local k=$1 p
  p=$(lsblk -dno PKNAME "/dev/$k" 2>/dev/null | head -1 | tr -d ' ')
  if [[ -z $p && -e /sys/class/block/$k/partition ]]; then p=$(basename "$(readlink -f "/sys/class/block/$k/..")"); fi
  if [[ -z $p && -d /sys/class/block/$k/slaves ]]; then p=$(ls "/sys/class/block/$k/slaves" 2>/dev/null | head -1); fi
  echo "$p"
}

#------------------------------------------------------------------------------
# Método de provisionamento
#------------------------------------------------------------------------------
udev_rule_for() { grep -lF -- "${1##*/}\"" /etc/udev/rules.d/*.rules 2>/dev/null | head -1; }

detect_method() {
  section "Método de provisionamento"
  local i p m det="" c_asmlib=0 c_afd=0 c_udev=0 c_raw=0 c_unk=0 c_orcl=0 c_devasm=0 total=${#DGD_PATH[@]}
  for ((i=0; i<total; i++)); do
    p=${DGD_PATH[$i]}
    case $p in
      ORCL:*)                 c_asmlib=$((c_asmlib+1)); c_orcl=$((c_orcl+1)) ;;
      /dev/oracleasm/disks/*) c_asmlib=$((c_asmlib+1)); c_devasm=$((c_devasm+1)) ;;
      AFD:*)                  c_afd=$((c_afd+1)) ;;
      /*)
        if [[ $OS == AIX && $p == /dev/rhdisk* ]]; then c_raw=$((c_raw+1))
        elif [[ $OS == Linux && -n $(udev_rule_for "$p") ]]; then c_udev=$((c_udev+1))
        else c_unk=$((c_unk+1)); fi ;;
      *) c_unk=$((c_unk+1)) ;;
    esac
  done
  for m in asmlib afd udev raw; do
    eval "[[ \$c_$m -eq $total ]]" && det=$m
  done
  if [[ -z $det ]]; then
    if [[ $ACTION == add-only ]]; then det="path"
    elif (( c_unk > 0 )); then
      die "Não identifiquei como os discos atuais do $DG são provisionados (asmlib=$c_asmlib afd=$c_afd udev=$c_udev raw=$c_raw desconhecido=$c_unk). Provisione manualmente e use --add-only."
    elif [[ $METHOD == auto ]]; then
      die "Diskgroup com métodos MISTOS (asmlib=$c_asmlib afd=$c_afd udev=$c_udev raw=$c_raw). Informe --method."
    fi
  fi
  if [[ $METHOD == auto ]]; then METHOD=$det
  elif [[ -n $det && $det != path && $METHOD != "$det" ]]; then
    warn "Você forçou --method $METHOD, mas os discos atuais do $DG usam '$det'. Revise com MUITA atenção."
  fi
  PATH_STYLE="path"
  case $METHOD in
    asmlib) (( c_devasm > c_orcl )) && PATH_STYLE="devasm" || PATH_STYLE="orcl" ;;
    afd)    PATH_STYLE="afd" ;;
    udev)   UDEV_DIR=$(dirname "${DGD_PATH[0]}") ;;
  esac
  if [[ $METHOD == raw && $OS == Linux && $ACTION != add-only ]]; then
    die "Linux sem ASMLib/AFD/udev não tem persistência de nome/permissão — não suportado para provisionamento. Use --add-only."
  fi
  [[ $OS == SunOS && $ACTION != add-only ]] && die "Solaris: provisionamento automático não suportado. Prepare o slice e use --add-only."
  ok "Método: $METHOD | estilo de caminho: $PATH_STYLE"
}

prepare_method() {
  local out n p f
  case $METHOD in
    asmlib)
      ORACLEASM_BIN=$(command -v oracleasm 2>/dev/null || true)
      [[ -z $ORACLEASM_BIN && -x /usr/sbin/oracleasm ]] && ORACLEASM_BIN=/usr/sbin/oracleasm
      [[ -n $ORACLEASM_BIN ]] || die "Método asmlib, mas o comando oracleasm não foi encontrado."
      [[ $ACTION == add-only ]] && return 0
      out=$("$ORACLEASM_BIN" status 2>&1) || die "oracleasm status falhou: $out"
      grep -qiE ': no$' <<<"$out" && die "ASMLib não está carregado/montado neste nó: $(tr '\n' ' ' <<<"$out")"
      if [[ $REMOTE_MODE == ssh ]]; then
        for n in "${REMOTE_NODES[@]}"; do
          out=$(r_ro "$n" "$ORACLEASM_BIN status" 2>&1) || die "[$n] oracleasm status falhou: $out"
          grep -qiE ': no$' <<<"$out" && die "[$n] ASMLib não está carregado/montado: $out"
        done
      fi ;;
    afd)
      [[ $ACTION == add-only ]] && return 0
      out=$(as_grid "'$GRID_HOME/bin/asmcmd' afd_state" 2>&1)
      grep -q 'LOADED' <<<"$out" || die "ASMFD não está carregado neste nó: $out"
      if [[ $REMOTE_MODE == ssh ]]; then
        for n in "${REMOTE_NODES[@]}"; do
          out=$(r_ro "$n" "ORACLE_HOME=$GRID_HOME ORACLE_BASE=$ORA_BASE $GRID_HOME/bin/asmcmd afd_state" 2>&1)
          grep -q 'LOADED' <<<"$out" || die "[$n] ASMFD não está carregado: $out"
        done
      fi ;;
    udev)
      [[ $ACTION == add-only ]] && return 0
      udev_prepare ;;
  esac

  # permissões de referência (udev / raw)
  if [[ $METHOD == udev || $METHOD == raw ]]; then
    p=$(asm_path_to_os "${DGD_PATH[0]}")
    f=$(ls -lL "$p" 2>/dev/null)
    DG_OWNER=$(awk '{print $3}' <<<"$f"); DG_GROUP=$(awk '{print $4}' <<<"$f")
    DG_MODE=$(perm_octal <<<"$f")
    OWNER_EFF=${OWNER:-$DG_OWNER}; GROUP_EFF=${GROUP:-$DG_GROUP}; PERM_EFF=${PERM:-$DG_MODE}
    [[ -n $OWNER_EFF && -n $GROUP_EFF && -n $PERM_EFF ]] || die "Não consegui ler dono/grupo/modo de $p. Informe --owner/--group/--perm."
    info "Permissão de referência: $OWNER_EFF:$GROUP_EFF $PERM_EFF (de $p)"
  fi
}

detect_partition_style() {
  local i op real k t c_part=0 c_disk=0 parent pt
  [[ $OS == Linux && $ACTION != add-only ]] || return 0
  for ((i=0; i<${#DGD_PATH[@]}; i++)); do
    op=$(asm_path_to_os "${DGD_PATH[$i]}"); [[ -n $op && -e $op ]] || continue
    if [[ $op == /dev/oracleasm/disks/* ]]; then k=$(lsblk_kname_of_mm "$(majmin "$op")")
    else real=$(readlink -f "$op"); k=${real##*/}; fi
    [[ -n $k ]] || continue
    t=$(lsblk -dno TYPE "/dev/$k" 2>/dev/null | head -1 | tr -d ' ')
    if [[ $t == part ]]; then
      c_part=$((c_part+1))
      if [[ -z $DG_PTTYPE ]]; then
        parent=$(linux_parent_of "$k")
        if [[ -n $parent ]]; then
          pt=$(blkid -p -o value -s PTTYPE "/dev/$parent" 2>/dev/null)
          [[ $pt == dos ]] && pt=msdos
          DG_PTTYPE=$pt
        fi
      fi
    else
      c_disk=$((c_disk+1))
    fi
  done
  if (( c_part >= c_disk && c_part > 0 )); then DG_PART_STYLE="yes"; elif (( c_disk > 0 )); then DG_PART_STYLE="no"; fi
  info "Discos atuais: particionados=$c_part inteiros=$c_disk | tabela=${DG_PTTYPE:-?}"
}

#------------------------------------------------------------------------------
# udev: geração de regra a partir de um template REAL do DG
#------------------------------------------------------------------------------
udev_value() {  # calcula o identificador do template para um device
  local dev=$1 k prog first d prop attr devpath
  k=${dev##*/}
  case $UDEV_KEY in
    'RESULT==')
      devpath=$(udevadm info -q path -n "$dev" 2>/dev/null)
      prog=$UDEV_PROG
      prog=${prog//\%k/$k}; prog=${prog//\$kernel/$k}
      prog=${prog//\%N//dev/$k}; prog=${prog//\$devnode//dev/$k}; prog=${prog//\$tempnode//dev/$k}
      prog=${prog//\%p/$devpath}; prog=${prog//\$devpath/$devpath}
      if [[ $prog == *'$parent'* || $prog == *'%P'* ]]; then
        local pk; pk=$(linux_parent_of "$k"); [[ -n $pk ]] || pk=$k
        prog=${prog//\$parent/$pk}; prog=${prog//\%P/$pk}
      fi
      first=${prog%% *}
      if [[ $first != /* ]]; then
        for d in /usr/lib/udev /lib/udev /sbin /usr/sbin /usr/bin; do
          [[ -x $d/$first ]] && { prog="$d/$prog"; break; }
        done
      fi
      sh -c "$prog" 2>/dev/null | head -1 ;;
    ENV\{*)
      prop=${UDEV_KEY#ENV\{}; prop=${prop%%\}*}
      udevadm info --query=property --name="$dev" 2>/dev/null | awk -v k="$prop" 'index($0,k"=")==1{print substr($0,length(k)+2); exit}' ;;
    ATTRS\{*)
      attr=${UDEV_KEY%%==*}
      udevadm info -a -n "$dev" 2>/dev/null | awk -v a="$attr==\"" '{s=$0; sub(/^[ \t]+/,"",s)} index(s,a)==1{s=substr(s,length(a)+1); sub(/"$/,"",s); print s; exit}' ;;
  esac
}

count_occ() { awk -v s="$2" 'BEGIN{n=0} {l=$0; while((i=index(l,s))>0){n++; l=substr(l,i+length(s))}} END{print n}' <<<"$1"; }

udev_prepare() {
  local i p base f line k tmp v n
  for ((i=0; i<${#DGD_PATH[@]}; i++)); do
    p=${DGD_PATH[$i]}; base=${p##*/}
    f=$(udev_rule_for "$p"); [[ -n $f ]] || continue
    n=$(grep -v '^[[:space:]]*#' "$f" | grep -cF -- "$base\"")
    [[ $n == 1 ]] || continue
    line=$(grep -v '^[[:space:]]*#' "$f" | grep -F -- "$base\"")
    [[ $line == *'\' ]] && continue
    UDEV_FILE=$f; UDEV_TLINE=$line; UDEV_OLDLABEL=$base; UDEV_TDEV=$(readlink -f "$p")
    break
  done
  [[ -n $UDEV_TLINE ]] || die "Não encontrei uma regra udev de uma linha (única) para os discos do $DG em /etc/udev/rules.d. Provisione manualmente e use --add-only."

  for k in 'RESULT==' 'ENV{ID_SERIAL}==' 'ENV{ID_WWN}==' 'ENV{ID_SCSI_SERIAL}==' 'ENV{ID_SERIAL_SHORT}==' \
           'ENV{DM_UUID}==' 'ENV{DM_NAME}==' 'ATTRS{wwid}==' 'ATTRS{serial}==' 'ENV{ID_PART_ENTRY_UUID}=='; do
    if [[ $UDEV_TLINE == *"$k\""* ]]; then
      UDEV_KEY=$k; tmp=${UDEV_TLINE#*"$k\""}; UDEV_OLDVAL=${tmp%%\"*}; break
    fi
  done
  [[ -n $UDEV_KEY ]] || die "Regra udev template sem identificador reconhecido (RESULT/ID_SERIAL/ID_WWN/DM_UUID/...): $UDEV_TLINE"
  [[ $UDEV_KEY == 'ENV{ID_PART_ENTRY_UUID}==' ]] && die "Template udev usa ID_PART_ENTRY_UUID (único por partição) — gere a regra manualmente e use --add-only."
  if [[ $UDEV_KEY == 'RESULT==' ]]; then
    tmp=${UDEV_TLINE#*PROGRAM}; tmp=${tmp#*\"}; UDEV_PROG=${tmp%%\"*}
    [[ -n $UDEV_PROG ]] || die "Regra udev com RESULT mas sem PROGRAM legível."
  fi
  if [[ $UDEV_TLINE == *'KERNEL=="'* ]]; then tmp=${UDEV_TLINE#*KERNEL==\"}; UDEV_KGLOB=${tmp%%\"*}; fi
  [[ $(lsblk -dno TYPE "$UDEV_TDEV" 2>/dev/null | tr -d ' ') == part ]] && UDEV_PART_RULE=1

  v=$(udev_value "$UDEV_TDEV")
  [[ $v == "$UDEV_OLDVAL" ]] || die "Validação do template udev FALHOU: para $UDEV_TDEV calculei '$v', a regra tem '$UDEV_OLDVAL'. Regra: $UDEV_TLINE"
  [[ $(count_occ "$UDEV_TLINE" "$UDEV_OLDLABEL\"") == 1 ]] || die "O label '$UDEV_OLDLABEL' aparece mais de uma vez no template udev."
  ok "Template udev: $UDEV_FILE ($UDEV_KEY, regra de $([[ $UDEV_PART_RULE == 1 ]] && echo partição || echo disco))"
  info "  $UDEV_TLINE"

  if [[ $REMOTE_MODE == ssh ]]; then
    for n in "${REMOTE_NODES[@]}"; do
      tmp=$(r_ro "$n" "grep -v '^[[:space:]]*#' '$UDEV_FILE' 2>/dev/null | grep -cF -- '$UDEV_OLDLABEL\"'" 2>/dev/null)
      [[ $tmp == 1 ]] || die "[$n] O arquivo $UDEV_FILE não tem a mesma regra do disco $UDEV_OLDLABEL. Regras udev divergentes entre os nós."
    done
  fi
}

udev_build_line() {  # $1=novo valor  $2=novo label
  local l=$UDEV_TLINE oldtok newtok
  oldtok="$UDEV_KEY\"$UDEV_OLDVAL\""; newtok="$UDEV_KEY\"$1\""
  [[ $(count_occ "$l" "$oldtok") == 1 ]] || { err "Identificador aparece mais de uma vez no template."; return 1; }
  l=${l/"$oldtok"/"$newtok"}
  l=${l/"$UDEV_OLDLABEL\""/"$2\""}
  printf '%s\n' "$l"
}

#------------------------------------------------------------------------------
# Checagem de disco — Linux
#------------------------------------------------------------------------------
CK_FAIL=""; CK_WARN=""; CK_REAL=""; CK_KNAME=""; CK_TYPE=""; CK_USE=""; CK_MB=0; CK_SS=0
CK_ID=""; CK_BYID=""; CK_ISPART=0; CK_PART=""; CK_AIXFIX=0

ck_reset() {
  CK_FAIL=""; CK_WARN=""; CK_REAL=""; CK_KNAME=""; CK_TYPE=""; CK_USE=""; CK_MB=0; CK_SS=0
  CK_ID=""; CK_BYID=""; CK_ISPART=0; CK_PART=""; CK_AIXFIX=0
}

linux_dev_check() {
  local in=$1 d real kname type ch mp x mm bytes nz nz2 sig out hs
  ck_reset
  d=$in; [[ $d == /* ]] || d="/dev/$d"
  [[ -e $d ]] || { CK_FAIL="não existe"; return 0; }
  real=$(readlink -f "$d"); kname=${real##*/}; CK_REAL=$real; CK_KNAME=$kname
  [[ -b $real ]] || { CK_FAIL="não é block device ($real)"; return 0; }
  type=$(lsblk -dno TYPE "$real" 2>/dev/null | head -1 | tr -d '[:space:]'); CK_TYPE=$type
  case $type in
    disk)  CK_USE=$real ;;
    mpath) CK_USE="/dev/mapper/$(cat "/sys/class/block/$kname/dm/name" 2>/dev/null)"
           [[ -b $CK_USE ]] || CK_USE=$real ;;
    part)  if (( USE_EXISTING_PART )); then CK_ISPART=1; CK_USE=$real; CK_PART=$real
           else CK_FAIL="é uma PARTIÇÃO — informe o disco inteiro (ou use --use-existing-partition)"; return 0; fi ;;
    *)     CK_FAIL="tipo '$type' não suportado (esperado disk/mpath)"; return 0 ;;
  esac

  ch=$(lsblk -nlo KNAME,TYPE "$real" 2>/dev/null | awk 'NR>1{print $2":"$1}' | sort -u | tr '\n' ' ')
  if [[ -n $ch ]]; then
    [[ " $ch" == *" mpath:"* ]] && { CK_FAIL="é um CAMINHO de multipath — use o /dev/mapper/... correspondente"; return 0; }
    CK_FAIL="possui partições/dependentes: $ch"; return 0
  fi
  if [[ -d /sys/class/block/$kname/holders && -n $(ls -A "/sys/class/block/$kname/holders" 2>/dev/null) ]]; then
    CK_FAIL="em uso por: $(ls "/sys/class/block/$kname/holders" | tr '\n' ' ')"; return 0
  fi
  mp=$(lsblk -nlo MOUNTPOINT "$real" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)
  [[ -z $mp ]] || { CK_FAIL="montado em $mp"; return 0; }
  awk -v r="$real" '$1==r{f=1} END{exit !f}' /proc/swaps 2>/dev/null && { CK_FAIL="é swap"; return 0; }
  grep -qw "$kname" /proc/mdstat 2>/dev/null && { CK_FAIL="membro de RAID md"; return 0; }
  if command -v pvs >/dev/null 2>&1; then
    while read -r x; do
      [[ -n $x && $(readlink -f "$x") == "$real" ]] && { CK_FAIL="é PV do LVM"; return 0; }
    done < <(pvs --noheadings -o pv_name 2>/dev/null | tr -d ' ')
  fi
  sig=$(blkid -p -o export "$real" 2>/dev/null | grep -E '^(TYPE|PTTYPE|LABEL|UUID)=' | tr '\n' ' ')
  [[ -z $sig ]] || { CK_FAIL="possui assinatura: $sig"; return 0; }
  if command -v wipefs >/dev/null 2>&1; then
    out=$(wipefs "$real" 2>/dev/null | grep -viE '^(offset|device)' | grep -v '^-' | grep -v '^[[:space:]]*$')
    [[ -z $out ]] || { CK_FAIL="wipefs encontrou assinaturas: $(tr '\n' ' ' <<<"$out")"; return 0; }
  fi
  if [[ -n $ORACLEASM_BIN ]]; then
    out=$("$ORACLEASM_BIN" querydisk "$real" 2>&1)
    [[ $out == *"is marked an ASM disk"* ]] && { CK_FAIL="já marcado no ASMLib: $out"; return 0; }
  fi
  hs=$(kfed_header_status "$real")
  [[ -z $hs ]] || { CK_FAIL="possui HEADER ASM (status/grupo: $hs)"; return 0; }

  mm=$(lsblk -nlo MAJ:MIN "$real" 2>/dev/null | tr -d ' ' | tr '\n' ' ')
  if [[ $type == mpath ]]; then
    for x in /sys/class/block/"$kname"/slaves/*; do [[ -e $x/dev ]] && mm+="$(cat "$x/dev") "; done
  fi
  for x in $mm; do
    [[ $ASM_MM == *" $x "* ]] && { CK_FAIL="o device (maj:min $x) JÁ é usado pelo ASM/ASMLib/AFD"; return 0; }
  done
  if command -v fuser >/dev/null 2>&1 && fuser -s "$real" 2>/dev/null; then
    CK_FAIL="aberto por processo(s): $(fuser "$real" 2>&1 | tr -s ' ')"; return 0
  fi

  bytes=$(blockdev --getsize64 "$real" 2>/dev/null); is_uint "$bytes" || { CK_FAIL="tamanho ilegível"; return 0; }
  CK_MB=$((bytes/1048576)); (( CK_MB > 2 )) || { CK_FAIL="tamanho ${CK_MB}MB inválido"; return 0; }
  CK_SS=$(blockdev --getss "$real" 2>/dev/null); is_uint "$CK_SS" || CK_SS=0

  nz=$(nonzero_bytes "$real" 0 2); nz2=$(nonzero_bytes "$real" $((CK_MB-1)) 1)
  if (( nz > 0 || nz2 > 0 )); then
    if (( ALLOW_DIRTY )); then CK_WARN+="dados não-zerados (início=${nz}B, fim=${nz2}B) aceitos por --allow-dirty; "
    else CK_FAIL="NÃO está zerado (bytes não-nulos: início=${nz}, fim=${nz2}). Pode ter dados antigos. Se tiver CERTEZA use --allow-dirty"; return 0; fi
  fi

  CK_ID=$(udevadm info --query=property --name="$real" 2>/dev/null \
          | awk -F= '$1=="ID_WWN"||$1=="ID_SERIAL"||$1=="DM_UUID"{printf "%s=%s ", $1, $2}')
  for x in /dev/disk/by-id/*; do
    [[ -L $x && $(readlink -f "$x") == "$real" ]] && CK_BYID+="${x##*/} "
  done
  [[ -n $CK_BYID ]] || CK_WARN+="sem link em /dev/disk/by-id (identificação persistente prejudicada); "
  return 0
}

#------------------------------------------------------------------------------
# Checagem de disco — AIX
#------------------------------------------------------------------------------
aix_dev_check() {
  local in=$1 h st pv vg rp raw out mm hs nz nz2
  ck_reset
  h=${in##*/}; h=${h#r}
  [[ $h =~ ^hdisk[0-9]+$ ]] || { CK_FAIL="nome inválido (esperado hdiskN)"; return 0; }
  raw="/dev/r$h"; CK_KNAME=$h; CK_REAL=$raw; CK_USE=$raw; CK_TYPE="disk"
  st=$(lsdev -Cc disk -l "$h" -F status 2>/dev/null)
  [[ $st == Available ]] || { CK_FAIL="status '${st:-inexistente}' (esperado Available)"; return 0; }
  read -r pv vg <<<"$(lspv 2>/dev/null | awk -v d="$h" '$1==d{print $2, $3}')"
  [[ -z $vg || $vg == None ]] || { CK_FAIL="pertence ao VG $vg"; return 0; }
  [[ -z $pv || $pv == none ]] || { CK_FAIL="possui PVID $pv (se é realmente livre: chdev -l $h -a pv=clear)"; return 0; }
  rp=$(lsattr -El "$h" -a reserve_policy -F value 2>/dev/null)
  if (( IS_RAC )) && [[ -n $rp && $rp != no_reserve ]]; then
    if (( FIX_AIX_ATTRS )); then CK_AIXFIX=1; CK_WARN+="reserve_policy=$rp será ajustado para no_reserve; "
    else CK_FAIL="reserve_policy=$rp (RAC exige no_reserve). Use --fix-aix-attrs ou: chdev -l $h -a reserve_policy=no_reserve"; return 0; fi
  fi
  CK_ID=$(lsattr -El "$h" -a unique_id -F value 2>/dev/null)
  CK_MB=$(bootinfo -s "$h" 2>/dev/null); is_uint "$CK_MB" && (( CK_MB > 2 )) || { CK_FAIL="tamanho não identificado"; return 0; }
  CK_SS=0
  for mm in "$(majmin "$raw")" "$(majmin "/dev/$h")"; do
    [[ -n $mm && $ASM_MM == *" $mm "* ]] && { CK_FAIL="device (maj:min $mm) JÁ é usado pelo ASM"; return 0; }
  done
  out=$(fuser "$raw" 2>/dev/null | tr -d '[:space:]')
  [[ -z $out ]] || { CK_FAIL="aberto por processo(s): $out"; return 0; }
  hs=$(kfed_header_status "$raw")
  [[ -z $hs ]] || { CK_FAIL="possui HEADER ASM (status/grupo: $hs)"; return 0; }
  nz=$(nonzero_bytes "$raw" 0 2); nz2=$(nonzero_bytes "$raw" $((CK_MB-1)) 1)
  if (( nz > 0 || nz2 > 0 )); then
    if (( ALLOW_DIRTY )); then CK_WARN+="dados não-zerados aceitos por --allow-dirty; "
    else CK_FAIL="NÃO está zerado (início=${nz}, fim=${nz2}). Se tiver CERTEZA use --allow-dirty"; return 0; fi
  fi
  return 0
}

#------------------------------------------------------------------------------
# Discos novos: validação local + remota
#------------------------------------------------------------------------------
check_new_disks() {
  section "Validação dos discos (${#DISKS_IN[@]})"
  local i j in fails=()
  for ((i=0; i<${#DISKS_IN[@]}; i++)); do
    in=${DISKS_IN[$i]}
    case $OS in Linux) linux_dev_check "$in" ;; AIX) aix_dev_check "$in" ;; esac
    if [[ -n $CK_FAIL ]]; then fails+=("$in: $CK_FAIL"); err "$in: $CK_FAIL"; continue; fi
    for ((j=0; j<${#N_REAL[@]}; j++)); do
      [[ ${N_REAL[$j]} == "$CK_REAL" ]] && { fails+=("$in: é o mesmo device que ${N_IN[$j]} ($CK_REAL)"); continue 2; }
    done
    N_IN+=("$in"); N_REAL+=("$CK_REAL"); N_KNAME+=("$CK_KNAME"); N_TYPE+=("$CK_TYPE"); N_USE+=("$CK_USE")
    N_MB+=("$CK_MB"); N_SS+=("$CK_SS"); N_ID+=("$CK_ID"); N_BYID+=("$CK_BYID"); N_ISPART+=("$CK_ISPART")
    N_PART+=("$CK_PART"); N_AIXFIX+=("$CK_AIXFIX"); N_WARN+=("$CK_WARN"); N_RDEV+=(""); N_RFIX+=(""); N_UDEVPREV+=("")
    ok "$in -> $CK_REAL ($CK_TYPE, ${CK_MB}MB, setor ${CK_SS:-?}) ${CK_BYID:+by-id: ${CK_BYID%% *}}"
    [[ -n $CK_WARN ]] && warn "$in: $CK_WARN"
  done
  if (( ${#fails[@]} > 0 )); then
    err "Disco(s) reprovado(s) na validação — NADA foi alterado:"
    for in in "${fails[@]}"; do printf '      - %s\n' "$in" >&2; done
    exit 1
  fi
  check_sizes
  if (( IS_RAC )); then
    case $OS in Linux) remote_visibility_linux ;; AIX) remote_map_aix ;; esac
  fi
  if [[ $METHOD == asmlib ]]; then check_asmlib_scanorder; fi
}

check_sizes() {
  local i eff diff fail=0
  for ((i=0; i<${#N_IN[@]}; i++)); do
    if (( N_SS[i] > 0 && DG_SECTOR > 0 && N_SS[i] > DG_SECTOR )); then
      err "${N_IN[$i]}: setor lógico ${N_SS[$i]} > setor do DG ($DG_SECTOR). O ASM vai recusar."; fail=1
    elif (( N_SS[i] > 0 && DG_SECTOR > 0 && N_SS[i] != DG_SECTOR )); then
      warn "${N_IN[$i]}: setor lógico ${N_SS[$i]} difere do setor do DG ($DG_SECTOR)."
    fi
    (( DG_OSMB_REF > 0 )) || continue
    eff=${N_MB[$i]}
    diff=$(( (eff > DG_OSMB_REF ? eff - DG_OSMB_REF : DG_OSMB_REF - eff) * 100 / DG_OSMB_REF ))
    if (( diff > SIZE_TOL )); then
      if (( ALLOW_SIZE_MISMATCH )); then
        warn "${N_IN[$i]}: ${eff}MB vs referência ${DG_OSMB_REF}MB (${diff}%) — aceito por --allow-size-mismatch. Discos de tamanhos diferentes desbalanceiam o I/O."
      else
        err "${N_IN[$i]}: ${eff}MB vs referência do DG ${DG_OSMB_REF}MB (diferença ${diff}% > ${SIZE_TOL}%)."; fail=1
      fi
    fi
  done
  (( fail == 0 )) || die "Validação de tamanho/setor falhou (use --allow-size-mismatch se for intencional)."
}

check_asmlib_scanorder() {
  local i has_mp=0 cfg
  for ((i=0; i<${#N_IN[@]}; i++)); do [[ ${N_TYPE[$i]} == mpath ]] && has_mp=1; done
  (( has_mp )) || return 0
  cfg=$(cat /etc/sysconfig/oracleasm* 2>/dev/null)
  if ! grep -qE '^ORACLEASM_SCANORDER=.*(dm|mapper)' <<<"$cfg"; then
    die "Disco multipath com ASMLib, mas ORACLEASM_SCANORDER não prioriza dm. O ASMLib pode usar UM caminho só (sdX). Configure ORACLEASM_SCANORDER=\"dm\" e ORACLEASM_SCANEXCLUDE=\"sd\" em todos os nós."
  fi
}

remote_visibility_linux() {
  local i n ids id script r chk sorted
  if [[ $REMOTE_MODE != ssh ]]; then
    warn "Modo remoto '$REMOTE_MODE': a visibilidade nos outros nós será validada pelo ASM (gv\$asm_disk) ANTES do ALTER."
    return 0
  fi
  for ((i=0; i<${#N_IN[@]}; i++)); do
    ids=${N_BYID[$i]}
    [[ -n $ids ]] || die "${N_IN[$i]} não tem /dev/disk/by-id: impossível localizá-lo com segurança nos outros nós."
    sorted=""
    for id in $ids; do case $id in wwn-*|dm-uuid-mpath-*|scsi-3*|nvme-eui.*) sorted="$id $sorted" ;; *-part[0-9]*) ;; *) sorted+="$id " ;; esac; done
    script="for i in $sorted; do if [ -e /dev/disk/by-id/\$i ]; then p=\$(readlink -f /dev/disk/by-id/\$i); case \$p in /dev/dm-*) n=\$(cat /sys/class/block/\${p##*/}/dm/name 2>/dev/null); [ -n \"\$n\" ] && p=/dev/mapper/\$n;; esac; echo \$p; exit 0; fi; done; exit 1"
    for n in "${REMOTE_NODES[@]}"; do
      r=$(r_ro "$n" "$script") || die "${N_IN[$i]} NÃO está visível no nó $n (by-id: $sorted). Verifique zoning/attach/multi-attach."
      chk=$(r_ro "$n" "lsblk -nlo KNAME,TYPE,MOUNTPOINT $r 2>/dev/null | awk 'NR>1 || \$3!=\"\"'; blkid -p -o export $r 2>/dev/null | grep -E '^(TYPE|PTTYPE)='")
      [[ -z $chk ]] && [[ $r =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || die "No nó $n o device $r (= ${N_IN[$i]}) NÃO está limpo: $chk"
      N_RDEV[$i]+="$n=$r "
      ok "[$n] ${N_IN[$i]} visível como $r e limpo"
    done
  done
}

remote_map_aix() {
  local i n uid script out rh pvvg rp
  if [[ $REMOTE_MODE != ssh ]]; then
    warn "Modo remoto '$REMOTE_MODE': confira nos outros nós que o hdisk (unique_id) está livre e com no_reserve."
    return 0
  fi
  for ((i=0; i<${#N_IN[@]}; i++)); do
    uid=${N_ID[$i]}
    [[ -n $uid && $uid =~ ^[A-Za-z0-9._-]+$ ]] || die "${N_IN[$i]} sem unique_id utilizável — não consigo mapear nos outros nós. Use --remote manual."
    script="for d in \$(lsdev -Cc disk -F name); do u=\$(lsattr -El \$d -a unique_id -F value 2>/dev/null); if [ \"\$u\" = '$uid' ]; then echo \$d; lspv | awk -v d=\$d '\$1==d{print \$2, \$3}'; lsattr -El \$d -a reserve_policy -F value 2>/dev/null; exit 0; fi; done; exit 1"
    for n in "${REMOTE_NODES[@]}"; do
      out=$(r_ro "$n" "$script") || die "${N_IN[$i]} (unique_id) NÃO encontrado no nó $n."
      rh=$(sed -n 1p <<<"$out"); pvvg=$(sed -n 2p <<<"$out"); rp=$(sed -n 3p <<<"$out")
      [[ $rh =~ ^hdisk[0-9]+$ ]] || die "[$n] retorno inesperado: $out"
      case $pvvg in "none None"|"none None "*) ;; *) die "[$n] $rh não está livre (PVID/VG: $pvvg)." ;; esac
      if [[ -n $rp && $rp != no_reserve ]]; then
        (( FIX_AIX_ATTRS )) || die "[$n] $rh com reserve_policy=$rp. Use --fix-aix-attrs."
        N_RFIX[$i]+="$n "
      fi
      N_RDEV[$i]+="$n=$rh "
      ok "[$n] ${N_IN[$i]} = $rh"
    done
  done
}

rdev_of() {  # $1=índice $2=nó
  local x
  for x in ${N_RDEV[$1]:-}; do [[ ${x%%=*} == "$2" ]] && { echo "${x#*=}"; return 0; }; done
  return 1
}

#------------------------------------------------------------------------------
# Labels / nomes
#------------------------------------------------------------------------------
# gen_names <src> <taken> <qtde> <prefixo> <largura> <início> <descrição>
# resultado em GEN_OUT
gen_names() {
  local src=$1 taken=$2 cnt=$3 fpre=$4 fwid=$5 fstart=$6 what=$7
  local stats top second pre width x num nums_taken=" " max=0 n cand tab padw shortv
  tab=$(printf '\t')
  GEN_OUT=()
  if [[ -n $fpre ]]; then
    pre=$fpre
  else
    stats=$(printf '%s\n' "$src" | awk 'NF{ if (match($0,/[0-9]+$/) && RSTART>1) c[substr($0,1,RSTART-1)]++ } END{for (p in c) printf "%d\t%s\n", c[p], p}' \
            | sort -t "$tab" -k1,1nr -k2,2)
    [[ -n $stats ]] || { err "Não consegui deduzir o padrão de $what (nenhum termina em número). Use --prefix."; return 1; }
    top=$(sed -n 1p <<<"$stats"); second=$(sed -n 2p <<<"$stats")
    if [[ -n $second && ${top%%"$tab"*} == "${second%%"$tab"*}" ]]; then
      err "Padrão de $what ambíguo (empate): $(tr '\t\n' '= ' <<<"$stats") — use --prefix."; return 1
    fi
    pre=${top#*"$tab"}
    [[ -n $second ]] && warn "Mais de um prefixo de $what no DG ($(tr '\t\n' '= ' <<<"$stats")); usando o dominante '$pre'."
  fi

  # largura (zero-padding) a partir do DG
  padw=$(printf '%s\n' "$src" | awk -v p="$pre" 'NF && index(toupper($0),toupper(p))==1 { n=substr($0,length(p)+1); if (n ~ /^0[0-9]+$/) w[length(n)]++ }
          END{b=0; for (k in w) if (w[k]>b || (w[k]==b && k+0>bk+0)) {b=w[k]; bk=k}; print (b?bk:0)}')
  if [[ -n $fwid ]]; then width=$fwid; else width=$padw; fi
  if (( width > 0 )); then
    shortv=$(printf '%s\n' "$src" | awk -v p="$pre" -v w="$width" 'NF && index(toupper($0),toupper(p))==1 { n=substr($0,length(p)+1); if (n ~ /^[0-9]+$/ && length(n)<w) printf "%s ", $0 }')
    [[ -n $shortv ]] && warn "Inconsistência de padding em $what (padrão ${width} dígitos): $shortv"
  fi

  # números ocupados (DG + globais), comparação sem diferenciar maiúsculas
  while read -r x; do
    [[ -n $x ]] || continue
    [[ $(upper "$x") == "$(upper "$pre")"* ]] || continue
    num=${x:${#pre}}
    [[ $num =~ ^[0-9]+$ ]] || continue
    num=$((10#$num))
    nums_taken+="$num "
    (( num > max )) && max=$num
  done <<<"$(printf '%s\n%s\n' "$src" "$taken")"

  if [[ -n $fstart ]]; then n=$((10#$fstart)); else n=$((max+1)); fi
  while (( ${#GEN_OUT[@]} < cnt )); do
    printf -v cand '%s%0*d' "$pre" "$width" "$n"
    if [[ $nums_taken == *" $n "* ]] || grep -qixF -- "$cand" <<<"$taken"; then
      [[ -n $fstart ]] && { err "$what '$cand' (número $n) já está em uso."; return 1; }
      n=$((n+1)); continue
    fi
    GEN_OUT+=("$cand"); nums_taken+="$n "; taken+=$'\n'"$cand"; n=$((n+1))
  done
  info "Padrão de $what: prefixo='$pre' padding=$width maior número em uso=$max → ${GEN_OUT[*]}"
  return 0
}

label_of_path() {
  local p=$1
  case $METHOD in
    asmlib) p=${p#ORCL:}; echo "${p##*/}" ;;
    afd)    echo "${p#AFD:}" ;;
    udev)   echo "${p##*/}" ;;
    *)      echo "-" ;;
  esac
}

global_labels() {
  local f
  case $METHOD in
    asmlib) [[ -n $ORACLEASM_BIN ]] && "$ORACLEASM_BIN" listdisks 2>/dev/null ;;
    afd)    awk '{print $1}' <<<"$AFD_MAP" ;;
    udev)   [[ -d $UDEV_DIR ]] && ls -1 "$UDEV_DIR" 2>/dev/null
            for f in /etc/udev/rules.d/*.rules; do
              [[ -r $f ]] && grep -ohE '(SYMLINK\+?|NAME)="[^"]*"' "$f" | sed -E 's/.*="([^"]*)"/\1/' | tr ' ' '\n' | awk -F/ '{print $NF}'
            done ;;
  esac
}

path_for_label() {
  case $METHOD in
    asmlib) [[ $PATH_STYLE == devasm ]] && echo "/dev/oracleasm/disks/$1" || echo "ORCL:$1" ;;
    afd)    echo "AFD:$1" ;;
    udev)   echo "$UDEV_DIR/$1" ;;
  esac
}

gen_labels_and_names() {
  section "Labels e nomes ASM"
  local cnt=${#N_IN[@]} i src="" taken="" l arr=() eq=0 namesrc="" nametaken=""
  if [[ $ACTION != add-only ]]; then N_LABEL=(); fi
  N_NAME=()

  if [[ $ACTION != add-only ]]; then
    case $METHOD in
      asmlib|afd|udev)
        for ((i=0; i<${#DGD_PATH[@]}; i++)); do src+="$(label_of_path "${DGD_PATH[$i]}")"$'\n'; done
        taken="$src$(global_labels)"
        if [[ -n $LABELS_IN ]]; then
          IFS=',' read -r -a arr <<<"$LABELS_IN"
          (( ${#arr[@]} == cnt )) || die "--labels tem ${#arr[@]} itens, mas são $cnt discos."
          for l in "${arr[@]}"; do
            l=$(trim "$l")
            grep -qixF -- "$l" <<<"$taken" && die "Label '$l' já está em uso."
            N_LABEL+=("$l"); taken+=$'\n'"$l"
          done
        else
          gen_names "$src" "$taken" "$cnt" "$PREFIX" "$WIDTH" "$START_NUM" "label" || die "Falha ao gerar labels."
          N_LABEL=("${GEN_OUT[@]}")
        fi
        for ((i=0; i<cnt; i++)); do
          if [[ $METHOD == udev ]]; then
            [[ ${N_LABEL[$i]} =~ ^[A-Za-z0-9_.+-]{1,64}$ ]] || die "Label udev inválido: ${N_LABEL[$i]}"
          else
            N_LABEL[$i]=$(upper "${N_LABEL[$i]}")
            [[ ${N_LABEL[$i]} =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "Label inválido para $METHOD: ${N_LABEL[$i]} (A-Z, 0-9, _, até 30, começa com letra)."
          fi
        done ;;
      *) for ((i=0; i<cnt; i++)); do N_LABEL+=("-"); done ;;
    esac
  fi

  # convenção NAME == label?
  if [[ $METHOD == asmlib || $METHOD == afd || $METHOD == udev ]]; then
    for ((i=0; i<${#DGD_PATH[@]}; i++)); do
      [[ $(upper "$(label_of_path "${DGD_PATH[$i]}")") == "$(upper "${DGD_NAME[$i]}")" ]] && eq=$((eq+1))
    done
    (( eq == ${#DGD_PATH[@]} )) && NAME_EQ_LABEL=1
  fi
  info "Convenção do DG: nome ASM $([[ $NAME_EQ_LABEL == 1 ]] && echo '= label' || echo '≠ label (padrão próprio)')"

  for ((i=0; i<${#DGD_NAME[@]}; i++)); do namesrc+="${DGD_NAME[$i]}"$'\n'; done
  for ((i=0; i<${#ALL_NAME[@]}; i++)); do [[ ${ALL_GRP[$i]} == "$DG_NUM" ]] && nametaken+="${ALL_NAME[$i]}"$'\n'; done

  if [[ -n $NAMES_IN ]]; then
    IFS=',' read -r -a arr <<<"$NAMES_IN"
    (( ${#arr[@]} == cnt )) || die "--names tem ${#arr[@]} itens, mas são $cnt discos."
    for l in "${arr[@]}"; do N_NAME+=("$(upper "$(trim "$l")")"); done
  elif (( NAME_EQ_LABEL )); then
    for ((i=0; i<cnt; i++)); do N_NAME+=("$(upper "${N_LABEL[$i]}")"); done
  else
    if [[ $METHOD == raw || $METHOD == path ]]; then
      gen_names "$namesrc" "$nametaken" "$cnt" "$PREFIX" "$WIDTH" "$START_NUM" "nome ASM" || die "Falha ao gerar nomes ASM."
    else
      gen_names "$namesrc" "$nametaken" "$cnt" "" "" "" "nome ASM" || die "Falha ao gerar nomes ASM (use --names)."
    fi
    for ((i=0; i<cnt; i++)); do N_NAME+=("$(upper "${GEN_OUT[$i]}")"); done
  fi
  for ((i=0; i<cnt; i++)); do
    [[ ${N_NAME[$i]} =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "Nome ASM inválido: ${N_NAME[$i]} (A-Z, 0-9, _, até 30, começa com letra)."
    grep -qixF -- "${N_NAME[$i]}" <<<"$nametaken" && die "Nome ASM ${N_NAME[$i]} já existe no $DG."
    nametaken+="${N_NAME[$i]}"$'\n'
  done

  if [[ $ACTION != add-only ]]; then
    N_ASMPATH=()
    for ((i=0; i<cnt; i++)); do
      case $METHOD in
        asmlib|afd|udev) N_ASMPATH+=("$(path_for_label "${N_LABEL[$i]}")") ;;
        raw)             N_ASMPATH+=("${N_USE[$i]}") ;;
      esac
    done
  fi
  for ((i=0; i<cnt; i++)); do
    [[ ${N_ASMPATH[$i]} =~ ^[A-Za-z0-9_/:.+-]+$ ]] || die "Caminho ASM inválido: ${N_ASMPATH[$i]}"
    diskstring_ok "${N_ASMPATH[$i]}" || die "O caminho ${N_ASMPATH[$i]} NÃO casa com asm_diskstring='$ASM_DISKSTRING'. O ASM não vai descobrir o disco."
    ok "Disco $((i+1)): label=${N_LABEL[$i]} nome=${N_NAME[$i]} caminho=${N_ASMPATH[$i]}"
  done
}

diskstring_ok() {
  local p=$1 g arr=()
  if [[ -z $ASM_DISKSTRING || $ASM_DISKSTRING == - ]]; then
    case $p in ORCL:*) return 0 ;; AFD:*) return 1 ;; esac
    warn "asm_diskstring vazio (descoberta padrão do SO). A descoberta de $p será validada antes do ALTER."
    return 0
  fi
  IFS=',' read -r -a arr <<<"$ASM_DISKSTRING"
  for g in "${arr[@]}"; do
    g=$(trim "$g"); g=${g#\'}; g=${g%\'}
    # shellcheck disable=SC2053
    [[ $p == $g ]] && return 0
  done
  return 1
}

#------------------------------------------------------------------------------
# Failgroup / site / power
#------------------------------------------------------------------------------
resolve_failgroups() {
  section "Failgroups / Sites / Rebalance"
  local cnt=${#N_IN[@]} i arr=() fg sarr=() rows
  for ((i=0; i<cnt; i++)); do N_FG+=(""); N_SITE+=(""); done

  if [[ -n $FAILGROUPS_IN ]]; then
    IFS=',' read -r -a arr <<<"$FAILGROUPS_IN"
    (( ${#arr[@]} == 1 || ${#arr[@]} == cnt )) || die "--failgroup: informe 1 failgroup ou $cnt (um por disco)."
    for ((i=0; i<cnt; i++)); do
      fg=$(upper "$(trim "${arr[$(( ${#arr[@]} == 1 ? 0 : i ))]}")")
      [[ $fg =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "Failgroup inválido: $fg"
      if [[ $DG_FGS != *" $fg "* ]]; then
        (( ALLOW_NEW_FG )) || die "Failgroup $fg não existe no $DG (existentes:$DG_FGS). Use --allow-new-failgroup se for intencional."
        warn "Failgroup NOVO será criado: $fg"
      fi
      N_FG[$i]=$fg
    done
    [[ $DG_TYPE == EXTERN ]] && warn "DG EXTERNAL: failgroup informado será aplicado, mas não tem efeito de redundância."
  elif [[ $DG_TYPE != EXTERN ]]; then
    if (( DG_DEFAULT_FG )); then
      info "DG $DG_TYPE com failgroup padrão (cada disco no seu próprio failgroup): sem cláusula FAILGROUP."
    else
      die "DG $DG_TYPE com failgroups NOMEADOS (${DG_FGS# }). Informe --failgroup (um para todos ou um por disco)."
    fi
  fi

  if (( DG_USES_SITE )); then
    [[ -n $SITES_IN ]] || die "Diskgroup usa SITE (Extended). Informe --site."
    IFS=',' read -r -a sarr <<<"$SITES_IN"
    (( ${#sarr[@]} == 1 || ${#sarr[@]} == cnt )) || die "--site: informe 1 site ou $cnt."
    for ((i=0; i<cnt; i++)); do
      N_SITE[$i]=$(upper "$(trim "${sarr[$(( ${#sarr[@]} == 1 ? 0 : i ))]}")")
      [[ ${N_SITE[$i]} =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "Site inválido: ${N_SITE[$i]}"
      [[ -n ${N_FG[$i]} ]] || die "Com SITE é obrigatório --failgroup."
    done
  elif [[ -n $SITES_IN ]]; then
    die "--site informado, mas o $DG não usa sites."
  fi

  if [[ $DG_TYPE != EXTERN && -n $FAILGROUPS_IN ]]; then
    rows=$(for ((i=0; i<${#DGD_FG[@]}; i++)); do [[ ${DGD_FGT[$i]} == QUORUM ]] || echo "${DGD_FG[$i]} ${DGD_TOTAL[$i]}"; done
           for ((i=0; i<cnt; i++)); do echo "${N_FG[$i]} ${N_MB[$i]}"; done)
    info "Capacidade por failgroup DEPOIS do ADD (MB):"
    awk '{t[$1]+=$2} END{for (f in t) printf "        %-30s %12d\n", f, t[f]}' <<<"$rows" | sort
    awk '{t[$1]+=$2} END{mn=-1; for (f in t){if(mn<0||t[f]<mn)mn=t[f]; if(t[f]>mx)mx=t[f]} exit !(mn>0 && mx/mn>1.10)}' <<<"$rows" \
      && warn "Failgroups ficarão DESBALANCEADOS (>10% de diferença). Em NORMAL/HIGH isso reduz o espaço utilizável."
  fi
}

resolve_power() {
  local compat_ok=0 maxp minp
  version_ge "$DG_COMPAT_ASM" "11.2.0.2" && compat_ok=1
  if (( compat_ok )); then minp=0; maxp=1024; else minp=1; maxp=11; fi
  if (( NO_REBAL )); then
    (( compat_ok )) || die "--no-rebalance (POWER 0) exige COMPATIBLE.ASM >= 11.2.0.2 (atual $DG_COMPAT_ASM)."
    POWER_EFF=0; POWER_CLAUSE="REBALANCE POWER 0 NOWAIT"
    warn "REBALANCE POWER 0: os dados NÃO serão redistribuídos até você rodar --set-power."
  elif [[ -n $POWER ]]; then
    (( POWER >= minp && POWER <= maxp )) || die "--power $POWER fora do intervalo $minp-$maxp (COMPATIBLE.ASM=$DG_COMPAT_ASM)."
    POWER_EFF=$POWER; POWER_CLAUSE="REBALANCE POWER $POWER NOWAIT"
  else
    POWER_EFF="$ASM_POWER_LIMIT (asm_power_limit)"; POWER_CLAUSE="REBALANCE NOWAIT"
  fi
  if is_uint "$POWER" && (( POWER > 16 )); then warn "Power $POWER é alto: mais I/O no storage durante o rebalance."; fi
  info "Rebalance: power=$POWER_EFF | acompanhar=$([[ $MON_WAIT == 1 ]] && echo sim || echo não)"
}

decide_partition() {
  local i
  for ((i=0; i<${#N_IN[@]}; i++)); do N_NEEDPART+=(0); done
  [[ $OS == Linux && $ACTION != add-only ]] || { PART_EFF="no"; return 0; }
  if [[ $PART_MODE == auto ]]; then
    PART_EFF=${DG_PART_STYLE:-yes}
  else
    PART_EFF=$PART_MODE
  fi
  if [[ $PTTYPE == auto ]]; then PTTYPE_EFF=${DG_PTTYPE:-gpt}; else PTTYPE_EFF=$PTTYPE; fi
  [[ $PTTYPE_EFF == gpt || $PTTYPE_EFF == msdos ]] || PTTYPE_EFF="gpt"
  for ((i=0; i<${#N_IN[@]}; i++)); do
    if (( N_ISPART[i] )); then N_NEEDPART[$i]=0
    elif [[ $PART_EFF == yes ]]; then
      N_NEEDPART[$i]=1
      if [[ $PTTYPE_EFF == msdos ]] && (( N_MB[i] > 2097151 )); then
        warn "${N_IN[$i]} > 2TiB: msdos não suporta, usando gpt."; PTTYPE_EFF="gpt"
      fi
    else
      N_NEEDPART[$i]=0; N_PART[$i]=${N_USE[$i]}
    fi
  done
  [[ $METHOD == udev && $UDEV_PART_RULE == 1 && $PART_EFF == no ]] && die "O template udev é de PARTIÇÃO, mas foi escolhido disco inteiro. Remova --no-partition."
  [[ $METHOD == udev && $UDEV_PART_RULE == 0 && $PART_EFF == yes ]] && die "O template udev é de DISCO inteiro, mas foi escolhida partição. Use --no-partition."
  info "Particionamento: $PART_EFF (tabela $PTTYPE_EFF, início 1MiB)"

  # pré-visualização do identificador udev
  if [[ $METHOD == udev ]]; then
    for ((i=0; i<${#N_IN[@]}; i++)); do
      if (( UDEV_PART_RULE == 0 )); then
        N_UDEVPREV[$i]=$(udev_value "${N_REAL[$i]}")
        [[ -n ${N_UDEVPREV[$i]} ]] || die "Não consegui calcular $UDEV_KEY para ${N_IN[$i]}."
        grep -rqF -- "\"${N_UDEVPREV[$i]}\"" /etc/udev/rules.d/ 2>/dev/null && die "Já existe regra udev com o identificador de ${N_IN[$i]} (${N_UDEVPREV[$i]})."
        # shellcheck disable=SC2053
        [[ -z $UDEV_KGLOB || ${N_KNAME[$i]} == $UDEV_KGLOB ]] || die "${N_KNAME[$i]} não casa com KERNEL==\"$UDEV_KGLOB\" do template udev."
      fi
    done
  fi
}

#------------------------------------------------------------------------------
# Disco já provisionado (--add-only)
#------------------------------------------------------------------------------
check_addonly_disks() {
  section "Discos já provisionados (--add-only)"
  local in p i rows inst path hdr grp osmb seen hosts
  for in in "${DISKS_IN[@]}"; do
    if [[ $in != */* && $in != *:* ]]; then
      case $METHOD in
        asmlib|afd|udev) p=$(path_for_label "$([[ $METHOD == udev ]] && echo "$in" || upper "$in")") ;;
        *) die "Para '$in' informe o caminho completo (método do DG: $METHOD)." ;;
      esac
    else
      p=$in
    fi
    [[ $p =~ ^[A-Za-z0-9_/:.+-]+$ ]] || die "Caminho inválido: $p"
    N_IN+=("$in"); N_ASMPATH+=("$p"); N_LABEL+=("$(label_of_path "$p")")
    N_MB+=(0)
  done
  SQL_LIST=$(printf "'%s'," "${N_ASMPATH[@]}"); SQL_LIST=${SQL_LIST%,}
  rows=$(sqlt <<'SQL'
select inst_id||'|'||path||'|'||header_status||'|'||group_number||'|'||nvl(os_mb,0) from gv$asm_disk where path in (__LIST__) order by path, inst_id;
SQL
) || die "Falha consultando gv\$asm_disk."
  for ((i=0; i<${#N_ASMPATH[@]}; i++)); do
    seen=0
    while IFS='|' read -r inst path hdr grp osmb; do
      [[ $path == "${N_ASMPATH[$i]}" ]] || continue
      seen=$((seen+1))
      [[ $grp == 0 ]] || die "${N_ASMPATH[$i]} já pertence a um diskgroup (grupo $grp, instância $inst)."
      case $hdr in CANDIDATE|PROVISIONED|FORMER) ;; *) die "${N_ASMPATH[$i]} com header_status=$hdr na instância $inst (esperado CANDIDATE/PROVISIONED/FORMER)." ;; esac
      [[ $hdr == FORMER ]] && warn "${N_ASMPATH[$i]} é FORMER (já pertenceu a um DG). Confirme que ele é realmente livre."
      N_MB[$i]=$osmb
    done <<<"$rows"
    (( seen == INST_COUNT )) || die "${N_ASMPATH[$i]} visto por $seen de $INST_COUNT instâncias ASM. Faça o scan nos nós (oracleasm scandisks / afd_scan / udev / permissão)."
    ok "${N_ASMPATH[$i]}: visível em $seen/$INST_COUNT instâncias, ${N_MB[$i]}MB"
  done
  for ((i=0; i<${#N_IN[@]}; i++)); do N_SS+=(0); done
  check_sizes
}

#------------------------------------------------------------------------------
# ALTER DISKGROUP
#------------------------------------------------------------------------------
build_alter() {
  local s i j key keys=() k first lines
  s="ALTER DISKGROUP $DG ADD"
  for ((i=0; i<${#N_NAME[@]}; i++)); do
    key="${N_SITE[$i]:-}|${N_FG[$i]:-}"
    [[ " ${keys[*]:-} " == *" $key "* ]] || keys+=("$key")
  done
  for k in "${keys[@]}"; do
    s+=$'\n '
    [[ -n ${k%%|*} ]] && s+=" SITE ${k%%|*}"
    [[ -n ${k#*|} ]] && s+=" FAILGROUP ${k#*|}"
    s+=" DISK"
    first=1; lines=""
    for ((j=0; j<${#N_NAME[@]}; j++)); do
      [[ "${N_SITE[$j]:-}|${N_FG[$j]:-}" == "$k" ]] || continue
      (( first )) || lines+=","
      lines+=$'\n'"    '${N_ASMPATH[$j]}' NAME ${N_NAME[$j]}"
      first=0
    done
    s+=$lines
  done
  s+=$'\n'"  $POWER_CLAUSE;"
  printf '%s\n' "$s"
}

#------------------------------------------------------------------------------
# Plano
#------------------------------------------------------------------------------
print_plan() {
  section "PLANO DE EXECUÇÃO"
  local i add=0
  printf '  Host/Nó    : %s (%s) | SO=%s | modo=%s\n' "$(hostname)" "$LOCAL_NODE" "$OS" "$([[ $EXECUTE == 1 ]] && echo EXECUTE || echo DRY-RUN)"
  printf '  Cluster    : %s | remoto=%s\n' "$([[ $IS_RAC == 1 ]] && echo "RAC (${NODES[*]})" || echo standalone)" "$REMOTE_MODE"
  printf '  Diskgroup  : %s (%s) AU=%sMB setor=%s compatible.asm=%s\n' "$DG" "$DG_TYPE" "$DG_AU" "$DG_SECTOR" "$DG_COMPAT_ASM"
  if [[ $METHOD == exadata ]]; then
    printf '  Método     : exadata | cells=%s | prefixo=%s | tipo=%s | criar griddisk=%s | ação=%s\n\n' \
      "${EXA_CNAMES[*]}" "$EXA_PREFIX" "$EXA_DISKTYPE" "$([[ $EXA_CREATE == 1 ]] && echo "sim (size=$EXA_SIZE_STR)" || echo não)" "$ACTION"
  else
    printf '  Método     : %s | partição=%s (%s) | ação=%s\n\n' "$METHOD" "$PART_EFF" "$PTTYPE_EFF" "$ACTION"
  fi
  if [[ $METHOD == exadata ]]; then
    printf '  %-2s %-24s %-18s %10s %-14s %-24s %-20s\n' "#" "CELL (host)" "CELL (nome)" "MB" "-" "NOME ASM (griddisk)" "FAILGROUP"
  else
    printf '  %-2s %-24s %-18s %10s %-14s %-24s %-20s\n' "#" "DISCO" "DEVICE REAL" "MB" "LABEL" "NOME ASM" "FAILGROUP"
  fi
  printf '  %s\n' "--------------------------------------------------------------------------------------------------------------------"
  for ((i=0; i<${#N_IN[@]}; i++)); do
    printf '  %-2s %-24s %-18s %10s %-14s %-24s %-20s\n' "$((i+1))" "${N_IN[$i]}" "${N_REAL[$i]:--}" "${N_MB[$i]}" \
      "${N_LABEL[$i]}" "${N_NAME[$i]}" "${N_FG[$i]:-$([[ $METHOD == exadata ]] && echo "$(upper "${N_REAL[$i]}") (auto)" || echo '(padrão)')}"
    printf '     caminho ASM: %s\n' "${N_ASMPATH[$i]}"
    [[ -n ${N_BYID[$i]:-} ]] && printf '     by-id      : %s\n' "${N_BYID[$i]%% *}"
    [[ -n ${N_ID[$i]:-} ]] && printf '     id         : %s\n' "${N_ID[$i]}"
    [[ -n ${N_RDEV[$i]:-} ]] && printf '     outros nós : %s\n' "${N_RDEV[$i]}"
    add=$((add + N_MB[i]))
  done
  printf '\n  Capacidade : total %sMB -> ~%sMB (+%sMB brutos) | livre %sMB -> ~%sMB\n' \
    "$DG_TOTAL" "$((DG_TOTAL+add))" "$add" "$DG_FREE" "$((DG_FREE+add))"
  [[ $DG_TYPE == NORMAL ]] && printf '               (NORMAL: espaço utilizável ganho ~ %sMB)\n' "$((add/2))"
  [[ $DG_TYPE == HIGH ]]   && printf '               (HIGH: espaço utilizável ganho ~ %sMB)\n' "$((add/3))"
  if [[ $ACTION != provision-only ]]; then
    printf '\n  Statement que será executado:\n'
    build_alter | sed 's/^/    /'
  fi
  (( WARN_COUNT > 0 )) && printf '\n  %sAtenção: %s aviso(s) acima. Leia antes de prosseguir.%s\n' "$C_Y" "$WARN_COUNT" "$C_0"
  return 0
}

#------------------------------------------------------------------------------
# Snapshot
#------------------------------------------------------------------------------
snapshot() {
  local f="$LOG_DIR/asm_add_disk_brabo_${DG}_${RUN_TS}_snap_$1.txt"
  {
    echo "### $(ts) host=$(hostname) fase=$1 script=$SCRIPT_VERSION"
    case $OS in
      Linux) lsblk -o NAME,KNAME,TYPE,SIZE,MAJ:MIN,OWNER,GROUP,MODE,MOUNTPOINT 2>/dev/null ;;
      AIX)   lspv 2>/dev/null; lsdev -Cc disk 2>/dev/null ;;
    esac
    [[ $METHOD == asmlib && -n $ORACLEASM_BIN ]] && { echo "### oracleasm listdisks"; "$ORACLEASM_BIN" listdisks 2>&1; }
    [[ $METHOD == afd ]] && { echo "### afd_lslbl"; as_grid "'$GRID_HOME/bin/asmcmd' afd_lslbl" 2>&1; }
    [[ $METHOD == udev && -n $UDEV_FILE ]] && { echo "### $UDEV_FILE"; cat "$UDEV_FILE"; }
    if [[ $METHOD == exadata ]]; then
      local h
      for h in ${EXA_HOSTS[@]+"${EXA_HOSTS[@]}"}; do
        echo "### cell $h: list griddisk"
        exa_cell "$h" "list griddisk attributes name,size,status,asmmodestatus,diskType,asmDiskGroupName" 2>&1
      done
    fi
    echo "### v\$asm_disk"
    sqlt <<'SQL'
select group_number||'|'||nvl(name,'-')||'|'||path||'|'||header_status||'|'||mode_status||'|'||state||'|'||nvl(failgroup,'-')||'|'||os_mb||'|'||total_mb from v$asm_disk order by group_number, path;
SQL
    echo "### v\$asm_diskgroup"
    sql_query "select name||'|'||state||'|'||type||'|'||total_mb||'|'||free_mb||'|'||usable_file_mb from v\$asm_diskgroup order by name;"
  } > "$f" 2>&1
  info "Snapshot ($1): $f"
}

#------------------------------------------------------------------------------
# Provisionamento
#------------------------------------------------------------------------------
predict_part() { local d=$1; [[ $d =~ [0-9]$ ]] && echo "${d}p1" || echo "${d}1"; }

wait_partition() {
  local dev=$1 t p c
  for ((t=0; t<30; t++)); do
    udevadm settle >/dev/null 2>&1
    p=$(lsblk -nlo KNAME,TYPE "$dev" 2>/dev/null | awk 'NR>1 && $2=="part"{print $1; exit}')
    if [[ -n $p ]]; then
      if [[ $p == dm-* ]]; then echo "/dev/mapper/$(cat "/sys/class/block/$p/dm/name")"; else echo "/dev/$p"; fi
      return 0
    fi
    if [[ $dev == /dev/mapper/* ]]; then
      for c in "${dev}p1" "${dev}1" "${dev}-part1"; do [[ -b $c ]] && { echo "$c"; return 0; }; done
    fi
    sleep 1
  done
  return 1
}

prov_linux() {
  local i=$1
  local dev=${N_USE[$i]} part n rdev k start tgt
  if (( N_NEEDPART[i] )); then
    # trava final: o disco continua sem nada imediatamente antes de particionar
    if (( EXECUTE )); then
      [[ -z $(lsblk -nlo KNAME "${N_REAL[$i]}" 2>/dev/null | sed 1d) ]] || { err "$dev ganhou partição/dependente desde a validação. Abortando."; return 1; }
      [[ -z $(blkid -p -o export "${N_REAL[$i]}" 2>/dev/null | grep -E '^(TYPE|PTTYPE)=') ]] || { err "$dev ganhou assinatura desde a validação. Abortando."; return 1; }
    fi
    run_mod parted -s -a optimal "$dev" mklabel "$PTTYPE_EFF" mkpart primary 1MiB 100% || return 1
    (( EXECUTE )) && UNDO+=("[$LOCAL_NODE] parted -s $dev rm 1 && wipefs -a $dev    # ${N_IN[$i]} — SOMENTE se NÃO estiver no ASM")
    if [[ ${N_TYPE[$i]} == mpath ]]; then run_mod kpartx -a "$dev" || return 1
    else run_mod partprobe "$dev" || run_mod partx -u "$dev" || return 1; fi
    run_mod udevadm settle
    if (( EXECUTE )); then
      part=$(wait_partition "$dev") || { err "A partição de $dev não apareceu em 30s."; return 1; }
      k=$(basename "$(readlink -f "$part")")
      start=$(cat "/sys/class/block/$k/start" 2>/dev/null)
      [[ -z $start || $start == 2048 ]] || warn "$part começa no setor $start (esperado 2048 = 1MiB)."
      ok "Partição criada: $part"
    else
      part="$(predict_part "$dev") (previsto)"
    fi
    N_PART[$i]=$part
    for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
      rdev=$(rdev_of "$i" "$n") || rdev="<device de ${N_IN[$i]} em $n>"
      if [[ ${N_TYPE[$i]} == mpath ]]; then r_mod "$n" "kpartx -a $rdev && udevadm settle" || return 1
      else r_mod "$n" "partprobe $rdev && udevadm settle" || return 1; fi
    done
  else
    [[ -n ${N_PART[$i]} ]] || N_PART[$i]=$dev
  fi

  tgt=${N_PART[$i]%% *}
  case $METHOD in
    asmlib)
      run_mod "$ORACLEASM_BIN" createdisk "${N_LABEL[$i]}" "$tgt" || return 1
      (( EXECUTE )) && UNDO+=("[$LOCAL_NODE] $ORACLEASM_BIN deletedisk ${N_LABEL[$i]}    # SOMENTE se NÃO estiver no ASM")
      if (( EXECUTE )); then
        "$ORACLEASM_BIN" querydisk -p "${N_LABEL[$i]}" || { err "querydisk não confirmou ${N_LABEL[$i]}."; return 1; }
      fi
      run_mod "$ORACLEASM_BIN" scandisks || return 1
      for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
        r_mod "$n" "$ORACLEASM_BIN scandisks && $ORACLEASM_BIN querydisk -p ${N_LABEL[$i]}" || return 1
      done ;;
    afd)
      run_mod grid_env_root "$GRID_HOME/bin/asmcmd" afd_label "${N_LABEL[$i]}" "$tgt" || return 1
      (( EXECUTE )) && UNDO+=("[$LOCAL_NODE] ORACLE_HOME=$GRID_HOME $GRID_HOME/bin/asmcmd afd_unlabel ${N_LABEL[$i]}    # SOMENTE se NÃO estiver no ASM")
      if (( EXECUTE )); then
        grid_env_root "$GRID_HOME/bin/asmcmd" afd_lslbl "$tgt" 2>&1 | grep -qw "${N_LABEL[$i]}" || { err "afd_lslbl não confirmou ${N_LABEL[$i]}."; return 1; }
      fi
      for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
        r_mod "$n" "ORACLE_HOME=$GRID_HOME ORACLE_BASE=$ORA_BASE $GRID_HOME/bin/asmcmd afd_scan && ORACLE_HOME=$GRID_HOME $GRID_HOME/bin/asmcmd afd_lslbl | grep -w ${N_LABEL[$i]}" || return 1
      done ;;
    udev)
      udev_apply "$i" "$tgt" || return 1 ;;
  esac
  return 0
}

udev_apply() {
  local i=$1 tgt=$2 newval line k n rt cmd t mmn mmt own
  if (( EXECUTE )); then
    newval=$(udev_value "$(readlink -f "$tgt")")
    [[ -n $newval && $newval != *'"'* ]] || { err "Não consegui calcular $UDEV_KEY para $tgt."; return 1; }
    grep -rqF -- "\"$newval\"" /etc/udev/rules.d/ 2>/dev/null && { err "Já existe regra udev com '$newval'."; return 1; }
    k=$(basename "$(readlink -f "$tgt")")
    # shellcheck disable=SC2053
    [[ -z $UDEV_KGLOB || $k == $UDEV_KGLOB ]] || { err "$k não casa com KERNEL==\"$UDEV_KGLOB\" do template."; return 1; }
  else
    newval=${N_UDEVPREV[$i]:-"<$UDEV_KEY de $tgt>"}; k=${tgt##*/}
  fi
  line=$(udev_build_line "$newval" "${N_LABEL[$i]}") || return 1
  if (( EXECUTE )); then
    if [[ ! -e "$UDEV_FILE.bak_asmbrabo_$RUN_TS" ]]; then
      cp -p "$UDEV_FILE" "$UDEV_FILE.bak_asmbrabo_$RUN_TS" || return 1
      UNDO+=("[$LOCAL_NODE] cp -p $UDEV_FILE.bak_asmbrabo_$RUN_TS $UDEV_FILE && udevadm control --reload-rules")
    fi
    info "EXEC: append em $UDEV_FILE: $line"
    printf '# asm_add_disk_brabo %s %s -> %s\n%s\n' "$RUN_TS" "${N_IN[$i]}" "${N_LABEL[$i]}" "$line" >> "$UDEV_FILE" || return 1
  else
    dry "append em $UDEV_FILE (backup antes): $line"
  fi
  run_mod udevadm control --reload-rules || return 1
  run_mod udevadm trigger --action=change --sysname-match="$k" || return 1
  run_mod udevadm settle
  if (( EXECUTE )); then
    for ((t=0; t<15; t++)); do [[ -e ${N_ASMPATH[$i]} ]] && break; sleep 1; done
    [[ -e ${N_ASMPATH[$i]} ]] || { err "${N_ASMPATH[$i]} não apareceu após o udev."; return 1; }
    mmn=$(majmin "${N_ASMPATH[$i]}"); mmt=$(majmin "$tgt")
    [[ $mmn == "$mmt" ]] || { err "${N_ASMPATH[$i]} ($mmn) NÃO aponta para $tgt ($mmt)!"; return 1; }
    own=$(ls -lL "${N_ASMPATH[$i]}")
    [[ $(awk '{print $3":"$4}' <<<"$own") == "$OWNER_EFF:$GROUP_EFF" && $(perm_octal <<<"$own") == "$PERM_EFF" ]] \
      || { err "Permissão de ${N_ASMPATH[$i]} difere da referência ($OWNER_EFF:$GROUP_EFF $PERM_EFF): $own"; return 1; }
    ok "${N_ASMPATH[$i]} -> $tgt ($OWNER_EFF:$GROUP_EFF $PERM_EFF)"
  fi
  for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
    rt=$(rdev_of "$i" "$n") || rt="<device de ${N_IN[$i]} em $n>"
    if (( UDEV_PART_RULE )); then rt="\$(lsblk -nlpo NAME,TYPE $rt | awk '\$2==\"part\"{print \$1; exit}')"; fi
    cmd="[ -e '$UDEV_FILE.bak_asmbrabo_$RUN_TS' ] || cp -p '$UDEV_FILE' '$UDEV_FILE.bak_asmbrabo_$RUN_TS'; "
    cmd+="printf '%s\n' $(printf '%q' "$line") >> '$UDEV_FILE' && udevadm control --reload-rules && "
    cmd+="udevadm trigger --action=change --sysname-match=\$(basename \$(readlink -f $rt)) && udevadm settle && sleep 2 && ls -lL '${N_ASMPATH[$i]}'"
    r_mod "$n" "$cmd" || return 1
    (( EXECUTE )) && UNDO+=("[$n] cp -p $UDEV_FILE.bak_asmbrabo_$RUN_TS $UDEV_FILE && udevadm control --reload-rules")
  done
  return 0
}

prov_aix() {
  local i=$1
  local h=${N_KNAME[$i]} raw=${N_USE[$i]} n rh orig
  if (( N_AIXFIX[i] )); then run_mod chdev -l "$h" -a reserve_policy=no_reserve || return 1; fi
  for n in ${N_RFIX[$i]:-}; do
    rh=$(rdev_of "$i" "$n") || return 1
    r_mod "$n" "chdev -l $rh -a reserve_policy=no_reserve" || return 1
  done
  orig=$(ls -l "$raw" 2>/dev/null | awk '{print $3":"$4}')
  run_mod chown "$OWNER_EFF:$GROUP_EFF" "$raw" || return 1
  (( EXECUTE )) && UNDO+=("[$LOCAL_NODE] chown $orig $raw; chmod 600 $raw    # SOMENTE se NÃO estiver no ASM")
  run_mod chmod "$PERM_EFF" "$raw" || return 1
  for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
    rh=$(rdev_of "$i" "$n") || rh=$h
    r_mod "$n" "chown $OWNER_EFF:$GROUP_EFF /dev/r$rh && chmod $PERM_EFF /dev/r$rh && ls -l /dev/r$rh" || return 1
  done
  return 0
}

execute_provision() {
  local i
  for ((i=0; i<${#N_IN[@]}; i++)); do
    section "Provisionando $((i+1))/${#N_IN[@]}: ${N_IN[$i]} -> ${N_LABEL[$i]}"
    case $OS in
      Linux) prov_linux "$i" || die "Falha provisionando ${N_IN[$i]}." 3 ;;
      AIX)   prov_aix "$i"   || die "Falha provisionando ${N_IN[$i]}." 3 ;;
    esac
  done
  flush_manual
}

expected_path() {  # $1=índice $2=host da instância
  local h s
  h=$(upper "${2%%.*}")
  if [[ $OS == AIX && $METHOD == raw && $h != "$(upper "${LOCAL_NODE%%.*}")" ]]; then
    for s in ${N_RDEV[$1]:-}; do
      [[ $(upper "${s%%=*}") == "$h" ]] && { echo "/dev/r${s#*=}"; return 0; }
    done
  fi
  echo "${N_ASMPATH[$1]}"
}

verify_discovery() {
  section "Descoberta pelo ASM em TODAS as instâncias"
  if (( ! EXECUTE )); then dry "gv\$asm_disk: cada disco precisa aparecer em $INST_COUNT instância(s) como CANDIDATE/PROVISIONED/FORMER"; return 0; fi
  local insts rows att i id host exp line allok report paths="" hdr grp
  insts=$(sql_query "select inst_id||'|'||host_name from gv\$instance order by 1;") || return 1
  for ((i=0; i<${#N_ASMPATH[@]}; i++)); do
    while IFS='|' read -r id host; do [[ -n $id ]] && paths+="'$(expected_path "$i" "$host")',"; done <<<"$insts"
  done
  SQL_LIST=${paths%,}
  for ((att=1; att<=12; att++)); do
    rows=$(sqlt <<'SQL'
select inst_id||'|'||path||'|'||header_status||'|'||group_number||'|'||nvl(os_mb,0) from gv$asm_disk where path in (__LIST__);
SQL
) || return 1
    allok=1; report=""
    for ((i=0; i<${#N_ASMPATH[@]}; i++)); do
      while IFS='|' read -r id host; do
        [[ -n $id ]] || continue
        exp=$(expected_path "$i" "$host")
        line=$(awk -F'|' -v a="$id" -v b="$exp" '$1==a && $2==b' <<<"$rows")
        if [[ -z $line ]]; then allok=0; report+="inst $id ($host): $exp NÃO descoberto; "; continue; fi
        IFS='|' read -r _ _ hdr grp _ <<<"$line"
        [[ $grp == 0 ]] || { err "$exp aparece no grupo $grp na instância $id!"; return 1; }
        case $hdr in
          CANDIDATE|PROVISIONED|FORMER) ;;
          MEMBER) err "$exp está como MEMBER na instância $id!"; return 1 ;;
          *) allok=0; report+="inst $id: $exp header=$hdr; " ;;
        esac
      done <<<"$insts"
    done
    if (( allok )); then ok "Todos os discos descobertos em $INST_COUNT instância(s)."; return 0; fi
    info "Aguardando descoberta ($att/12): $report"
    sleep 10
  done
  err "Descoberta incompleta: $report"
  err "Verifique asm_diskstring ('$ASM_DISKSTRING'), permissões e o scan em cada nó. O ALTER NÃO foi executado."
  return 1
}

do_alter() {
  section "ALTER DISKGROUP $DG"
  local stmt ops
  stmt=$(build_alter)
  printf '%s\n' "$stmt" | sed 's/^/    /'
  if (( ! EXECUTE )); then dry "(statement acima)"; return 0; fi
  ops=$(load_ops) || die "Falha consultando gv\$asm_operation." 3
  if [[ -n $ops ]] && (( ! ALLOW_RUNNING_OP )); then
    die "Surgiu uma operação no $DG durante a execução. Discos provisionados mas NÃO adicionados. Rode --add-only quando terminar." 3
  fi
  PHASE="alter"
  if ! sql_query "$stmt" >/dev/null; then
    PHASE="execute"
    die "ALTER DISKGROUP falhou. Os discos ficaram provisionados, mas NÃO foram adicionados. Corrija e use --add-only, ou reverta." 3
  fi
  PHASE="added"
  UNDO=()
  ok "ALTER DISKGROUP $DG ADD executado."
}

post_verify() {
  section "Verificação pós-ADD"
  local rows i nm path hdr mode st fg tmb fail=0
  SQL_LIST=$(printf "'%s'," "${N_NAME[@]}"); SQL_LIST=${SQL_LIST%,}
  rows=$(sqlt <<'SQL'
select name||'|'||path||'|'||header_status||'|'||mode_status||'|'||state||'|'||failgroup||'|'||total_mb from v$asm_disk where group_number = __DGNUM__ and name in (__LIST__) order by name;
SQL
) || { warn "Falha na verificação pós-ADD — confira com --status."; return 0; }
  for ((i=0; i<${#N_NAME[@]}; i++)); do
    if ! grep -q "^${N_NAME[$i]}|" <<<"$rows"; then err "${N_NAME[$i]} não aparece no $DG!"; fail=1; continue; fi
    IFS='|' read -r nm path hdr mode st fg tmb <<<"$(grep "^${N_NAME[$i]}|" <<<"$rows")"
    if [[ $hdr == MEMBER && $mode == ONLINE && ( $st == NORMAL || $st == ADDING ) ]]; then
      ok "$nm $path $hdr/$mode/$st fg=$fg ${tmb}MB"
    else
      err "$nm $path header=$hdr mode=$mode state=$st"; fail=1
    fi
  done
  (( fail == 0 )) || warn "Há discos em estado inesperado. Confira com --status."
}

monitor_rebal() {
  section "Rebalance do $DG (Ctrl+C sai do monitor; o rebalance NÃO é afetado)"
  local start rows inst op st pw sofar work rate em ec pass
  PHASE="monitor"; start=$(epoch)
  while :; do
    rows=$(load_ops) || { warn "Falha consultando gv\$asm_operation."; return 1; }
    if [[ -z $rows ]]; then ok "Nenhuma operação em andamento no $DG — rebalance concluído."; break; fi
    while IFS='|' read -r inst op st pw sofar work rate em ec pass; do
      [[ -n $inst ]] || continue
      printf '  %s inst=%s %s/%s pass=%s power=%s %s/%s AU (%s AU/min) est=%s min\n' \
        "$(ts)" "$inst" "$op" "$st" "$pass" "$pw" "$sofar" "$work" "$rate" "$em"
      [[ $ec != - && -n $ec ]] && err "Rebalance com erro na instância $inst: $ec (veja o alert log do ASM)."
    done <<<"$rows"
    if (( WAIT_TIMEOUT > 0 && $(epoch) - start >= WAIT_TIMEOUT*60 )); then
      warn "Tempo de acompanhamento esgotado (${WAIT_TIMEOUT} min). O rebalance continua no ASM."; break
    fi
    sleep "$POLL"
  done
  PHASE="done"
}

#------------------------------------------------------------------------------
# Ações auxiliares
#------------------------------------------------------------------------------
show_status() {
  section "Status do diskgroup $DG"
  sql_pretty "$(cat <<SQL
col name format a20
col type format a7
col state format a10
col compat format a12
select name, state, type, total_mb, free_mb, usable_file_mb, required_mirror_free_mb, allocation_unit_size/1048576 au_mb, sector_size
from v\$asm_diskgroup where name = '$DG';
prompt
prompt ==== Failgroups ====
col failgroup format a30
select failgroup, failgroup_type, count(*) discos, sum(total_mb) total_mb, sum(free_mb) free_mb
from v\$asm_disk where group_number = $DG_NUM group by failgroup, failgroup_type order by 1;
prompt
prompt ==== Discos (gv\$asm_disk) do $DG e candidatos (grupo 0) ====
TTITLE 'ASM Disks - General Information (From GV\$ASM_DISK)'
COL inst_id        FORMAT 99       HEADING 'Inst'
COL group_number   FORMAT 99999    HEADING 'ASM|Disk|Grp #'
COL disk_number    FORMAT 99999    HEADING 'ASM|Disk|#'
COL name           FORMAT A32      HEADING 'ASM Disk Name' WRAP
COL total_mb       FORMAT 99999999 HEADING 'Total|Disk|Space(MB)'
COL mount_status   FORMAT A07      HEADING 'Mount|Status'
COL header_status  FORMAT A12      HEADING 'Header|Status'
COL mode_status    FORMAT A08      HEADING 'Mode|Status'
COL state          FORMAT A08      HEADING 'Disk|State'
COL failgroup      FORMAT A20      HEADING 'Failgroup'
COL path           FORMAT A40      HEADING 'OS Disk Path Name' WRAP
SELECT inst_id, group_number, disk_number, name, total_mb, mount_status, header_status, mode_status, state, failgroup, path
FROM gv\$asm_disk WHERE group_number IN ($DG_NUM, 0) ORDER BY group_number, name, inst_id;
TTITLE OFF
prompt
prompt ==== Operações (gv\$asm_operation) ====
select inst_id, operation, state, power, sofar, est_work, est_rate, est_minutes, error_code
from gv\$asm_operation where group_number = $DG_NUM;
SQL
)"
}

do_scan() {
  section "Scan de discos do SO (somente leitura)"
  local k t in
  printf '  %-26s %-6s %10s  %s\n' "DEVICE" "TIPO" "MB" "SITUAÇÃO"
  printf '  %s\n' "-----------------------------------------------------------------------------------------"
  case $OS in
    Linux)
      while read -r k t; do
        [[ $t == disk || $t == mpath ]] || continue
        in="/dev/$k"; [[ $t == mpath ]] && in="/dev/mapper/$(cat "/sys/class/block/$k/dm/name" 2>/dev/null)"
        linux_dev_check "$in"
        if [[ -n $CK_FAIL ]]; then printf '  %-26s %-6s %10s  EM USO/INAPTO: %s\n' "$in" "$t" "${CK_MB:-?}" "$CK_FAIL"
        else printf '  %-26s %-6s %10s  %sLIVRE%s %s\n' "$in" "$t" "$CK_MB" "$C_G" "$C_0" "${CK_BYID%% *}"; fi
      done < <(lsblk -nlo KNAME,TYPE 2>/dev/null | awk '$2=="disk"||$2=="mpath"' | sort -u) ;;
    AIX)
      for k in $(lsdev -Cc disk -F name 2>/dev/null); do
        aix_dev_check "$k"
        if [[ -n $CK_FAIL ]]; then printf '  %-26s %-6s %10s  EM USO/INAPTO: %s\n' "$k" disk "${CK_MB:-?}" "$CK_FAIL"
        else printf '  %-26s %-6s %10s  %sLIVRE%s uid=%s\n' "$k" disk "$CK_MB" "$C_G" "$C_0" "${CK_ID:0:40}"; fi
      done ;;
    *) die "--scan suportado em Linux e AIX." ;;
  esac
  if [[ -n $GRID_HOME ]]; then
    section "Discos que o ASM enxerga fora de diskgroup (grupo 0)"
    sql_query "select path||' | '||header_status||' | '||nvl(os_mb,0)||' MB' from v\$asm_disk where group_number = 0 order by path;" | sed 's/^/  /'
  fi
}

do_rescan() {
  require_root
  section "Rescan de barramento"
  local h n
  case $OS in
    Linux)
      for h in /sys/class/scsi_host/host*/scan; do
        [[ -w $h ]] && run_mod sh -c "echo '- - -' > $h"
      done
      run_mod udevadm settle
      for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do
        r_mod "$n" "for h in /sys/class/scsi_host/host*/scan; do echo '- - -' > \$h; done; udevadm settle"
      done ;;
    AIX)
      run_mod cfgmgr
      for n in ${REMOTE_NODES[@]+"${REMOTE_NODES[@]}"}; do r_mod "$n" "cfgmgr"; done ;;
    *) die "--rescan suportado em Linux e AIX." ;;
  esac
  flush_manual
  do_scan
}

do_set_power() {
  local compat_ok=0 maxp minp ops stmt
  version_ge "$DG_COMPAT_ASM" "11.2.0.2" && compat_ok=1
  if (( compat_ok )); then minp=0; maxp=1024; else minp=1; maxp=11; fi
  (( SET_POWER >= minp && SET_POWER <= maxp )) || die "Power $SET_POWER fora do intervalo $minp-$maxp (COMPATIBLE.ASM=$DG_COMPAT_ASM)."
  ops=$(load_ops) || die "Falha consultando gv\$asm_operation."
  section "Rebalance power do $DG"
  if [[ -z $ops ]]; then warn "Não há rebalance em andamento: este comando vai INICIAR um rebalance no $DG."
  else info "Operação atual:"; printf '%s\n' "$ops" | sed 's/^/        /'; fi
  (( SET_POWER == 0 )) && warn "POWER 0 PARA o rebalance em andamento."
  stmt="ALTER DISKGROUP $DG REBALANCE POWER $SET_POWER NOWAIT;"
  printf '    %s\n' "$stmt"
  if (( ! EXECUTE )); then dry "(statement acima — use --execute)"; return 0; fi
  confirm_typed "$DG" "Digite o nome do diskgroup ($DG) para confirmar: "
  sql_query "$stmt" >/dev/null || die "Falha ao alterar o power." 3
  ok "Power alterado para $SET_POWER."
  sleep 3; ops=$(load_ops); [[ -n $ops ]] && printf '%s\n' "$ops" | sed 's/^/        /'
}

#------------------------------------------------------------------------------
# EXADATA (on-premises)
#------------------------------------------------------------------------------
exa_cell() {  # $1=host da cell  $2=comando cellcli (sem aspas duplas)
  local out rc
  [[ $2 != *'"'* ]] || { err "comando cellcli inválido (aspas duplas)"; return 1; }
  out=$("${SSH_BASE[@]}" -n "$EXA_USER@$1" "cellcli -e \"$2\"" 2>&1); rc=$?
  if (( rc != 0 )) || grep -q 'CELL-[0-9]' <<<"$out"; then
    err "[cell $1] cellcli falhou (rc=$rc): $2"; printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  printf '%s\n' "$out"
}

exa_cell_mod() {  # versão que ALTERA (respeita DRY-RUN)
  if (( ! EXECUTE )); then dry "[cell $1] cellcli -e \"$2\""; return 0; fi
  info "EXEC [cell $1]: cellcli -e \"$2\""
  exa_cell "$1" "$2"
}

size_to_mb() {  # 5562G | 1.5T | 870400M | bytes -> MB inteiro
  awk -v s="$1" 'BEGIN{u=toupper(substr(s,length(s))); v=substr(s,1,length(s)-1)+0
    if(u=="T")v*=1048576; else if(u=="G")v*=1024; else if(u=="M")v=v; else if(u=="K")v/=1024; else v=(s+0)/1048576
    printf "%d\n", v+0.5}'
}

exa_check_cloud() {
  if command -v dbaascli >/dev/null 2>&1 || [[ -d /var/opt/oracle/creg || -d /var/opt/oracle/dbaas_acfs ]]; then
    die "Exadata Cloud (ExaCS / ExaCC / ExaDB-D) detectado (dbaascli/creg). A storage é gerenciada pela automação da Oracle: escale pelo console OCI ou dbaascli. Este script NÃO altera griddisks/diskgroups nesses ambientes."
  fi
  [[ -r /etc/oracle/cell/network-config/cellip.ora ]] \
    && info "cellip.ora: $(grep -c 'cell=' /etc/oracle/cell/network-config/cellip.ora 2>/dev/null) cell(s) configurada(s)" \
    || warn "/etc/oracle/cell/network-config/cellip.ora não encontrado neste nó."
}

exa_reference() {
  section "Referência Exadata do $DG"
  local i nm pref="" fd=0 hd=0 stats top second line
  for ((i=0; i<${#DGD_NAME[@]}; i++)); do
    nm=${DGD_NAME[$i]}
    if [[ $nm =~ ^(.+)_(CD|FD)_[0-9]+_.+$ ]]; then
      pref+="${BASH_REMATCH[1]}"$'\n'
      [[ ${BASH_REMATCH[2]} == FD ]] && fd=$((fd+1)) || hd=$((hd+1))
    else
      warn "Nome fora do padrão Exadata <PREFIXO>_CD|FD_NN_<cell>: $nm"
    fi
  done
  if [[ -z $EXA_PREFIX ]]; then
    stats=$(printf '%s' "$pref" | sed '/^$/d' | sort | uniq -c | sort -k1,1nr)
    [[ -n $stats ]] || die "Não consegui deduzir o prefixo dos griddisks do $DG. Use --exa-prefix."
    top=$(sed -n 1p <<<"$stats"); second=$(sed -n 2p <<<"$stats")
    [[ -z $second ]] || die "Mais de um prefixo de griddisk no $DG ($(tr -s ' \n' ' ' <<<"$stats")). Use --exa-prefix."
    EXA_PREFIX=$(awk '{print $2}' <<<"$top")
  fi
  EXA_PREFIX=$(upper "$EXA_PREFIX")
  if (( fd > 0 && hd > 0 )); then die "DG mistura griddisks de HardDisk (CD) e FlashDisk (FD). Cenário não suportado."; fi
  (( fd > 0 )) && EXA_DISKTYPE="FlashDisk" || EXA_DISKTYPE="HardDisk"

  line=$(for ((i=0; i<${#DGD_FG[@]}; i++)); do [[ ${DGD_FGT[$i]} == QUORUM ]] || echo "${DGD_FG[$i]}"; done \
         | sort | uniq -c | awk '{print $1}' | sort | uniq -c | sort -k1,1nr | head -1)
  EXA_REF_COUNT=$(awk '{print $2}' <<<"$line")
  EXA_REF_SIZE_MB=$DG_OSMB_REF
  if [[ -n $EXA_SIZE ]]; then EXA_SIZE_STR=$EXA_SIZE; else EXA_SIZE_STR="${EXA_REF_SIZE_MB}M"; fi

  local attrs
  attrs=$(sqlt <<'SQL'
select name||'='||value from v$asm_attribute where group_number = __DGNUM__ and name in ('content.type','cell.smart_scan_capable','compatible.rdbms','appliance.mode') order by name;
SQL
) || true
  ok "Prefixo=$EXA_PREFIX tipo=$EXA_DISKTYPE griddisks/failgroup=$EXA_REF_COUNT tamanho=${EXA_REF_SIZE_MB}MB failgroups(cells):$DG_FGS"
  [[ -n $attrs ]] && info "Atributos: $(tr '\n' ' ' <<<"$attrs")"
}

exa_plan_create() {  # $1=host $2=cellname : planeja CREATE GRIDDISK ALL <tipo> PREFIX=...
  local h=$1 cn=$2 rows nm dt st fr need cnt=0
  need=$(size_to_mb "$EXA_SIZE_STR")
  (( EXA_REF_SIZE_MB == 0 || ALLOW_SIZE_MISMATCH || ( need >= EXA_REF_SIZE_MB*(100-SIZE_TOL)/100 && need <= EXA_REF_SIZE_MB*(100+SIZE_TOL)/100 ) )) \
    || die "--exa-size $EXA_SIZE_STR (${need}MB) difere do tamanho dos griddisks do $DG (${EXA_REF_SIZE_MB}MB)."
  rows=$(exa_cell "$h" "list celldisk attributes name,diskType,status,freeSpace") || die "Falha listando celldisks em $h."
  while read -r nm dt st fr; do
    [[ -n $nm && $dt == "$EXA_DISKTYPE" ]] || continue
    [[ $st == normal ]] || die "Cell $cn: celldisk $nm status=$st (esperado normal)."
    (( $(size_to_mb "$fr") >= need )) || die "Cell $cn: celldisk $nm com freeSpace $fr < ${EXA_SIZE_STR}."
    N_IN+=("$h"); N_REAL+=("$cn"); N_GD+=("${EXA_PREFIX}_${nm}"); N_NAME+=("$(upper "${EXA_PREFIX}_${nm}")")
    N_ASMPATH+=("o/*/${EXA_PREFIX}_${nm}"); N_MB+=("$need"); N_LABEL+=("-"); N_FG+=(""); N_SITE+=("")
    cnt=$((cnt+1))
  done <<<"$rows"
  (( cnt > 0 )) || die "Cell $cn: nenhum celldisk do tipo $EXA_DISKTYPE."
  (( cnt == EXA_REF_COUNT || EXA_ALLOW_PARTIAL )) || die "Cell $cn tem $cnt celldisks $EXA_DISKTYPE, mas cada failgroup do $DG tem $EXA_REF_COUNT griddisks. Use --exa-allow-partial se for intencional."
  EXA_CREATE_PLAN+=("$h|$cn")
  ok "Cell $cn ($h): CRIAR $cnt griddisks ${EXA_PREFIX}_* de $EXA_SIZE_STR (celldisks normal, espaço livre OK)"
}

exa_check_cells() {
  section "Cells Exadata"
  local hosts=() h out cn cs rows nm sz st am dt dgn mb cnt diff
  IFS=',' read -r -a hosts <<<"$EXA_CELLS"
  for h in "${hosts[@]}"; do
    h=$(trim "$h")
    "${SSH_BASE[@]}" -n "$EXA_USER@$h" true >/dev/null 2>&1 \
      || die "ssh $EXA_USER@$h sem senha (BatchMode) falhou. Configure a equivalência (ex.: dcli -g ~/cell_group -l $EXA_USER -k)."
    out=$(exa_cell "$h" "list cell attributes name,status") || die "Falha consultando a cell $h."
    read -r cn cs <<<"$(awk 'NF{print $1, $2; exit}' <<<"$out")"
    [[ -n $cn ]] || die "Cell $h não retornou o nome."
    [[ $cs == online ]] || die "Cell $h ($cn) com status=$cs (esperado online)."
    for out in ${EXA_CNAMES[@]+"${EXA_CNAMES[@]}"}; do [[ $(upper "$out") == "$(upper "$cn")" ]] && die "Cell $cn informada duas vezes."; done
    EXA_HOSTS+=("$h"); EXA_CNAMES+=("$cn")
    [[ $DG_FGS == *" $(upper "$cn") "* ]] && warn "Cell $cn JÁ é failgroup do $DG: só griddisks UNUSED serão considerados."

    rows=$(exa_cell "$h" "list griddisk attributes name,size,status,asmmodestatus,diskType,asmDiskGroupName") || die "Falha listando griddisks em $h."
    rows=$(awk -v p="$EXA_PREFIX" 'NF && toupper($1) ~ ("^" p "_(CD|FD)_")' <<<"$rows")
    if [[ -z $rows ]]; then
      (( EXA_CREATE )) || die "Cell $cn: nenhum griddisk ${EXA_PREFIX}_*. Crie com cellcli ou use --exa-create-griddisk."
      exa_plan_create "$h" "$cn"
      continue
    fi
    (( EXA_CREATE )) && die "Cell $cn já possui griddisks ${EXA_PREFIX}_* — remova --exa-create-griddisk."
    cnt=0
    while read -r nm sz st am dt dgn; do
      [[ -n $nm ]] || continue
      if [[ -n $dgn || $am != UNUSED ]]; then info "  $nm em uso (asmmodestatus=$am dg=${dgn:--}) — ignorado"; continue; fi
      [[ $st == active ]] || die "Griddisk $nm status=$st (esperado active)."
      [[ $dt == "$EXA_DISKTYPE" ]] || die "Griddisk $nm diskType=$dt, mas o $DG usa $EXA_DISKTYPE."
      mb=$(size_to_mb "$sz")
      if (( EXA_REF_SIZE_MB > 0 )); then
        diff=$(( (mb > EXA_REF_SIZE_MB ? mb-EXA_REF_SIZE_MB : EXA_REF_SIZE_MB-mb) * 100 / EXA_REF_SIZE_MB ))
        if (( diff > SIZE_TOL )); then
          (( ALLOW_SIZE_MISMATCH )) || die "Griddisk $nm com ${mb}MB vs ${EXA_REF_SIZE_MB}MB dos griddisks do $DG (${diff}%)."
          warn "Griddisk $nm com tamanho diferente (${mb}MB) aceito por --allow-size-mismatch."
        fi
      fi
      N_IN+=("$h"); N_REAL+=("$cn"); N_GD+=("$nm"); N_NAME+=("$(upper "$nm")"); N_ASMPATH+=("o/*/$nm")
      N_MB+=("$mb"); N_LABEL+=("-"); N_FG+=(""); N_SITE+=("")
      cnt=$((cnt+1))
    done <<<"$rows"
    (( cnt > 0 )) || die "Cell $cn: nenhum griddisk ${EXA_PREFIX}_* livre (todos já estão em diskgroup)."
    (( cnt == EXA_REF_COUNT || EXA_ALLOW_PARTIAL )) || die "Cell $cn: $cnt griddisks livres, mas cada failgroup do $DG tem $EXA_REF_COUNT. Use --exa-allow-partial se for intencional."
    ok "Cell $cn ($h): $cnt griddisks ${EXA_PREFIX}_* active/UNUSED, ${mb}MB cada"
  done
}

exa_discover() {  # $1=1 aguarda (pós-criação). Preenche N_ASMPATH com o path real.
  local wait=${1:-0} att max rows i inst path hdr grp osmb seen report allok
  max=1; (( wait )) && max=12
  for ((att=1; att<=max; att++)); do
    rows=$(sql_query "select inst_id||'|'||path||'|'||header_status||'|'||group_number||'|'||nvl(os_mb,0) from gv\$asm_disk where path like 'o/%';") || return 1
    allok=1; report=""
    for ((i=0; i<${#N_GD[@]}; i++)); do
      seen=0
      while IFS='|' read -r inst path hdr grp osmb; do
        [[ -n $path ]] || continue
        [[ $(upper "${path##*/}") == "$(upper "${N_GD[$i]}")" ]] || continue
        [[ $grp == 0 ]] || { err "${N_GD[$i]} já está no grupo $grp (instância $inst)!"; return 1; }
        case $hdr in CANDIDATE|PROVISIONED|FORMER) ;; *) err "${N_GD[$i]} header=$hdr na instância $inst."; return 1 ;; esac
        [[ $path =~ ^o/[0-9A-Za-z.:\;_/-]+$ ]] || { err "Path inesperado: $path"; return 1; }
        seen=$((seen+1)); N_ASMPATH[$i]=$path
      done <<<"$rows"
      (( seen == INST_COUNT )) || { allok=0; report+="${N_GD[$i]} em $seen/$INST_COUNT; "; }
    done
    if (( allok )); then ok "Todos os ${#N_GD[@]} griddisks descobertos como CANDIDATE em $INST_COUNT instância(s) ASM."; return 0; fi
    (( att < max )) && { info "Aguardando descoberta ($att/$max): $report"; sleep 10; }
  done
  err "Descoberta incompleta: $report"
  err "Verifique cellip.ora/cellinit.ora, asm_diskstring ('$ASM_DISKSTRING') e o status das cells."
  return 1
}

flow_exadata() {
  local e h cn
  require_root
  detect_grid
  detect_cluster
  REMOTE_MODE="none"
  load_dg
  check_dg_health
  METHOD="exadata"; PART_EFF="no"
  exa_check_cloud
  exa_reference
  exa_check_cells
  if (( ${#EXA_CREATE_PLAN[@]} == 0 )); then
    section "Descoberta pelo ASM"
    exa_discover 0 || die "Os griddisks não estão visíveis para todas as instâncias ASM — nada foi alterado."
  fi
  resolve_power
  print_plan

  if (( ! EXECUTE )); then
    section "DRY-RUN — comandos que seriam executados"
    for e in ${EXA_CREATE_PLAN[@]+"${EXA_CREATE_PLAN[@]}"}; do
      exa_cell_mod "${e%%|*}" "create griddisk all $(tr '[:upper:]' '[:lower:]' <<<"$EXA_DISKTYPE") prefix=$EXA_PREFIX, size=$EXA_SIZE_STR"
    done
    (( ${#EXA_CREATE_PLAN[@]} )) && dry "aguardar a descoberta dos griddisks em todas as instâncias ASM (gv\$asm_disk)"
    [[ $ACTION == provision-only ]] || do_alter
    (( MON_WAIT )) && dry "monitoramento do rebalance a cada ${POLL}s"
    printf '\n%sDRY-RUN concluído: NADA foi alterado. Revise o plano e rode novamente com --execute.%s\n' "$C_G" "$C_0"
    return 0
  fi

  section "CONFIRMAÇÃO"
  echo "  Esta operação vai alterar as cells ${EXA_CNAMES[*]} e/ou o diskgroup $DG (Exadata)."
  confirm_typed "$DG" "  Digite o nome do diskgroup ($DG): "
  confirm_typed "${#N_NAME[@]}" "  Digite a quantidade de griddisks (${#N_NAME[@]}): "

  PHASE="execute"
  snapshot "antes"
  for e in ${EXA_CREATE_PLAN[@]+"${EXA_CREATE_PLAN[@]}"}; do
    h=${e%%|*}; cn=${e#*|}
    section "Criando griddisks ${EXA_PREFIX}_* na cell $cn"
    [[ -z $(exa_cell "$h" "list griddisk attributes name" | awk -v p="$EXA_PREFIX" 'toupper($1) ~ ("^" p "_")') ]] \
      || die "A cell $cn ganhou griddisks ${EXA_PREFIX}_* desde a validação. Abortando." 3
    exa_cell_mod "$h" "create griddisk all $(tr '[:upper:]' '[:lower:]' <<<"$EXA_DISKTYPE") prefix=$EXA_PREFIX, size=$EXA_SIZE_STR" \
      || die "Falha criando griddisks na cell $cn." 3
    UNDO+=("[cell $cn] cellcli -e \"drop griddisk all prefix=$EXA_PREFIX\"    # SOMENTE se NÃO estiverem no ASM")
    ok "Griddisks criados na cell $cn."
  done
  if (( ${#EXA_CREATE_PLAN[@]} )); then
    section "Descoberta pelo ASM"
    exa_discover 1 || die "Griddisks criados, mas não descobertos por todas as instâncias — ALTER NÃO executado." 3
  fi

  if [[ $ACTION == provision-only ]]; then
    UNDO=(); snapshot "depois"
    section "GRIDDISKS CRIADOS"
    printf '  Para adicionar: %s -g %s --exa-cell %s -p <N> --execute\n' "$0" "$DG" "$EXA_CELLS"
    return 0
  fi

  do_alter
  post_verify
  (( MON_WAIT )) && monitor_rebal
  snapshot "depois"
  section "CONCLUÍDO"
  echo "  Cells adicionadas ao $DG: ${EXA_CNAMES[*]} (${#N_NAME[@]} griddisks)"
  echo "  Acompanhar : $0 -g $DG --monitor"
  echo "  Status     : $0 -g $DG --status"
  for cn in "${EXA_CNAMES[@]}"; do
    printf '  Reverter   : ALTER DISKGROUP %s DROP DISKS IN FAILGROUP %s REBALANCE POWER <N>;  (avalie o espaço antes!)\n' "$DG" "$(upper "$cn")"
  done
  (( WARN_COUNT > 0 )) && warn "Execução com $WARN_COUNT aviso(s) — revise o log."
  return 0
}

#------------------------------------------------------------------------------
# Fluxo principal de adição
#------------------------------------------------------------------------------
flow_add() {
  local i
  if [[ -n $EXA_CELLS ]]; then flow_exadata; return; fi
  [[ $ACTION == add-only ]] || require_root
  detect_grid
  detect_cluster
  [[ $ACTION == add-only ]] && REMOTE_MODE="none" || setup_remote
  load_dg
  check_dg_health
  [[ $OS == Linux ]] && load_afd_map
  load_all_asm_disks
  detect_method
  if [[ $OS == Linux && -z $ORACLEASM_BIN ]]; then ORACLEASM_BIN=$(command -v oracleasm 2>/dev/null || true); fi
  prepare_method
  collect_asm_majmins
  if [[ $ACTION == add-only ]]; then
    check_addonly_disks
  else
    detect_partition_style
    check_new_disks
  fi
  gen_labels_and_names
  resolve_failgroups
  resolve_power
  decide_partition
  print_plan

  if (( ! EXECUTE )); then
    section "DRY-RUN — comandos que seriam executados"
    if [[ $ACTION != add-only ]]; then
      for ((i=0; i<${#N_IN[@]}; i++)); do
        case $OS in Linux) prov_linux "$i" ;; AIX) prov_aix "$i" ;; esac
      done
    fi
    verify_discovery
    [[ $ACTION == provision-only ]] || do_alter
    (( MON_WAIT )) && dry "monitoramento do rebalance a cada ${POLL}s"
    printf '\n%sDRY-RUN concluído: NADA foi alterado. Revise o plano e rode novamente com --execute.%s\n' "$C_G" "$C_0"
    return 0
  fi

  section "CONFIRMAÇÃO"
  echo "  Esta operação vai alterar o storage e o diskgroup $DG em $(hostname)."
  confirm_typed "$DG" "  Digite o nome do diskgroup ($DG): "
  confirm_typed "${#N_IN[@]}" "  Digite a quantidade de discos (${#N_IN[@]}): "

  PHASE="execute"
  snapshot "antes"
  [[ $ACTION == add-only ]] || execute_provision
  verify_discovery || die "Descoberta falhou — ALTER NÃO executado." 3

  if [[ $ACTION == provision-only ]]; then
    UNDO=()
    snapshot "depois"
    section "PROVISIONAMENTO CONCLUÍDO"
    echo "  Discos prontos (não adicionados). Para adicionar:"
    printf '    %s -g %s --add-only -d %s -p <N> --execute\n' "$0" "$DG" "$(IFS=,; echo "${N_LABEL[*]}")"
    return 0
  fi

  do_alter
  post_verify
  (( MON_WAIT )) && monitor_rebal
  snapshot "depois"

  section "CONCLUÍDO"
  echo "  Discos adicionados ao $DG: ${N_NAME[*]}"
  echo "  Acompanhar : $0 -g $DG --monitor"
  echo "  Status     : $0 -g $DG --status"
  echo "  Power      : $0 -g $DG --set-power <N> --execute"
  printf '  Reverter   : ALTER DISKGROUP %s DROP DISK %s REBALANCE POWER <N>;  (só depois de avaliar espaço!)\n' \
    "$DG" "$(IFS=,; echo "${N_NAME[*]}")"
  (( WARN_COUNT > 0 )) && warn "Execução com $WARN_COUNT aviso(s) — revise o log."
  return 0
}

#------------------------------------------------------------------------------
main() {
  parse_args "$@"
  validate_args
  setup_colors
  trap on_exit EXIT
  trap 'on_signal INT' INT
  trap 'on_signal TERM' TERM
  init_runtime
  banner
  info "Ação=$ACTION | modo=$([[ $EXECUTE == 1 ]] && echo EXECUTE || echo DRY-RUN) | host=$(hostname) | usuário=$CUR_USER | SO=$OS"
  info "Linha de comando: $0 $*"

  case $ACTION in
    add|provision-only|add-only|set-power|rescan) (( EXECUTE )) && acquire_lock ;;
  esac

  case $ACTION in
    add|provision-only|add-only) flow_add ;;
    status)    detect_grid; load_dg; show_status ;;
    monitor)   detect_grid; load_dg; monitor_rebal ;;
    set-power) detect_grid; load_dg; do_set_power ;;
    scan)      require_root
               if ps -eo args 2>/dev/null | grep -q '^asm_pmon_+ASM'; then detect_grid; [[ $OS == Linux ]] && load_afd_map; load_all_asm_disks; collect_asm_majmins
               else warn "ASM não está no ar: o scan não consegue cruzar com os discos do ASM."; fi
               [[ $OS == Linux ]] && ORACLEASM_BIN=$(command -v oracleasm 2>/dev/null || true)
               do_scan ;;
    rescan)    (( EXECUTE )) || warn "--rescan sem --execute: só mostra os comandos."
               if ps -eo args 2>/dev/null | grep -q '^asm_pmon_+ASM'; then detect_grid; detect_cluster; setup_remote; [[ $OS == Linux ]] && load_afd_map; load_all_asm_disks; collect_asm_majmins; fi
               [[ $OS == Linux ]] && ORACLEASM_BIN=$(command -v oracleasm 2>/dev/null || true)
               do_rescan ;;
  esac
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
