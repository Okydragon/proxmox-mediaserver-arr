#!/usr/bin/env bash
# ct/mediaserver.sh
# Cria um LXC Debian 12/13 (unprivileged) para o Media Server Stack
# (Jellyfin + qBittorrent + Prowlarr/Radarr/Sonarr/Lidarr + Bazarr + Flaresolverr)
#
# Rode este script no shell do NODE Proxmox, como root:
#   bash ct/mediaserver.sh
#
# Ele espera encontrar install/mediaserver-install.sh no mesmo diretório pai
# (ou seja: rode a partir da raiz do repo clonado).
#
# Mensagens ao usuário (whiptail/echo) são bilíngues (pt-BR/en) via a função
# t() logo abaixo; comentários no código continuam só em português, já que
# são só para quem for ler/manter o script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL_SCRIPT="$REPO_ROOT/install/mediaserver-install.sh"

# ---------- Idioma / Language ----------
LANG_CHOICE=$(whiptail --menu "Escolha o idioma / Choose your language" 12 60 2 \
    "pt" "Português (Brasil)" \
    "en" "English" \
    --default-item "pt" --title "Idioma / Language" 3>&1 1>&2 2>&3)
[ -z "$LANG_CHOICE" ] && LANG_CHOICE="pt"

# ---------- Mensagens (pt-BR / en) ----------
# t() devolve o texto certo pra chave pedida, no idioma escolhido acima. As
# strings referenciam variáveis do script diretamente (ex: $CT_ID) — como é
# uma função de verdade, elas são resolvidas na hora da chamada, não na hora
# em que t() foi definida.
t() {
    local key="$1"
    if [ "$LANG_CHOICE" = "en" ]; then
        case "$key" in
            err_install_not_found) echo "ERROR: could not find $INSTALL_SCRIPT. Run this script from the repo root." ;;
            debian_updating_catalog) echo "Updating template catalog (pveam update)..." ;;
            debian_catalog_fail) echo "WARNING: could not query the pveam catalog. Using fixed fallback (Debian 12)." ;;
            debian_menu_prompt) echo "Debian version for the LXC (latest pre-selected).\nAll apps run in Docker, so the host version has little impact on compatibility." ;;
            debian_menu_title) echo "Container Template" ;;
            debian_using_template) echo "Using template: $TEMPLATE" ;;
            debian_downloading) echo "Downloading template $TEMPLATE (may take a minute)..." ;;
            media_none_found) echo "No eligible mounted disk was found automatically (excluding Ceph/rootfs)." ;;
            media_manual_full) echo "ABSOLUTE path on the HOST where the media is/will be (e.g. /mnt/midia)\nThis path must be a disk/partition already mounted on the node." ;;
            media_manual_short) echo "ABSOLUTE path on the HOST where the media is/will be (e.g. /mnt/midia)" ;;
            media_storage_title) echo "Media Storage" ;;
            media_menu_item_manual) echo "Type a path manually" ;;
            media_menu_prompt) echo "Disks/partitions already mounted on the node (Ceph and the boot disk were already excluded).\nChoose where the media will live:" ;;
            media_subpath_prompt) echo "Media path inside ${mnt}\n(use the mount point itself, or a subdirectory of it)" ;;
            qbt_password_title) echo "qBittorrent Password" ;;
            qbt_password_prompt) echo "qBittorrent WebUI password (the username will be 'admin').\nAn easy-to-type suggestion is already filled in below - accept it or replace it with your own." ;;
            setup_title) echo "Media Server Setup" ;;
            prompt_ct_id) echo "LXC container ID" ;;
            prompt_hostname) echo "Container hostname" ;;
            prompt_storage) echo "Proxmox storage for the rootfs (e.g. local-lvm)" ;;
            prompt_disk) echo "Rootfs size in GB" ;;
            prompt_cores) echo "CPU cores" ;;
            prompt_ram) echo "RAM in MB" ;;
            gpu_title) echo "GPU Passthrough" ;;
            gpu_prompt) echo "Enable GPU passthrough (Intel QuickSync) for Jellyfin?" ;;
            net_title) echo "Network" ;;
            net_prompt_yesno) echo "Set up a fixed IP for this container?\n\nRecommended if you're going to put an external reverse proxy in front of it later - that way the address you register there won't change on its own. If you already reserve the IP by MAC on your DHCP/router, you can answer No and keep DHCP." ;;
            net_ip_prompt) echo "Fixed IP + mask in CIDR notation (e.g. 192.168.1.50/24)" ;;
            net_gateway_prompt) echo "Gateway (e.g. 192.168.1.1)" ;;
            net_dns_prompt) echo "DNS server (optional - leave blank to inherit from the Proxmox host)" ;;
            net_dhcp_warning) echo "WARNING: IP or gateway not provided. Keeping DHCP." ;;
            media_dir_missing_prompt) echo "The path $MEDIA_PATH does not exist. Create it now?" ;;
            media_dir_abort) echo "Aborting: invalid media path." ;;
            gpu_warn_no_dri) echo "WARNING: /dev/dri does not exist on this host. Skipping GPU passthrough." ;;
            gpu_warn_no_groups) echo "WARNING: could not detect the video/render groups on the host. Configure passthrough manually." ;;
            gpu_configured) echo "GPU passthrough configured (video=${VIDEO_GID}, render=${RENDER_GID})." ;;
            gpu_important) echo "IMPORTANT: check /etc/pve/lxc/${CT_ID}.conf before considering this final - GIDs vary per host." ;;
            waiting_network) echo "Waiting for the network to come up inside the container..." ;;
            summary_ready) echo " Media Server ready! Container ID: $CT_ID" ;;
            summary_qbt) echo " qBittorrent - user: admin / password: the one you set during install" ;;
            summary_qbt_note1) echo "   (the install script confirms above whether it managed to apply it automatically;" ;;
            summary_qbt_note2) echo "   if not, run: docker logs qbittorrent | grep -i password)" ;;
            summary_next_steps) echo " Manual next step: register your private indexers in Prowlarr." ;;
        esac
    else
        case "$key" in
            err_install_not_found) echo "ERRO: não encontrei $INSTALL_SCRIPT. Rode este script a partir da raiz do repo." ;;
            debian_updating_catalog) echo "Atualizando catálogo de templates (pveam update)..." ;;
            debian_catalog_fail) echo "AVISO: não consegui consultar o catálogo pveam. Usando fallback fixo (Debian 12)." ;;
            debian_menu_prompt) echo "Versão do Debian para o LXC (mais recente pré-selecionada).\nTodas as apps rodam em Docker, então a versão do host tem pouco impacto na compatibilidade." ;;
            debian_menu_title) echo "Template do Container" ;;
            debian_using_template) echo "Usando template: $TEMPLATE" ;;
            debian_downloading) echo "Baixando template $TEMPLATE (pode levar um minuto)..." ;;
            media_none_found) echo "Nenhum disco montado elegível foi encontrado automaticamente (fora Ceph/rootfs)." ;;
            media_manual_full) echo "Caminho ABSOLUTO no HOST onde a mídia está/ficará (ex: /mnt/midia)\nEste path deve ser um disco/partição já montado no node." ;;
            media_manual_short) echo "Caminho ABSOLUTO no HOST onde a mídia está/ficará (ex: /mnt/midia)" ;;
            media_storage_title) echo "Storage de Mídia" ;;
            media_menu_item_manual) echo "Digitar um caminho manualmente" ;;
            media_menu_prompt) echo "Discos/partições já montados no node (Ceph e o disco de boot já foram excluídos).\nEscolha onde a mídia vai ficar:" ;;
            media_subpath_prompt) echo "Caminho da mídia dentro de ${mnt}\n(use o próprio ponto de montagem, ou um subdiretório dele)" ;;
            qbt_password_title) echo "Senha do qBittorrent" ;;
            qbt_password_prompt) echo "Senha da WebUI do qBittorrent (usuário será 'admin').\nJá vem uma sugestão fácil de digitar preenchida abaixo - aceite ou troque pela sua." ;;
            setup_title) echo "Media Server Setup" ;;
            prompt_ct_id) echo "ID do container LXC" ;;
            prompt_hostname) echo "Hostname do container" ;;
            prompt_storage) echo "Storage do Proxmox p/ o rootfs (ex: local-lvm)" ;;
            prompt_disk) echo "Tamanho do rootfs em GB" ;;
            prompt_cores) echo "Núcleos de CPU" ;;
            prompt_ram) echo "RAM em MB" ;;
            gpu_title) echo "GPU Passthrough" ;;
            gpu_prompt) echo "Habilitar passthrough de GPU (Intel QuickSync) para o Jellyfin?" ;;
            net_title) echo "Rede" ;;
            net_prompt_yesno) echo "Configurar um IP fixo para este container?\n\nRecomendado se você for usar um Nginx Proxy Manager externo depois - assim o endereço que você cadastrar lá não muda sozinho. Se você já reserva o IP por MAC no seu DHCP/router, pode responder Não e manter DHCP." ;;
            net_ip_prompt) echo "IP fixo + máscara em CIDR (ex: 192.168.1.50/24)" ;;
            net_gateway_prompt) echo "Gateway (ex: 192.168.1.1)" ;;
            net_dns_prompt) echo "Servidor DNS (opcional - deixe em branco para herdar do host Proxmox)" ;;
            net_dhcp_warning) echo "AVISO: IP ou gateway não informado. Mantendo DHCP." ;;
            media_dir_missing_prompt) echo "O caminho $MEDIA_PATH não existe. Criar agora?" ;;
            media_dir_abort) echo "Abortando: caminho de mídia inválido." ;;
            gpu_warn_no_dri) echo "AVISO: /dev/dri não existe neste host. Pulando GPU passthrough." ;;
            gpu_warn_no_groups) echo "AVISO: não consegui detectar os grupos video/render no host. Configure o passthrough manualmente." ;;
            gpu_configured) echo "GPU passthrough configurado (video=${VIDEO_GID}, render=${RENDER_GID})." ;;
            gpu_important) echo "IMPORTANTE: confira /etc/pve/lxc/${CT_ID}.conf antes de considerar definitivo - os GIDs variam por host." ;;
            waiting_network) echo "Aguardando rede subir dentro do container..." ;;
            summary_ready) echo " Media Server pronto! Container ID: $CT_ID" ;;
            summary_qbt) echo " qBittorrent - usuário: admin / senha: a que você definiu na instalação" ;;
            summary_qbt_note1) echo "   (o install script confirma acima se conseguiu aplicá-la automaticamente;" ;;
            summary_qbt_note2) echo "   se não conseguiu, rode: docker logs qbittorrent | grep -i password)" ;;
            summary_next_steps) echo " Próximos passos manuais: cadastro dos seus indexers privados no Prowlarr." ;;
        esac
    fi
}

if [ ! -f "$INSTALL_SCRIPT" ]; then
    echo "$(t err_install_not_found)"
    exit 1
fi

# ---------- Defaults ----------
CT_ID_DEFAULT=301
CT_HOSTNAME_DEFAULT="mediaserver"
CT_STORAGE_DEFAULT="local-lvm"
CT_DISK_DEFAULT=32
CT_CORES_DEFAULT=4
CT_RAM_DEFAULT=8192
CT_BRIDGE_DEFAULT="vmbr0"
MEDIA_PATH_DEFAULT="/mnt/midia"
TEMPLATE_STORAGE_DEFAULT="local"
PUID_DEFAULT=1000
PGID_DEFAULT=1000
TZ_DEFAULT="America/Sao_Paulo"

# ---------- Detecção da versão do Debian (template LXC) ----------
# Em vez de fixar uma string de template exata (ex: "debian-12-standard_12.7-1_amd64.tar.zst"),
# que fica desatualizada a cada patch release, consultamos o catálogo do pveam em
# tempo real e deixamos o usuário escolher a major version do Debian, com a mais
# recente pré-selecionada. Como todas as aplicações rodam em containers Docker
# (com suas próprias imagens-base), a versão do Debian do LXC em si tem pouco
# impacto na compatibilidade — o principal é ter o repositório oficial do Docker
# suportando o codename escolhido, o que já é checado dinamicamente pelo
# install/mediaserver-install.sh.
select_debian_template() {
    TEMPLATE_STORAGE="$TEMPLATE_STORAGE_DEFAULT"

    echo "$(t debian_updating_catalog)"
    pveam update >/dev/null 2>&1 || true

    local catalog
    catalog="$(pveam available -section system 2>/dev/null | awk '{print $2}' | grep -E '^debian-[0-9]+-standard_' || true)"

    if [ -z "$catalog" ]; then
        echo "$(t debian_catalog_fail)"
        TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
        return
    fi

    # Mantém só o release mais recente de cada major version (o catálogo do pveam
    # já vem em ordem crescente por release, então a última ocorrência "vence")
    local -A latest_by_major=()
    local majors_order=()
    while IFS= read -r tmpl; do
        local major
        major="$(echo "$tmpl" | sed -E 's/^debian-([0-9]+)-standard_.*/\1/')"
        if [ -z "${latest_by_major[$major]:-}" ]; then
            majors_order+=("$major")
        fi
        latest_by_major["$major"]="$tmpl"
    done <<< "$catalog"

    local sorted_majors
    sorted_majors="$(printf '%s\n' "${majors_order[@]}" | sort -rn)"

    local menu_args=()
    local default_choice=""
    while IFS= read -r major; do
        [ -z "$default_choice" ] && default_choice="$major"
        menu_args+=("$major" "Debian ${major} — ${latest_by_major[$major]}")
    done <<< "$sorted_majors"

    local choice
    choice=$(whiptail --menu "$(t debian_menu_prompt)" 16 78 6 "${menu_args[@]}" --default-item "$default_choice" --title "$(t debian_menu_title)" 3>&1 1>&2 2>&3)
    [ -z "$choice" ] && choice="$default_choice"

    TEMPLATE="${latest_by_major[$choice]}"
    echo "$(t debian_using_template)"

    if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
        echo "$(t debian_downloading)"
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
    fi
}

# ---------- Detecção de discos de mídia ----------
# Lista discos/partições JÁ MONTADOS no host, excluindo automaticamente:
#   - o disco de boot/rootfs do próprio Proxmox
#   - qualquer coisa usada pelo Ceph (OSDs bluestore "crus" ou VGs criados
#     pelo ceph-volume, que seguem o padrão de nome "ceph-<uuid>")
#   - VGs usados por storages LVM/LVM-thin do Proxmox (ex: local-lvm, onde
#     fica o rootfs dos containers)
# Não formata nada automaticamente — só lista o que já está pronto para uso.
# Ajuste os filtros abaixo se o layout de disco/Ceph do seu cluster for
# diferente do padrão (ex: Ceph em modo "simple" sem LVM).
detect_media_candidates() {
    MEDIA_CANDIDATES=()

    local root_src root_disk
    root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
    [ -z "$root_disk" ] && root_disk="$(basename "${root_src:-}")"

    # VGs criados pelo ceph-volume (layout LVM usado pelo Ceph em clusters Proxmox)
    local ceph_vgs
    ceph_vgs="$(pvs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1};1' | grep -i '^ceph-' || true)"

    # VGs usados por storages "lvm"/"lvmthin" cadastradas no Proxmox (ex: local-lvm)
    local pve_vgs
    pve_vgs="$(awk '
        /^(lvmthin|lvm):/ {intype=1; next}
        /^[a-zA-Z]+:/ {intype=0}
        intype && $1=="vgname" {print $2}
    ' /etc/pve/storage.cfg 2>/dev/null || true)"

    # NOTA: usamos eval aqui porque lsblk -P emite pares KEY="value" já
    # devidamente escapados/entre aspas — é o próprio host (root) descrevendo
    # seus discos, não entrada de usuário, então é seguro no nosso contexto.
    while IFS= read -r line; do
        eval "$line"

        [ -z "${MOUNTPOINT:-}" ] && continue
        case "$MOUNTPOINT" in
            /|/boot|/boot/*|/etc/pve*|/var/lib/vz) continue ;;
        esac
        [ "${FSTYPE:-}" = "ceph_bluestore" ] && continue

        local disk_base="${PKNAME:-$NAME}"
        if [ -n "$root_disk" ] && [ "$disk_base" = "$root_disk" ]; then
            continue
        fi

        if [ "${TYPE:-}" = "lvm" ]; then
            local vg
            vg="$(lvs --noheadings -o vg_name "/dev/$NAME" 2>/dev/null | awk '{$1=$1};1')"
            if [ -n "$vg" ]; then
                if echo "$ceph_vgs" | grep -qxF "$vg"; then continue; fi
                if echo "$pve_vgs" | grep -qxF "$vg"; then continue; fi
            fi
        fi

        MEDIA_CANDIDATES+=("/dev/${NAME}|${MOUNTPOINT}|${SIZE:-?}|${FSTYPE:-?}")
    done < <(lsblk -P -o NAME,MOUNTPOINT,FSTYPE,SIZE,PKNAME,TYPE)
}

# Monta o menu de seleção (ou cai para digitação manual) e define $MEDIA_PATH
select_media_path() {
    detect_media_candidates

    if [ "${#MEDIA_CANDIDATES[@]}" -eq 0 ]; then
        echo "$(t media_none_found)"
        MEDIA_PATH=$(whiptail --inputbox "$(t media_manual_full)" 10 70 "$MEDIA_PATH_DEFAULT" --title "$(t media_storage_title)" 3>&1 1>&2 2>&3)
        return
    fi

    local menu_args=()
    local i=0
    for entry in "${MEDIA_CANDIDATES[@]}"; do
        IFS='|' read -r dev mnt size fstype <<< "$entry"
        menu_args+=("$i" "$mnt  (${size}, ${fstype}, ${dev})")
        i=$((i+1))
    done
    menu_args+=("MANUAL" "$(t media_menu_item_manual)")

    local choice
    choice=$(whiptail --menu "$(t media_menu_prompt)" 18 78 8 "${menu_args[@]}" --title "$(t media_storage_title)" 3>&1 1>&2 2>&3)

    if [ "$choice" = "MANUAL" ] || [ -z "$choice" ]; then
        MEDIA_PATH=$(whiptail --inputbox "$(t media_manual_short)" 10 70 "$MEDIA_PATH_DEFAULT" --title "$(t media_storage_title)" 3>&1 1>&2 2>&3)
    else
        IFS='|' read -r dev mnt size fstype <<< "${MEDIA_CANDIDATES[$choice]}"
        MEDIA_PATH=$(whiptail --inputbox "$(t media_subpath_prompt)" 10 70 "$mnt" --title "$(t media_storage_title)" 3>&1 1>&2 2>&3)
    fi
}

# ---------- Senha da WebUI do qBittorrent ----------
# As versões atuais do qBittorrent geram uma senha temporária ALEATÓRIA no
# primeiro boot (mudança de segurança da própria aplicação) — então não dá
# mais pra simplesmente fixar "adminadmin" como uma versão anterior deste
# script fazia; o install script precisa reaplicar uma senha conhecida via
# API depois que o container subir (ver comentário em
# install/mediaserver-install.sh). Em vez de só gerar uma senha sozinho e
# impor pro usuário, sugerimos uma (fácil de digitar: 3 palavras + 2 dígitos,
# só minúsculas e hífen, sem símbolos) já preenchida no campo abaixo — você
# aceita a sugestão ou digita a sua própria.
QBT_WORDLIST=(
    acorde agulha alerta amora ancora anel arco areia atlas aurora
    bambu banco barco base bloco bolha bosque brasa brilho bronze
    cacto campo canela carvao casca cedro cesta chama chave cidade
    clima cobre coral corda coroa cristal dado delta deserto disco
    dragao duna elmo escudo esfera estrada estufa faisca farol fauna
    fenda ferro festa feixe fibra flauta flecha flor fonte forja
    forma forno forte fumaca futuro gado garra gema gesso grama
    grao grito grota gruta guia harpa horizonte ilha jade janela
    jangada jardim jato lago lamina lanterna lapis largo lenha letra
    ligeiro limao lince lousa lua luz maca mapa marfim mastro
    mel meteoro monte montanha morango neblina neve nuvem oasis onda
    ouro papel pedra pinho pinha planeta pluma ponte porto prata
    quartzo raiz ramo riacho rio rocha sabor sal savana selva
    sino sol tecido tempo terra tijolo trilha tronco vale vento
    verde vidro vinho vulcao agua ambar aroma
)

# Escolhida com `shuf` (em vez do $RANDOM do bash, que é um PRNG fraco) —
# 3 palavras + 2 dígitos dá uma senha do tipo "campo-farol-bronze-47":
# fácil de ler/digitar, sem símbolos, e razoável para uso doméstico (a
# WebUI do qBittorrent já bane IPs após tentativas de login consecutivas
# com falha, o que mitiga força-bruta online).
generate_memorable_password() {
    local w1 w2 w3 num
    w1="$(shuf -n1 -e "${QBT_WORDLIST[@]}")"
    w2="$(shuf -n1 -e "${QBT_WORDLIST[@]}")"
    w3="$(shuf -n1 -e "${QBT_WORDLIST[@]}")"
    num="$(shuf -i 10-99 -n1)"
    echo "${w1}-${w2}-${w3}-${num}"
}

select_qbt_password() {
    local suggestion
    suggestion="$(generate_memorable_password)"
    QBT_PASSWORD=$(whiptail --inputbox "$(t qbt_password_prompt)" 11 74 "$suggestion" --title "$(t qbt_password_title)" 3>&1 1>&2 2>&3)
    [ -z "$QBT_PASSWORD" ] && QBT_PASSWORD="$suggestion"
}

# ---------- Prompts interativos ----------
CT_ID=$(whiptail --inputbox "$(t prompt_ct_id)" 8 60 "$CT_ID_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)
CT_HOSTNAME=$(whiptail --inputbox "$(t prompt_hostname)" 8 60 "$CT_HOSTNAME_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)
CT_STORAGE=$(whiptail --inputbox "$(t prompt_storage)" 8 60 "$CT_STORAGE_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)
CT_DISK=$(whiptail --inputbox "$(t prompt_disk)" 8 60 "$CT_DISK_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)
CT_CORES=$(whiptail --inputbox "$(t prompt_cores)" 8 60 "$CT_CORES_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)
CT_RAM=$(whiptail --inputbox "$(t prompt_ram)" 8 60 "$CT_RAM_DEFAULT" --title "$(t setup_title)" 3>&1 1>&2 2>&3)

select_debian_template

select_media_path

select_qbt_password

if whiptail --yesno "$(t gpu_prompt)" 10 60 --title "$(t gpu_title)"; then
    USE_GPU="yes"
else
    USE_GPU="no"
fi

# ---------- Rede: IP estático opcional ----------
# Por padrão o container recebe IP via DHCP. Isso é um problema específico
# para quem for colocar um Nginx Proxy Manager EXTERNO (fora deste LXC e fora
# do Docker) na frente dos apps depois: o NPM guarda o IP:porta de cada app
# como "Proxy Host" fixo, e se o DHCP trocar o IP do container mais tarde,
# todos os Proxy Hosts quebram sem aviso. Deixamos como OPCIONAL porque quem
# já reserva o IP por MAC no próprio DHCP/router não precisa disso.
NET_CONFIG="name=eth0,bridge=${CT_BRIDGE_DEFAULT},ip=dhcp"
CT_DNS=""

if whiptail --yesno "$(t net_prompt_yesno)" 14 78 --title "$(t net_title)"; then
    CT_IP_CIDR=$(whiptail --inputbox "$(t net_ip_prompt)" 9 70 "" --title "$(t net_title)" 3>&1 1>&2 2>&3)
    CT_GATEWAY=$(whiptail --inputbox "$(t net_gateway_prompt)" 9 70 "" --title "$(t net_title)" 3>&1 1>&2 2>&3)
    CT_DNS=$(whiptail --inputbox "$(t net_dns_prompt)" 9 70 "" --title "$(t net_title)" 3>&1 1>&2 2>&3)

    if [ -z "$CT_IP_CIDR" ] || [ -z "$CT_GATEWAY" ]; then
        echo "$(t net_dhcp_warning)"
    else
        NET_CONFIG="name=eth0,bridge=${CT_BRIDGE_DEFAULT},ip=${CT_IP_CIDR},gw=${CT_GATEWAY}"
    fi
fi

# ---------- Validações ----------
if [ ! -d "$MEDIA_PATH" ]; then
    if whiptail --yesno "$(t media_dir_missing_prompt)" 8 60; then
        mkdir -p "$MEDIA_PATH"
    else
        echo "$(t media_dir_abort)"
        exit 1
    fi
fi

for sub in downloads filmes series musicas; do
    mkdir -p "$MEDIA_PATH/$sub"
done

# ---------- Criação do container ----------
PCT_EXTRA_ARGS=()
if [ -n "$CT_DNS" ]; then
    PCT_EXTRA_ARGS+=(--nameserver "$CT_DNS")
fi

pct create "$CT_ID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$CT_HOSTNAME" \
    --unprivileged 1 \
    --cores "$CT_CORES" \
    --memory "$CT_RAM" \
    --swap 512 \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "$NET_CONFIG" \
    --features "nesting=1,keyctl=1" \
    --onboot 1 \
    "${PCT_EXTRA_ARGS[@]}"

# ---------- Bind mount da mídia ----------
pct set "$CT_ID" -mp0 "${MEDIA_PATH},mp=/mnt/midia"

# ---------- GPU Passthrough (opcional) ----------
if [ "$USE_GPU" = "yes" ]; then
    if [ ! -e /dev/dri ]; then
        echo "$(t gpu_warn_no_dri)"
    else
        VIDEO_GID=$(getent group video | cut -d: -f3)
        RENDER_GID=$(getent group render | cut -d: -f3)

        if [ -z "$VIDEO_GID" ] || [ -z "$RENDER_GID" ]; then
            echo "$(t gpu_warn_no_groups)"
        else
            # Garante ordem video < render para o cálculo do idmap abaixo
            if [ "$VIDEO_GID" -gt "$RENDER_GID" ]; then
                TMP=$VIDEO_GID; VIDEO_GID=$RENDER_GID; RENDER_GID=$TMP
            fi

            {
                echo "lxc.cgroup2.devices.allow: c 226:0 rwm"
                echo "lxc.cgroup2.devices.allow: c 226:128 rwm"
                echo "lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir"
                echo "lxc.idmap: u 0 100000 65536"
                echo "lxc.idmap: g 0 100000 ${VIDEO_GID}"
                echo "lxc.idmap: g ${VIDEO_GID} ${VIDEO_GID} 1"
                echo "lxc.idmap: g $((VIDEO_GID+1)) $((100000+VIDEO_GID+1)) $((RENDER_GID-VIDEO_GID-1))"
                echo "lxc.idmap: g ${RENDER_GID} ${RENDER_GID} 1"
                echo "lxc.idmap: g $((RENDER_GID+1)) $((100000+RENDER_GID+1)) $((65536-RENDER_GID-1))"
            } >> "/etc/pve/lxc/${CT_ID}.conf"

            echo "$(t gpu_configured)"
            echo "$(t gpu_important)"
        fi
    fi
fi

# ---------- Start + provisionamento ----------
pct start "$CT_ID"
echo "$(t waiting_network)"
sleep 8

pct push "$CT_ID" "$INSTALL_SCRIPT" /root/mediaserver-install.sh

pct exec "$CT_ID" -- bash -c "chmod +x /root/mediaserver-install.sh"
pct exec "$CT_ID" -- env \
    MEDIA_PATH="/mnt/midia" \
    PUID="$PUID_DEFAULT" \
    PGID="$PGID_DEFAULT" \
    TZ="$TZ_DEFAULT" \
    QBT_PASSWORD="$QBT_PASSWORD" \
    LANG_CHOICE="$LANG_CHOICE" \
    /root/mediaserver-install.sh

CT_IP=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')

echo ""
echo "==================================================="
echo "$(t summary_ready)"
echo " Jellyfin:   http://${CT_IP}:8096"
echo " qBittorrent: http://${CT_IP}:8080"
echo " Prowlarr:   http://${CT_IP}:9696"
echo " Radarr:     http://${CT_IP}:7878"
echo " Sonarr:     http://${CT_IP}:8989"
echo " Lidarr:     http://${CT_IP}:8686"
echo " Bazarr:     http://${CT_IP}:6767"
echo "==================================================="
echo "$(t summary_qbt)"
echo "$(t summary_qbt_note1)"
echo "$(t summary_qbt_note2)"
echo "$(t summary_next_steps)"
echo "==================================================="
