# Telepítés és frissítés

A `rootfs/` fájljai az azonos szerverútvonalra kerülnek. A parancsok a NAS-on,
rootként vagy Docker-jogosultságú felhasználóval futnak.
A meglévő projekt-, hálózat- és volume-neveket, a helyi `.env` fájlokat őrizd meg;
adatmegőrzéshez `down -v` nem használható.

## Fájlok másolása

A repó gyökeréből (például egy szerveren lévő checkoutból):

```sh
sudo rsync -a --exclude .env rootfs/opt/compose/ /opt/compose/
sudo install -o root -g root -m 0644 rootfs/etc/systemd/system/* /etc/systemd/system/
sudo systemctl daemon-reload
```

A `.env` fájlok helyben készülnek a `.env.example` alapján, `0600` joggal.

## Első indítás

A külső volume-okat az [átállás](MIGRATION.md) hozza létre.
A `nas-bridge` hálózat már létezik; új gépen: `docker network create nas-bridge`.

```sh
cd /opt/compose/base
docker compose run --rm --no-deps nginx -t
docker compose up -d
```

Utána tetszőleges sorrendben: `auth`, `media`, `verdaccio`, `registry`, `monitoring`, `immich`, `cetli`
(`cd /opt/compose/STACK && docker compose up -d`).

Időzítők:

```sh
sudo systemctl enable --now cert-renew.timer registry-retention.timer registry-gc.timer docker-image-prune.timer
```

## Frissítés

Egy szolgáltatás image-frissítése, a stack könyvtárából:

```sh
docker compose pull jellyfin
docker compose up -d jellyfin
```

Nginx-konfig változásakor:

```sh
cd /opt/compose/base
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

Mount-, hálózat- és Compose-változáshoz `docker compose up -d` (újralétrehozza az érintett konténert).
A `latest` image-ek frissítése verzióváltás is lehet; nagyobb frissítés előtt nézd meg a kiadási jegyzetet.
Az Immich főverzió-váltásánál az `immich/compose.yml` fájlt is össze kell vetni a kiadás hivatalos
`docker-compose.yml`-jével (DB- és Valkey-image, kötelező beállítások).

## Registry-belépés

A `docker.ananasz.hu` csak privát IP-ről és bejelentkezve érhető el (nginx basic auth).
A hash elkészítése bárhol, ahol van Docker (a jelszót bekéri):

```sh
docker run --rm -it httpd:2.4-alpine htpasswd -nB USER
```

A kimenetet egy sorban, aposztrófok közé a NAS `/opt/compose/base/.env` fájljába
(`REGISTRY_HTPASSWD='USER:$2y$05$...'`, `0600`), majd a `/opt/compose/base` könyvtárból:

```sh
docker compose up -d nginx
```

Belépés a fejlesztői gépen és a NAS-on is (a NAS a cetli image-ek letöltéséhez):

```sh
docker login docker.ananasz.hu
```

A registry UI (`http://docker.nas`) és a retention job a belső hálón, nginx nélkül éri el a registryt.

## Alkalmazásdeploy (cetli)

Fejlesztői gépen, LAN-ról vagy WireGuardon keresztül:

```sh
docker build -t docker.ananasz.hu/cetli-backend:latest -f backend/Dockerfile .
docker push docker.ananasz.hu/cetli-backend:latest
```

A NAS-on:

```sh
cd /opt/compose/cetli
docker compose pull
docker compose up -d
```

Visszaálláshoz egyedi taget is érdemes pusholni (pl. git hash), és azt a
`cetli/.env` `CETLI_BACKEND_TAG` / `CETLI_FRONTEND_TAG` értékében megadni.
A registry megőrzése: [registry README](../rootfs/opt/compose/registry/README.md).

A frontend image a SPA-t a 80-as porton szolgálja ki, `index.html` fallbackkel,
és tartalmazza a `/.well-known/assetlinks.json` fájlt (`base/configs/conf.d/cetli.conf`).

Ha a NAS saját magáról nem éri el a `docker.ananasz.hu` címet (a router nem támogat hairpin NAT-ot),
a NAS `/etc/hosts` fájljába: `127.0.0.1 docker.ananasz.hu`.
