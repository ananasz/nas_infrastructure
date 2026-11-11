# Átállás a régi elrendezésről

Régi állapot: egy `nas-stack` projekt a `/nas-data/config/docker-compose.yml` fájlból,
bind mountokkal és secretfájlokkal, plusz a `/opt/cetli` stack. Az új stackek ugyanazokat a
konténerneveket használják, ezért a régi konténereket előbb el kell távolítani.

A két script a régi fájlokat nem módosítja és nem törli; visszaálláshoz a régi stack újraindítható.
Az új adatvolume-ok prefix nélküli nevet kapnak (pl. `jellyfin-config`); ha egy már létezik, a script megáll.

Megszűnik: `homepage`, `uptime-kuma`, `glances` (helyettük a [monitoring](MONITORING.md)),
a saját nginx-image (helyette `nginx` + `certbot` konténer), a nginx fájlba írt logjai (stdout → Loki),
a használaton kívüli `img_cache` proxy cache és a `cetli-web-static` volume (helyette frontend image).

## 1. Előkészítés (a régi stack fut)

DNS-rekord (DNS only) a `docker.ananasz.hu` és `photos.ananasz.hu` névre, majd certek a még futó régi nginxszel:

```sh
docker exec nginx certbot certonly --nginx -d docker.ananasz.hu
docker exec nginx certbot certonly --nginx -d photos.ananasz.hu
```

Az Immich-fotótár könyvtára a ZFS-poolon (külön datasetként is létrehozható):

```sh
sudo mkdir /nas-data/zfs-pool/photos
```

[Fájlok másolása](DEPLOYMENT.md#fájlok-másolása), majd a repó gyökeréből:

```sh
sudo bash migration/01-secrets-to-env.sh
```

A titkok a `/opt/compose/auth/.env` és `/opt/compose/cetli/.env` fájlba kerülnek
(a cetli meglévő `.env`-je is átjön). A fájlvégi egy sortörés elmarad.
A `/opt/compose/base/.env` ([registry-belépés](DEPLOYMENT.md#registry-belépés)), `monitoring/.env` és `immich/.env` kézzel készül a minta alapján.
Ellenőrzés stackenként: `docker compose config --quiet`.

## 2. Leállás és adatmásolás

```sh
cd /nas-data/config && docker compose down
cd /opt/cetli && docker compose down
cd /path/to/repo
sudo bash migration/02-binds-to-volumes.sh --dry-run
sudo bash migration/02-binds-to-volumes.sh
```

A `cetli_cetli-db-data` volume megmarad, az új `cetli` stack ugyanazt használja.
A `/nas-data/cache/jellyfin` nem másolódik, a Jellyfin újraépíti.

## 3. Indítás

[Első indítás](DEPLOYMENT.md#első-indítás): `base`, `auth`, `media`, `verdaccio`, `registry`, `monitoring`, `immich`.
Ezután a fejlesztői gépről pushold a `cetli-backend` és `cetli-frontend` image-et,
majd indítsd a `cetli` stacket.

Ellenőrzés:

- publikus nevek: `fs`, `fin`, `seer`, `auth`, `registry`, `cetli`, `api.cetli`, `photos`;
- Cetli-belépés Autheliával (OIDC kulcs, client secret, storage key egyezik);
- `*.nas` felületek LAN-ról és WireGuardról; `qb.ananasz.hu` kívülről 403;
- `cd /opt/compose/base && sh scripts/renew-certificates.sh --dry-run`;
- Grafana: `http://grafana.nas`, Disks dashboardon a lemezek.

Az Authelia nem indul, ha a `STORAGE_ENCRYPTION_KEY` eltér; ilyenkor a `.env` értékét
vesd össze a régi fájllal (pl. sortörés a kulcsban).

## Visszaállás

```sh
for s in cetli immich monitoring registry verdaccio media auth base; do (cd /opt/compose/$s && docker compose down); done
cd /nas-data/config && docker compose up -d
cd /opt/cetli && docker compose up -d
```

Az átállás óta az új volume-okba írt változások (pl. Jellyfin-nézettség) ilyenkor elvesznek.

## Takarítás az ellenőrzés után

- régi könyvtárak: `/nas-data/config`, `/nas-data/container-data`, `/nas-data/cache/jellyfin`, `/opt/cetli`
  (a secretfájlokkal együtt; előtte egy tömörített mentés javasolt);
- `docker volume rm nas-stack_cetli-web-static`, a régi saját nginx-image: `docker image prune`;
- megszűnt certek (`kuma`, `genyer`, `kutya.poc`, `quantumsoul.poc`; a pontos nevek a `certbot certificates` listában):
  `docker compose run --rm --no-deps certbot delete --cert-name CERT_NAME`
  ([törlés](CERTIFICATES.md#törlés)).
