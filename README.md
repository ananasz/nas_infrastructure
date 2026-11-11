# NAS infrastruktúra

Az otthoni NAS konfigurációja. A `rootfs/` a szerver `/` könyvtárát követi.
Valódi titok és futás közbeni adat nem kerül gitbe; a nyers szervermásolatok helye `.local/`.

## Tárolás

| Hely | Lemez | Tartalom |
| --- | --- | --- |
| `/nas-data/zfs-pool/` | ZFS (HDD) | `media`, `incomplete`, `nginx-served`, `photos`; fix útvonal, bind volume-ként csatolva |
| Docker named volume-ok | SSD | szolgáltatások konfigurációja, adatbázisai, cache-ek, certek |
| `/opt/compose/<stack>/` | SSD | Compose-fájlok, repóban kezelt konfigurációk, `.env` |

## Stackek (`/opt/compose/`)

Minden stack a közös, külső `nas-bridge` hálózaton éri el az nginxet.

| Stack | Szolgáltatások | Elérés |
| --- | --- | --- |
| `base` | nginx, certbot, Portainer | `http://portainer.nas` |
| `auth` | Authelia | `https://auth.ananasz.hu` |
| `media` | Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, qBittorrent, Jellyseerr | `fin`, `seer` publikus; `*.nas` |
| `verdaccio` | npm registry | `https://registry.ananasz.hu` |
| `registry` | Docker registry + UI | `https://docker.ananasz.hu` (LAN/WG), `http://docker.nas` |
| `monitoring` | Grafana, Loki, VictoriaMetrics, Alloy, cAdvisor, smartctl-exporter | `http://grafana.nas` |
| `immich` | Immich (server, ML, Postgres, Valkey) | `https://photos.ananasz.hu` |
| `cetli` | CouchDB, backend, frontend | `https://cetli.ananasz.hu`, `https://api.cetli.ananasz.hu` |
| `anachronos` | Postgres, backend, web | `https://chrono.ananasz.hu` |

A `*.nas` vhostok, a `*-db.nas:5432` DB-elérés és a `qb.ananasz.hu`, `docker.ananasz.hu` csak privát IP-ről
(LAN, WireGuard) érhetők el: `base/configs/snippets/lan-allow.conf`.

## Leírások

- [Telepítés, frissítés, alkalmazásdeploy](docs/DEPLOYMENT.md)
- [Átállás a régi elrendezésről](docs/MIGRATION.md)
- [Tanúsítványok](docs/CERTIFICATES.md), [Cloudflare DNS/proxy](docs/CLOUDFLARE.md), [registry karbantartás](rootfs/opt/compose/registry/README.md)
- [Monitoring](docs/MONITORING.md)
- [Tervek és javaslatok](docs/PLANS.md)
