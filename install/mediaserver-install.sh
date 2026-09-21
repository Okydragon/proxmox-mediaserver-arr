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

set -euo pipefail

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
LANG_CHOICE="${LANG_CHOICE:-pt}"
STACK_DIR="/opt/mediaserver"

# ---------- Mensagens (pt-BR / en) ----------
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
chown -R "$PUID:$PGID" "$STACK_DIR" "$MEDIA_PATH"

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

    if [ "$login_http" != "200" ]; then
        t qbt_login_failed
        rm -f "$cookie_jar"
        return 1
    fi

    local setpref_http
    setpref_http=$(curl -s -o /dev/null -w "%{http_code}" -b "$cookie_jar" \
        --data-urlencode "json={\"web_ui_password\":\"${QBT_PASSWORD}\"}" \
        "http://localhost:8080/api/v2/app/setPreferences")
    rm -f "$cookie_jar"

    if [ "$setpref_http" != "200" ]; then
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
t step2_indexers
t step3_bazarr
t step3_bazarr2
echo "==================================================="
