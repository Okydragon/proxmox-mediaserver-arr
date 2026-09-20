# Media Server Stack — script de provisionamento

🇧🇷 Português (este arquivo) | 🇺🇸 [English](README.en.md)

Cria um LXC Debian (12 ou 13, escolhido interativamente a partir do catálogo
mais recente do `pveam`) no Proxmox com Jellyfin + qBittorrent + Prowlarr +
Radarr + Sonarr + Lidarr + Bazarr + Flaresolverr, gerenciados via
`docker compose` puro (sem Dockge, sem Nginx Proxy Manager, sem SwingMusic,
sem Whisparr). O disco de mídia é escolhido entre os já montados no host,
detectados automaticamente (excluindo Ceph e o rootfs).

## Uso

No shell do node Proxmox (como root), a partir da raiz deste repositório:

```bash
bash ct/mediaserver.sh
```

O script pergunta interativamente:
- **Idioma** (Português ou English) — todas as mensagens seguintes saem no
  idioma escolhido
- ID e hostname do container
- Storage e tamanho do rootfs
- CPU / RAM
- **Versão do Debian do template** (lista as majors disponíveis no `pveam`,
  já com a mais recente pré-selecionada)
- **Caminho da mídia no host** — o script detecta os discos/partições já
  montados (excluindo Ceph e o rootfs) e mostra num menu; também dá pra
  digitar um caminho manualmente
- Se deseja GPU passthrough (Intel QuickSync) para o Jellyfin
- Se deseja configurar **IP fixo** para o container em vez de DHCP
  (recomendado se você for colocar um reverse proxy externo na frente depois)
- **Senha da WebUI do qBittorrent** — já vem uma sugestão fácil de digitar
  preenchida (3 palavras + 2 dígitos, ex: `campo-farol-bronze-47`); aceite
  ou digite a sua

Ele então cria o LXC, monta a mídia, instala Docker + Compose plugin dentro
do container e sobe a stack inteira.

## O que é automatizado

- Criação do container e bind mount da mídia
- Instalação do Docker via CLI (sem Dockge)
- Geração do `docker-compose.yml` com todos os apps
- **Integração via API**:
  - Senha da WebUI do qBittorrent trocada da temporária (gerada no primeiro
    boot) para a que você escolheu na instalação — ver aviso abaixo
  - qBittorrent cadastrado como download client no Radarr/Sonarr/Lidarr,
    já com a senha definitiva
  - Radarr/Sonarr/Lidarr sincronizados como Applications no Prowlarr
    (indexers propagam automaticamente depois de cadastrados)
  - Bazarr conectado ao Radarr/Sonarr (best-effort — ver aviso abaixo)

## O que fica manual (de propósito)

- **Indexers privados no Prowlarr** (AmigoShare, Nyaa, etc.) — dependem de
  credenciais/configurações específicas de cada usuário.
- **Conexão Bazarr**: o schema da API do Bazarr muda entre versões — o
  script tenta conectar automaticamente, mas vale conferir em
  Settings > Radarr/Sonarr dentro do Bazarr.

**Sobre a senha do qBittorrent:** desde a versão 4.6.1, o qBittorrent gera
uma senha temporária aleatória no primeiro boot (mudança de segurança da
própria aplicação — não dá mais pra contar com `admin`/`adminadmin` fixo).
O install script espera essa senha aparecer no log do container, faz login
com ela via API e troca pela senha que você escolheu na instalação, usando
essa mesma senha ao cadastrar o qBittorrent como download client nos `*arr`.
Se por algum motivo a troca falhar (timeout esperando o log, por exemplo),
o resumo final do instalador avisa e traz o comando pra pegar a senha
temporária manualmente. A senha definitiva também fica salva, com permissão
`600`, em `/opt/mediaserver/.qbittorrent-credentials` dentro do container.

## Preparando para um Nginx Proxy Manager externo (futuro)

O NPM foi removido desta stack de propósito — hoje o acesso é via Tailscale,
sem necessidade de reverse proxy. Mas o ambiente já fica pronto para o dia em
que você quiser colocar uma instância de NPM **fora deste LXC e fora do
Docker** (em outra VM/LXC, ou em outro host), sem precisar mexer na stack:

- Cada app já publica sua porta em `0.0.0.0` dentro do container (não só em
  `localhost`), então basta o host do NPM ter rota de rede até o IP do
  container — seja pela LAN, seja por um túnel Tailscale — para funcionar
  como "Proxy Host" apontando direto para `<IP-do-container>:<porta>`.
- **Responda "sim" à pergunta de IP fixo** durante a instalação (ou reserve o
  IP por MAC no seu DHCP/router). Isso evita que os Proxy Hosts cadastrados
  no NPM quebrem quando o IP do container mudar.
- Tabela de portas para usar na hora de cadastrar os Proxy Hosts:

  | App         | Porta |
  |-------------|-------|
  | Jellyfin    | 8096  |
  | qBittorrent | 8080  |
  | Prowlarr    | 9696  |
  | Radarr      | 7878  |
  | Sonarr      | 8989  |
  | Lidarr      | 8686  |
  | Bazarr      | 6767  |

- Nada disso exige mudança no `docker-compose.yml` ou nas regras de firewall
  deste script — a única responsabilidade que sobra pra você, na hora, é
  garantir que a rede onde o NPM vai rodar tenha rota até essa LAN (ou até o
  túnel Tailscale, dependendo de onde ele ficar).

## Adaptando para o repositório community-scripts

Este script funciona de forma standalone (chama `pct`/`whiptail` direto).
Para submeter ao [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE),
a lógica de `ct/mediaserver.sh` precisa ser portada para o framework deles
(`build.func`, variáveis padronizadas tipo `$var_os`, `$var_ram` etc.) —
a lógica do `install/mediaserver-install.sh` pode ser reaproveitada quase
como está. Vale conferir o `CONTRIBUTING.md` e um script similar já
mergeado (ex: algum LXC de media stack existente) como referência de
formato antes de abrir o PR.

**Sobre o seletor de idioma:** ele existe só na versão standalone. O
community-scripts/ProxmoxVE segue a convenção de manter todos os scripts em
inglês (o próprio `build.func` já é em inglês), então o PR não deve levar o
seletor de idioma nem a função `t()` — as mensagens portadas pro framework
deles ficam só em inglês, igual ao restante do repositório.

## Estrutura

```
ct/mediaserver.sh              # roda no host Proxmox
install/mediaserver-install.sh # roda dentro do container
```
