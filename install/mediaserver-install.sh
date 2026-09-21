#!/usr/bin/env bash
# install/mediaserver-install.sh
# Roda DENTRO do LXC. Instala Docker (CLI puro, sem Dockge), sobe a stack via
# docker compose e integra qBittorrent + Prowlarr + Bazarr aos apps *arr via API.
#
# Variáveis esperadas no ambiente (com defaults caso não sejam passadas):
#   MEDIA_PATH   - caminho de mídia dentro do container (default: /mnt/midia)
#   PUID/PGID    - usuário/grupo dos containers (default: 1000/1000)
#   TZ           - timezone (default: America/Sao_Paulo)
#   QBT_PASSWORD - senha da WebUI do qBittorrent (definida por quem rodou
#                  ct/mediaserver.sh; se vier vazia, geramos um fallback
#                  aqui mesmo para não travar uma execução standalone)
#   LANG_CHOICE  - idioma das mensagens ("pt" ou "en"; default: pt), definido
#                  por quem rodou ct/mediaserver.sh
#
# Mensagens ao usuário (echo) são bilíngues via a função t() logo abaixo;
# comentários no código continuam só em português.

set -Eeuo pipefail

# Diagnostico temporario: mostra comando + linha exatos se o script morrer
# por causa do set -e (sem isso, a saida seria totalmente silenciosa).
# TODO: remover depois de validar o teste funcional completo.
trap 'echo ">>> ERRO: comando [$BASH_COMMAND] falhou na linha $LINENO (codigo $?)" >&2' ERR

MEDIA_PATH="${MEDIA_PATH:-/mnt/midia}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
TZ="${TZ:-America/Sao_Paulo}"
QBT_USER="admin"
QBT_PASSWORD="${QBT_PASSWORD:-qbt${RANDOM}${RANDOM}}"
QBT_PASSWORD_SET="no"
SMB_ENABLE="${SMB_ENABLE:-no}"
SMB_USER="${SMB_USER:-}"
SMB_PASSWORD="${SMB_PASSWORD:-}"
SMB_READY="no"
LANG_CHOICE="${LANG_CHOICE:-pt}"
STACK_DIR="/opt/mediaserver"

# ---------- Mensagens (pt-BR / en) ----------
# shellcheck disable=SC2028  # backslashes literais de proposito (caminho UNC do Windows na chave smb_ready); bash echo (sem xpg_echo) nao expande escapes
t() {
    local key="$1"
    if [ "$LANG_CHOICE" = "en" ]; then
        case "$key" in
            updating_system) echo ">> Updating the system..." ;;
            installing_deps) echo ">> Installing dependencies..." ;;
            installing_docker) echo ">> Installing Docker Engine + Compose plugin..." ;;
            creating_folders) echo ">> Creating folder structure..." ;;
            generating_env) echo ">> Generating .env..." ;;
            generating_compose) echo ">> Generating docker-compose.yml..." ;;
            starting_stack) echo ">> Bringing up the stack (docker compose)..." ;;
            applying_qbt_password) echo ">> Applying the final qBittorrent password..." ;;
            qbt_password_ok) echo "  qBittorrent password set successfully." ;;
            qbt_password_manual) echo "  Set the password manually in qBittorrent > Settings > WebUI." ;;
            qbt_temp_not_found) echo "  WARNING: could not find the temporary password in the logs (90s timeout)." ;;
            qbt_temp_not_found_hint) echo "  Set the qBittorrent password manually: docker logs qbittorrent | grep -i password" ;;
            qbt_login_failed) echo "  WARNING: login with the qBittorrent temporary password failed (HTTP $login_http)." ;;
            qbt_setpref_failed) echo "  WARNING: failed to set the final qBittorrent password (HTTP $setpref_http)." ;;
            smb_installing) echo ">> Setting up the SMB network share..." ;;
            smb_skip_no_creds) echo "  WARNING: SMB was enabled but no username/password was provided; skipping the share." ;;
            smb_ready) echo "  SMB share ready (\\\\<container-ip>\\midia)." ;;
            smb_setup_failed) echo "  WARNING: could not fully set up the SMB share. Check manually: systemctl status smbd" ;;
            applying_unified_auth) echo ">> Applying unified login (same qBittorrent user/password) to the *arr apps..." ;;
            unified_auth_ok) echo "  - $app_name: login configured (user: $QBT_USER)." ;;
            unified_auth_fetch_failed) echo "  - WARNING: could not read $app_name's current settings; skipping its login setup (check manually in Settings)." ;;
            unified_auth_failed) echo "  - WARNING: could not configure login on $app_name automatically (HTTP $http_code); set it manually in Settings > General/Authentication." ;;
            waiting_apikeys) echo ">> Waiting for the *arr apps to generate their API keys (can take up to 2 min)..." ;;
            apikey_timeout) echo "WARNING: timeout waiting for the API key at $config_file. Skipping this app's integration." ;;
            skip_app_no_key) echo "  - Skipping $app_name (no API key)" ;;
            skip_app_no_key_prowlarr) echo "  - Skipping $app_name in Prowlarr (no API key)" ;;
            qbt_not_confirmed_warning) echo "  - WARNING: could not confirm the qBittorrent password change; registering $app_name anyway (may need manual adjustment later)." ;;
            connecting_qbt_app) echo "  - Connecting qBittorrent to $app_name..." ;;
            connecting_qbt_all) echo ">> Connecting qBittorrent to the *arr apps..." ;;
            registering_prowlarr_app) echo "  - Registering $app_name as an Application in Prowlarr..." ;;
            syncing_prowlarr) echo ">> Syncing Prowlarr with the *arr apps (Applications)..." ;;
            trying_bazarr) echo ">> Trying to connect Bazarr to Radarr/Sonarr (best-effort, check manually if it fails)..." ;;
            install_done) echo " Installation complete." ;;
            important) echo " IMPORTANT:" ;;
            qbt_summary_ok) echo " 1) qBittorrent - user: ${QBT_USER} / password: ${QBT_PASSWORD}" ;;
            qbt_summary_ok_note) echo "    (also saved to ${STACK_DIR}/.qbittorrent-credentials, permission 600)" ;;
            qbt_summary_fail1) echo " 1) Could NOT confirm the qBittorrent password change automatically." ;;
            qbt_summary_fail2) echo "    Run: docker logs qbittorrent | grep -i password" ;;
            qbt_summary_fail3) echo "    And set this password manually in Settings > WebUI: ${QBT_PASSWORD}" ;;
            smb_summary_ok) echo "    SMB share - user: ${SMB_USER} / password: the one you set during install" ;;
            smb_summary_fail) echo "    WARNING: could not fully set up the SMB share automatically. Check manually: systemctl status smbd" ;;
            unified_auth_summary) echo "    Radarr/Sonarr/Lidarr/Prowlarr/Bazarr now also require login, using the SAME user/password as qBittorrent above (check the warnings above if any app didn't apply it automatically)." ;;
            step2_indexers) echo " 2) Register your private indexers manually in Prowlarr." ;;
            step3_bazarr) echo " 3) Check the Bazarr<->Radarr/Sonarr connection in Settings - the Bazarr API" ;;
            step3_bazarr2) echo "    schema changes between versions and may need manual adjustment." ;;
        esac
    else
        case "$key" in
            updating_system) echo ">> Atualizando o sistema..." ;;
            installing_deps) echo ">> Instalando dependências..." ;;
            installing_docker) echo ">> Instalando Docker Engine + Compose plugin..." ;;
            creating_folders) echo ">> Criando estrutura de pastas..." ;;
            generating_env) echo ">> Gerando .env..." ;;
            generating_compose) echo ">> Gerando docker-compose.yml..." ;;
            starting_stack) echo ">> Subindo a stack (docker compose)..." ;;
            applying_qbt_password) echo ">> Aplicando senha definitiva do qBittorrent..." ;;
            qbt_password_ok) echo "  Senha do qBittorrent definida com sucesso." ;;
            qbt_password_manual) echo "  Configure a senha manualmente em qBittorrent > Settings > WebUI." ;;
            qbt_temp_not_found) echo "  AVISO: não encontrei a senha temporária nos logs (timeout de 90s)." ;;
            qbt_temp_not_found_hint) echo "  Configure a senha do qBittorrent manualmente: docker logs qbittorrent | grep -i password" ;;
            qbt_login_failed) echo "  AVISO: login com a senha temporária do qBittorrent falhou (HTTP $login_http)." ;;
            qbt_setpref_failed) echo "  AVISO: falha ao definir a senha definitiva do qBittorrent (HTTP $setpref_http)." ;;
            smb_installing) echo ">> Configurando o compartilhamento SMB..." ;;
            smb_skip_no_creds) echo "  AVISO: SMB foi ativado mas usuário/senha não foram informados; pulando o compartilhamento." ;;
            smb_ready) echo "  Compartilhamento SMB pronto (\\\\<ip-do-container>\\midia)." ;;
            smb_setup_failed) echo "  AVISO: não consegui configurar o compartilhamento SMB por completo. Confira manualmente: systemctl status smbd" ;;
            applying_unified_auth) echo ">> Aplicando login unificado (mesmo usuário/senha do qBittorrent) nos apps *arr..." ;;
            unified_auth_ok) echo "  - $app_name: login configurado (usuário: $QBT_USER)." ;;
            unified_auth_fetch_failed) echo "  - AVISO: não consegui ler as configurações atuais do $app_name; pulando o login desse app (confira manualmente em Settings)." ;;
            unified_auth_failed) echo "  - AVISO: não consegui configurar o login no $app_name automaticamente (HTTP $http_code); defina manualmente em Settings > General/Authentication." ;;
            waiting_apikeys) echo ">> Aguardando os apps *arr gerarem suas API keys (pode levar até 2 min)..." ;;
            apikey_timeout) echo "AVISO: timeout esperando API key em $config_file. Pulando integração deste app." ;;
            skip_app_no_key) echo "  - Pulando $app_name (sem API key)" ;;
            skip_app_no_key_prowlarr) echo "  - Pulando $app_name no Prowlarr (sem API key)" ;;
            qbt_not_confirmed_warning) echo "  - AVISO: não confirmei a troca de senha do qBittorrent; cadastrando $app_name mesmo assim (pode precisar de ajuste manual depois)." ;;
            connecting_qbt_app) echo "  - Conectando qBittorrent ao $app_name..." ;;
            connecting_qbt_all) echo ">> Conectando qBittorrent aos apps *arr..." ;;
            registering_prowlarr_app) echo "  - Registrando $app_name como Application no Prowlarr..." ;;
            syncing_prowlarr) echo ">> Sincronizando Prowlarr com os apps *arr (Applications)..." ;;
            trying_bazarr) echo ">> Tentando conectar Bazarr ao Radarr/Sonarr (best-effort, confira manualmente se falhar)..." ;;
            install_done) echo " Instalação concluída." ;;
            important) echo " IMPORTANTE:" ;;
            qbt_summary_ok) echo " 1) qBittorrent - usuário: ${QBT_USER} / senha: ${QBT_PASSWORD}" ;;
            qbt_summary_ok_note) echo "    (também salva em ${STACK_DIR}/.qbittorrent-credentials, permissão 600)" ;;
            qbt_summary_fail1) echo " 1) NÃO consegui confirmar a troca de senha do qBittorrent automaticamente." ;;
            qbt_summary_fail2) echo "    Rode: docker logs qbittorrent | grep -i password" ;;
            qbt_summary_fail3) echo "    E defina esta senha manualmente em Settings > WebUI: ${QBT_PASSWORD}" ;;
            smb_summary_ok) echo "    Compartilhamento SMB - usuário: ${SMB_USER} / senha: a que você definiu na instalação" ;;
            smb_summary_fail) echo "    AVISO: não consegui configurar o compartilhamento SMB por completo. Confira manualmente: systemctl status smbd" ;;
            unified_auth_summary) echo "    Radarr/Sonarr/Lidarr/Prowlarr/Bazarr agora também exigem login, usando o MESMO usuário/senha do qBittorrent acima (confira os avisos acima caso algum app não tenha aplicado automaticamente)." ;;
            step2_indexers) echo " 2) Cadastre seus indexers privados manualmente no Prowlarr." ;;
            step3_bazarr) echo " 3) Confira a conexão Bazarr<->Radarr/Sonarr em Settings - o schema da API" ;;
            step3_bazarr2) echo "    do Bazarr muda entre versões e pode precisar de ajuste manual." ;;
        esac
    fi
}

t updating_system
apt-get update -y && apt-get upgrade -y

t installing_deps
apt-get install -y ca-certificates curl gnupg jq

t installing_docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

t creating_folders
mkdir -p "$STACK_DIR"
for app in jellyfin qbittorrent prowlarr radarr sonarr lidarr bazarr flaresolverr; do
    mkdir -p "$STACK_DIR/$app/config"
done
for sub in downloads filmes series musicas; do
    mkdir -p "$MEDIA_PATH/$sub"
done
chown -R "$PUID:$PGID" "$STACK_DIR"
# Nao tentamos chown em $MEDIA_PATH aqui: e um bind mount vindo do host,
# e um container unprivileged nao tem permissao para mudar o dono desses
# arquivos (ver ct/mediaserver.sh, onde isso ja e feito no host antes do
# container subir).

# ---------- Compartilhamento SMB (opcional) ----------
# O usuario do SMB nao precisa ter o MESMO uid dos containers Docker (PUID)
# -- basta pertencer ao MESMO grupo (PGID) e a pasta de midia ser gravavel
# pelo grupo. Isso evita ter que reservar/adivinhar um uid especifico so
# pro Samba (que roda direto no SO do container, fora do Docker).
setup_smb_share() {
    [ "$SMB_ENABLE" != "yes" ] && return
    if [ -z "$SMB_USER" ] || [ -z "$SMB_PASSWORD" ]; then
        t smb_skip_no_creds
        return
    fi

    t smb_installing
    apt-get install -y samba samba-common-bin

    if ! getent group "$PGID" >/dev/null 2>&1; then
        groupadd -g "$PGID" mediashare
    fi

    if ! id -u "$SMB_USER" >/dev/null 2>&1; then
        useradd --no-create-home --shell /usr/sbin/nologin -g "$PGID" "$SMB_USER"
    else
        usermod -g "$PGID" "$SMB_USER"
    fi

    # smbpasswd exige que o usuario do Linux ja exista (acima) antes de
    # aceitar uma senha de Samba pra ele. "-s" le a senha via stdin, em vez
    # de argumento de linha de comando (que ficaria visivel pra qualquer um
    # rodando "ps" enquanto o comando executa).
    if ! printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -a -s "$SMB_USER"; then
        t smb_setup_failed
        return 1
    fi
    smbpasswd -e "$SMB_USER" >/dev/null

    # A pasta de midia ja existe (criada acima com mkdir -p, que por padrao
    # nao da permissao de escrita pro grupo) -- sem isso, o usuario do SMB
    # consegue LER mas nao escrever nada, mesmo sendo do grupo certo.
    chmod -R g+w "$MEDIA_PATH" 2>/dev/null || true

    if ! grep -q "^\[midia\]" /etc/samba/smb.conf 2>/dev/null; then
        cat >> /etc/samba/smb.conf <<SMBCONF

[midia]
   path = ${MEDIA_PATH}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER}
   create mask = 0664
   directory mask = 0775
SMBCONF
    fi

    if ! systemctl enable --now smbd >/dev/null 2>&1 || ! systemctl restart smbd; then
        t smb_setup_failed
        return 1
    fi

    SMB_READY="yes"
    t smb_ready
}

setup_smb_share

t generating_env
cat > "$STACK_DIR/.env" <<EOF
PUID=$PUID
PGID=$PGID
TZ=$TZ
MEDIA_PATH=$MEDIA_PATH
STACK_DIR=$STACK_DIR
EOF

t generating_compose
cat > "$STACK_DIR/docker-compose.yml" <<'COMPOSE'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/jellyfin/config:/config
      - ${MEDIA_PATH}:/data
    devices:
      - /dev/dri:/dev/dri

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8080
    volumes:
      - ${STACK_DIR}/qbittorrent/config:/config
      - ${MEDIA_PATH}:/data

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    restart: unless-stopped
    ports:
      - "9696:9696"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/prowlarr/config:/config

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    restart: unless-stopped
    ports:
      - "7878:7878"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/radarr/config:/config
      - ${MEDIA_PATH}:/data

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    restart: unless-stopped
    ports:
      - "8989:8989"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/sonarr/config:/config
      - ${MEDIA_PATH}:/data

  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    restart: unless-stopped
    ports:
      - "8686:8686"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/lidarr/config:/config
      - ${MEDIA_PATH}:/data

  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: bazarr
    restart: unless-stopped
    ports:
      - "6767:6767"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_DIR}/bazarr/config:/config
      - ${MEDIA_PATH}:/data

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    restart: unless-stopped
    ports:
      - "8191:8191"
    environment:
      - TZ=${TZ}
      - LOG_LEVEL=info
COMPOSE

t starting_stack
cd "$STACK_DIR"
docker compose up -d

# =====================================================================
# Integração via API: qBittorrent -> *arr, Prowlarr -> *arr (Applications)
# =====================================================================

wait_for_apikey() {
    local config_file="$1"
    local timeout=120
    local waited=0
    until [ -f "$config_file" ] && grep -q "<ApiKey>" "$config_file" 2>/dev/null; do
        sleep 3
        waited=$((waited+3))
        if [ "$waited" -ge "$timeout" ]; then
            t apikey_timeout
            return 1
        fi
    done
    grep -oP '(?<=<ApiKey>)[^<]+' "$config_file"
}

# O qBittorrent (a partir da 4.6.1) gera uma senha TEMPORÁRIA aleatória no
# primeiro boot e só mostra ela no log do processo — não dá pra prever, então
# esperamos ela aparecer para depois trocar pela senha definitiva via API.
wait_for_qbt_temp_password() {
    local timeout=90
    local waited=0
    local pass=""
    until [ -n "$pass" ]; do
        pass="$(docker logs qbittorrent 2>&1 | grep -oiP 'temporary password[^:]*:\s*\K\S+' | tail -1 || true)"
        [ -n "$pass" ] && break
        sleep 3
        waited=$((waited+3))
        if [ "$waited" -ge "$timeout" ]; then
            return 1
        fi
    done
    echo "$pass"
}

# Loga na WebUI do qBittorrent com a senha temporária e troca pela senha
# definitiva (QBT_PASSWORD) via API, para que ela bata com o que vamos
# cadastrar no Radarr/Sonarr/Lidarr como download client logo em seguida.
apply_qbt_password() {
    local temp_password="$1"
    local cookie_jar
    cookie_jar="$(mktemp)"

    local login_http
    login_http=$(curl -s -o /dev/null -w "%{http_code}" -c "$cookie_jar" \
        --data-urlencode "username=${QBT_USER}" \
        --data-urlencode "password=${temp_password}" \
        "http://localhost:8080/api/v2/auth/login")

    # A partir do qBittorrent 5.2.0, um login com sucesso passou a responder
    # "204 No Content" (corpo vazio, so o cookie de sessao) em vez do antigo
    # "200 Ok.". Se so aceitarmos 200 aqui, um login que na verdade funcionou
    # e tratado como falha e a senha definitiva nunca chega a ser aplicada
    # (foi exatamente isso que aconteceu no teste real: HTTP 204 == sucesso).
    if [ "$login_http" != "200" ] && [ "$login_http" != "204" ]; then
        t qbt_login_failed
        rm -f "$cookie_jar"
        return 1
    fi

    local setpref_http
    setpref_http=$(curl -s -o /dev/null -w "%{http_code}" -b "$cookie_jar" \
        --data-urlencode "json={\"web_ui_password\":\"${QBT_PASSWORD}\"}" \
        "http://localhost:8080/api/v2/app/setPreferences")
    rm -f "$cookie_jar"

    # Mesmo motivo do login acima: desde o qBittorrent 5.2.0 qualquer endpoint
    # cuja resposta de sucesso nao tem corpo (como este setPreferences) passou
    # a responder 204 em vez de 200 ("WEBAPI: Send 204 when WebAPI response
    # contains no data", release notes 5.2.0).
    if [ "$setpref_http" != "200" ] && [ "$setpref_http" != "204" ]; then
        t qbt_setpref_failed
        return 1
    fi

    return 0
}

t applying_qbt_password
QBT_TEMP_PASSWORD="$(wait_for_qbt_temp_password)" || QBT_TEMP_PASSWORD=""
if [ -n "$QBT_TEMP_PASSWORD" ]; then
    if apply_qbt_password "$QBT_TEMP_PASSWORD"; then
        QBT_PASSWORD_SET="yes"
        t qbt_password_ok
    else
        t qbt_password_manual
    fi
else
    t qbt_temp_not_found
    t qbt_temp_not_found_hint
fi

# Guarda as credenciais num arquivo com permissão restrita — mais seguro do
# que só imprimir no terminal (o log da instalação pode ficar salvo em algum
# lugar por aí). O status (aplicada ou não) também fica registrado.
{
    echo "usuario=${QBT_USER}"
    echo "senha=${QBT_PASSWORD}"
    echo "aplicada_automaticamente=${QBT_PASSWORD_SET}"
} > "${STACK_DIR}/.qbittorrent-credentials"
chmod 600 "${STACK_DIR}/.qbittorrent-credentials"

t waiting_apikeys
RADARR_KEY=$(wait_for_apikey "$STACK_DIR/radarr/config/config.xml") || RADARR_KEY=""
SONARR_KEY=$(wait_for_apikey "$STACK_DIR/sonarr/config/config.xml") || SONARR_KEY=""
LIDARR_KEY=$(wait_for_apikey "$STACK_DIR/lidarr/config/config.xml") || LIDARR_KEY=""
PROWLARR_KEY=$(wait_for_apikey "$STACK_DIR/prowlarr/config/config.xml") || PROWLARR_KEY=""

add_download_client() {
    local app_name="$1" port="$2" api_key="$3" category="$4"
    [ -z "$api_key" ] && { t skip_app_no_key; return; }

    if [ "$QBT_PASSWORD_SET" != "yes" ]; then
        t qbt_not_confirmed_warning
    fi

    t connecting_qbt_app
    curl -s -o /dev/null -w "    HTTP %{http_code}\n" -X POST "http://localhost:${port}/api/v3/downloadclient" \
        -H "X-Api-Key: ${api_key}" -H "Content-Type: application/json" \
        -d "{
            \"enable\": true,
            \"protocol\": \"torrent\",
            \"priority\": 1,
            \"name\": \"qBittorrent\",
            \"implementation\": \"QBittorrent\",
            \"configContract\": \"QBittorrentSettings\",
            \"fields\": [
                {\"name\":\"host\",\"value\":\"qbittorrent\"},
                {\"name\":\"port\",\"value\":8080},
                {\"name\":\"username\",\"value\":\"${QBT_USER}\"},
                {\"name\":\"password\",\"value\":\"${QBT_PASSWORD}\"},
                {\"name\":\"category\",\"value\":\"${category}\"}
            ]
        }" || true
}

add_prowlarr_app() {
    local app_name="$1" impl="$2" contract="$3" port="$4" api_key="$5"
    [ -z "$api_key" ] || [ -z "$PROWLARR_KEY" ] && { t skip_app_no_key_prowlarr; return; }

    t registering_prowlarr_app
    curl -s -o /dev/null -w "    HTTP %{http_code}\n" -X POST "http://localhost:9696/api/v1/applications" \
        -H "X-Api-Key: ${PROWLARR_KEY}" -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${app_name}\",
            \"implementation\": \"${impl}\",
            \"configContract\": \"${contract}\",
            \"syncLevel\": \"fullSync\",
            \"fields\": [
                {\"name\":\"apiKey\",\"value\":\"${api_key}\"},
                {\"name\":\"baseUrl\",\"value\":\"http://${app_name,,}:${port}\"},
                {\"name\":\"prowlarrUrl\",\"value\":\"http://prowlarr:9696\"}
            ],
            \"tags\": []
        }" || true
}

t connecting_qbt_all
add_download_client "Radarr" 7878 "$RADARR_KEY" "radarr"
add_download_client "Sonarr" 8989 "$SONARR_KEY" "sonarr"
add_download_client "Lidarr" 8686 "$LIDARR_KEY" "lidarr"

t syncing_prowlarr
add_prowlarr_app "Radarr" "Radarr" "RadarrSettings" 7878 "$RADARR_KEY"
add_prowlarr_app "Sonarr" "Sonarr" "SonarrSettings" 8989 "$SONARR_KEY"
add_prowlarr_app "Lidarr" "Lidarr" "LidarrSettings" 8686 "$LIDARR_KEY"

# --- Bazarr -> Radarr/Sonarr ---
# OBS: o schema exato da API do Bazarr muda entre versões. Este bloco é best-effort;
# se falhar, configure manualmente em Bazarr > Settings > Radarr/Sonarr (é rápido).
t trying_bazarr
BAZARR_URL="http://localhost:6767"
if [ -n "$RADARR_KEY" ]; then
    curl -s -o /dev/null -w "  Bazarr<->Radarr HTTP %{http_code}\n" -X POST "${BAZARR_URL}/api/system/settings" \
        -H "Content-Type: application/json" \
        -d "{\"settings-general-use_radarr\": true, \"settings-radarr-ip\": \"radarr\", \"settings-radarr-port\": 7878, \"settings-radarr-apikey\": \"${RADARR_KEY}\"}" || true
fi
if [ -n "$SONARR_KEY" ]; then
    curl -s -o /dev/null -w "  Bazarr<->Sonarr HTTP %{http_code}\n" -X POST "${BAZARR_URL}/api/system/settings" \
        -H "Content-Type: application/json" \
        -d "{\"settings-general-use_sonarr\": true, \"settings-sonarr-ip\": \"sonarr\", \"settings-sonarr-port\": 8989, \"settings-sonarr-apikey\": \"${SONARR_KEY}\"}" || true
fi

# =====================================================================
# Login unificado: mesmo usuario/senha do qBittorrent em todos os apps
# =====================================================================

# Radarr, Sonarr, Prowlarr e Lidarr compartilham o mesmo backend (Servarr) e
# o mesmo endpoint config/host -- mas o Lidarr usa API v1, nao v3 (unico
# diferente dos outros dois .NET). O PUT exige o objeto INTEIRO (nao aceita
# alteracao parcial), entao sempre fazemos GET, alteramos so os campos de
# autenticacao em memoria com jq, e mandamos o objeto completo de volta.
#
# O codigo HTTP de sucesso varia: a documentacao desses apps diz 200, mas o
# codigo-fonte deles devolve 202 (Accepted). Por seguranca -- mesma licao do
# bug do HTTP 204 no qBittorrent -- aceitamos qualquer 2xx em vez de travar
# num numero especifico.
apply_servarr_auth() {
    local app_name="$1" base_url="$2" api_version="$3" api_key="$4"
    [ -z "$api_key" ] && { t skip_app_no_key; return 1; }

    local current
    current="$(curl -s -H "X-Api-Key: ${api_key}" "${base_url}/api/${api_version}/config/host")"
    if [ -z "$current" ] || ! echo "$current" | jq -e . >/dev/null 2>&1; then
        t unified_auth_fetch_failed
        return 1
    fi

    local updated
    updated="$(echo "$current" | jq \
        --arg user "$QBT_USER" \
        --arg pass "$QBT_PASSWORD" \
        '.authenticationMethod = "forms" | .authenticationRequired = "enabled" | .username = $user | .password = $pass | .passwordConfirmation = $pass')"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        -H "X-Api-Key: ${api_key}" -H "Content-Type: application/json" \
        -d "$updated" \
        "${base_url}/api/${api_version}/config/host/1")

    case "$http_code" in
        2[0-9][0-9]) t unified_auth_ok ;;
        *) t unified_auth_failed; return 1 ;;
    esac
}

# O Bazarr nao e um app Servarr/.NET -- e Python, com seu proprio endpoint
# de settings, que so aceita corpo form-urlencoded (nao JSON) e so processa
# os campos que vierem no POST (update parcial de verdade, ao contrario do
# config/host acima). O nome do tipo de autenticacao aqui e "form"
# (singular), diferente do "forms" (plural) dos apps Servarr -- reparei
# nisso na hora, ja que e um erro facil de copiar/colar sem querer.
apply_bazarr_auth() {
    local app_name="Bazarr"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BAZARR_URL}/api/system/settings" \
        --data-urlencode "settings-auth-type=form" \
        --data-urlencode "settings-auth-username=${QBT_USER}" \
        --data-urlencode "settings-auth-password=${QBT_PASSWORD}")

    case "$http_code" in
        2[0-9][0-9]) t unified_auth_ok ;;
        *) t unified_auth_failed; return 1 ;;
    esac
}

t applying_unified_auth
apply_servarr_auth "Radarr" "http://localhost:7878" "v3" "$RADARR_KEY" || true
apply_servarr_auth "Sonarr" "http://localhost:8989" "v3" "$SONARR_KEY" || true
apply_servarr_auth "Lidarr" "http://localhost:8686" "v1" "$LIDARR_KEY" || true
apply_servarr_auth "Prowlarr" "http://localhost:9696" "v1" "$PROWLARR_KEY" || true
apply_bazarr_auth || true

echo ""
echo "==================================================="
t install_done
t important
if [ "$QBT_PASSWORD_SET" = "yes" ]; then
    t qbt_summary_ok
    t qbt_summary_ok_note
else
    t qbt_summary_fail1
    t qbt_summary_fail2
    t qbt_summary_fail3
fi
if [ "$SMB_ENABLE" = "yes" ]; then
    if [ "$SMB_READY" = "yes" ]; then
        t smb_summary_ok
    else
        t smb_summary_fail
    fi
fi
t unified_auth_summary
t step2_indexers
t step3_bazarr
t step3_bazarr2
echo "==================================================="
