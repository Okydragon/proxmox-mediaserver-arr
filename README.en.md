# Media Server Stack — provisioning script

🇧🇷 [Português](README.md) | 🇺🇸 English (this file)

Creates a Debian LXC (12 or 13, chosen interactively from the latest
`pveam` catalog) on Proxmox with Jellyfin + qBittorrent + Prowlarr +
Radarr + Sonarr + Lidarr + Bazarr + Flaresolverr, managed with plain
`docker compose` (no Dockge, no Nginx Proxy Manager, no SwingMusic,
no Whisparr). The media disk is chosen among the ones already mounted
on the host, detected automatically (excluding Ceph and the rootfs).

## Usage

From the Proxmox node shell (as root), from the root of this repository:

```bash
bash ct/mediaserver.sh
```

The script asks interactively for:
- **Language** (Português or English) — every following message is shown
  in the language you pick
- Container ID and hostname
- Storage and rootfs size
- CPU / RAM
- **Debian template version** (lists the major versions available in
  `pveam`, with the latest one pre-selected)
- **Media path on the host** — the script detects the disks/partitions
  already mounted (excluding Ceph and the rootfs) and shows them in a
  menu; you can also type a path manually
- Whether you want GPU passthrough (Intel QuickSync) for Jellyfin
- Whether you want to set up a **fixed IP** for the container instead of
  DHCP (recommended if you're going to put an external reverse proxy in
  front of it later)
- **qBittorrent WebUI password** — an easy-to-type suggestion is already
  filled in (3 words + 2 digits, e.g. `campo-farol-bronze-47`); accept it
  or type your own

It then creates the LXC, mounts the media, installs Docker + the Compose
plugin inside the container, and brings up the whole stack.

## What's automated

- Container creation and media bind mount
- Docker installation via CLI (no Dockge)
- Generating the `docker-compose.yml` with every app
- **API integration**:
  - qBittorrent's WebUI password swapped from the temporary one (generated
    on first boot) to the one you chose during install — see the note below
  - qBittorrent registered as a download client in Radarr/Sonarr/Lidarr,
    already with the final password
  - Radarr/Sonarr/Lidarr synced as Applications in Prowlarr (indexers
    propagate automatically once registered)
  - Bazarr connected to Radarr/Sonarr (best-effort — see the note below)

## What stays manual (on purpose)

- **Private indexers in Prowlarr** (AmigoShare, Nyaa, etc.) — these depend
  on each user's own credentials/settings.
- **Bazarr connection**: the exact Bazarr API schema changes between
  versions — the script tries to connect automatically, but it's worth
  checking under Settings > Radarr/Sonarr inside Bazarr.

**About the qBittorrent password:** since version 4.6.1, qBittorrent
generates a random temporary password on first boot (a security change in
the app itself — you can no longer rely on a fixed `admin`/`adminadmin`).
The install script waits for that password to show up in the container
log, logs in with it via the API, and swaps it for the password you chose
during install, using that same password when registering qBittorrent as
a download client in the `*arr` apps. If the swap fails for some reason
(timeout waiting for the log, for example), the installer's final summary
warns you and gives you the command to grab the temporary password
manually. The final password is also saved, with `600` permissions, at
`/opt/mediaserver/.qbittorrent-credentials` inside the container.

## Preparing for an external Nginx Proxy Manager (future)

NPM was removed from this stack on purpose — access today is via
Tailscale, with no need for a reverse proxy. But the environment is
already set up for the day you want to put an NPM instance **outside this
LXC and outside Docker** (on another VM/LXC, or another host), without
having to touch the stack:

- Each app already publishes its port on `0.0.0.0` inside the container
  (not just on `localhost`), so all the NPM host needs is a network route
  to the container's IP — whether over the LAN or a Tailscale tunnel — to
  work as a "Proxy Host" pointing directly at
  `<container-IP>:<port>`.
- **Answer "yes" to the fixed IP question** during install (or reserve the
  IP by MAC on your DHCP/router). This keeps the Proxy Hosts registered in
  NPM from breaking when the container's IP changes.
- Port table to use when registering the Proxy Hosts:

  | App         | Port  |
  |-------------|-------|
  | Jellyfin    | 8096  |
  | qBittorrent | 8080  |
  | Prowlarr    | 9696  |
  | Radarr      | 7878  |
  | Sonarr      | 8989  |
  | Lidarr      | 8686  |
  | Bazarr      | 6767  |

- None of this requires any change to the `docker-compose.yml` or to this
  script's firewall rules — the only thing left for you to do, at that
  point, is make sure the network the NPM will run on has a route to that
  LAN (or to the Tailscale tunnel, depending on where it ends up).

## Adapting for the community-scripts repository

This script works standalone (it calls `pct`/`whiptail` directly). To
submit it to
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE),
the logic in `ct/mediaserver.sh` needs to be ported to their framework
(`build.func`, standardized variables like `$var_os`, `$var_ram`, etc.) —
the logic in `install/mediaserver-install.sh` can be reused almost as-is.
It's worth checking their `CONTRIBUTING.md` and an already-merged, similar
script (e.g. an existing media-stack LXC) as a format reference before
opening the PR.

**About the language selector:** it only exists in the standalone version.
community-scripts/ProxmoxVE follows the convention of keeping every script
in English (`build.func` itself is in English), so the PR should not carry
the language selector or the `t()` function over — the messages ported to
their framework stay English-only, matching the rest of the repository.

## Structure

```
ct/mediaserver.sh              # runs on the Proxmox host
install/mediaserver-install.sh # runs inside the container
```
