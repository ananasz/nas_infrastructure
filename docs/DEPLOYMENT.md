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
sudo install -o root -g root -m 0750 rootfs/usr/local/bin/* /usr/local/bin/
sudo systemctl daemon-reload
```

A `.env` fájlok helyben készülnek a `.env.example` alapján, `0600` joggal.

## Első indítás

A külső volume-okat az [átállás](MIGRATION.md) hozza létre.
A `nas-bridge` hálózat már létezik; új gépen: `docker network create nas-bridge`.

```sh
cd /opt/compose/base
sudo renew-internal-certificate.sh --init   # belső DB-cert, az nginx nélküle nem indul
docker compose run --rm --no-deps nginx -t
docker compose up -d
```

Utána tetszőleges sorrendben: `auth`, `media`, `verdaccio`, `registry`, `monitoring`, `immich`, `cetli`, `anachronos`, `vaultwarden`, `crowdsec`
(`cd /opt/compose/STACK && docker compose up -d`). A CrowdSec host-oldali bouncere külön lépés: [CrowdSec](SECURITY.md#telepítés).

Időzítők:

```sh
sudo systemctl enable --now cert-renew.timer registry-retention.timer registry-gc.timer docker-image-prune.timer internal-cert-renew.timer
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

Belépés a fejlesztői gépen és a NAS-on is (a NAS a cetli és anachronos image-ek letöltéséhez):

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

A registry megőrzése: [registry README](../rootfs/opt/compose/registry/README.md).

A frontend image a SPA-t a 80-as porton szolgálja ki, `index.html` fallbackkel,
és tartalmazza a `/.well-known/assetlinks.json` fájlt (`base/configs/conf.d/cetli.conf`).

Ha a NAS saját magáról nem éri el a `docker.ananasz.hu` címet (a router nem támogat hairpin NAT-ot),
a NAS `/etc/hosts` fájljába: `127.0.0.1 docker.ananasz.hu`.

## Alkalmazásdeploy (anachronos)

Az image-eket az anachronos repó `build-docker.bat` szkriptje építi és pusholja
(`anachronos-backend`, `anachronos-frontend`, `latest` és `yyyyMMdd-HHmm-<rev>` tag).
A NAS-on a cetlihez hasonlóan `docker compose pull && docker compose up -d` a `/opt/compose/anachronos` alól;
Induláskor a backend maga futtatja az adatbázis-migrációkat.

### Első telepítés

1. DNS-rekord: `anachronos` (proxied, [Cloudflare](CLOUDFLARE.md)), majd cert ([új domain](CERTIFICATES.md#új-domain)).
2. Titkok (új értékek, ne a helyi fejlesztői vagy a cetli titkai): `openssl rand -hex 32`
   a `POSTGRES_PASSWORD`, `OIDC_CLIENT_SECRET`, `COOKIE_SECRET` értékéhez,
   az `anachronos/.env` fájlba a `.env.example` alapján.
3. A kliens titkának hash-e (a parancs bekéri a nyers `OIDC_CLIENT_SECRET` értéket):

   ```sh
   docker exec -it authelia authelia crypto hash generate pbkdf2 --variant sha512 --iterations 310000
   ```

   A teljes `$pbkdf2-sha512$...` érték az `auth/.env` `ANACHRONOS_CLIENT_SECRET_HASH` mezőjébe, aposztrófok közé,
   majd `cd /opt/compose/auth && docker compose up -d` (új secret, a konténer újralétrejön).
4. Csoport a felhasználónak az Authelia `users_database.yml` fájljában (`authelia-data` volume,
   `docker volume inspect -f '{{ .Mountpoint }}' authelia-data`): `access_anachronos` (felhasználó)
   vagy `admin_anachronos` (admin). Más csoporttal nem lehet belépni; a változás új belépéstől érvényes.
5. Image push a fejlesztői gépről, majd a NAS-on:

   ```sh
   cd /opt/compose/anachronos && docker compose up -d
   cd /opt/compose/base && docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload
   ```

Ellenőrzés: `curl -s -o /dev/null -w '%{http_code}\n' https://chrono.ananasz.hu/api/health/ready` → 200,
a `/api/auth/login?returnTo=%2F` → 302 az Authelia felé; utána böngészős belépés.

A `POSTGRES_PASSWORD` csak az első induláskor állítja be a DB-jelszót; később a Postgresben is módosítani kell.

## Vaultwarden

Publikus a mobil- és asztali kliensek miatt; a `/admin` csak LAN-ról/WireGuardról érhető el
(`base/configs/conf.d/vaultwarden.conf`). Regisztráció kikapcsolva, új fiók csak e-mailes meghívással
([SMTP](EMAIL.md)).

### Első telepítés

1. DNS-rekord: `vw` (DNS only, [Cloudflare](CLOUDFLARE.md)), majd cert ([új domain](CERTIFICATES.md#új-domain)).
2. Admin token: a parancs bekéri a választott admin jelszót, és Argon2-hasht ad:

   ```sh
   docker run --rm -it vaultwarden/server /vaultwarden hash --preset owasp
   ```

   A `$argon2id$...` érték aposztrófok közé a `vaultwarden/.env` `ADMIN_TOKEN` mezőjébe (`0600`),
   mellé az [SMTP-felhasználó](EMAIL.md). Az `/admin` felületen a jelszóval lehet belépni.
3. Indítás és nginx-reload:

   ```sh
   cd /opt/compose/vaultwarden && docker compose up -d
   cd /opt/compose/base && docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload
   ```

4. LAN-ról `https://vw.ananasz.hu/admin` → Users → Invite User; a meghívott a levélben kapott linkkel regisztrál.
5. Bitwardenből: a régi trezorban Export vault (`.json`), a Vaultwarden webes felületén Import data.
   Az attachmenteket az export nem tartalmazza, azokat kézzel kell áttölteni. Utána az exportfájlt töröld.
   A mobilappban belépéskor a régióválasztóban: Self-hosted, szerver URL `https://vw.ananasz.hu`.

Ellenőrzés: kívülről `https://vw.ananasz.hu/alive` → 200, `https://vw.ananasz.hu/admin` → 403.

Az `/admin` felületen mentett beállítások a volume `config.json` fájljába kerülnek, és felülírják
a Compose-ban megadott környezeti változókat. Mentés: [backup](BACKUP.md).

## Adatbázis-elérés (DataGrip)

LAN-ról vagy WireGuardról a `NEV-db.nas:5432` címen. Az nginx zárja le a TLS-t, és a név (SNI) alapján
választja a DB-t (`base/configs/streams.conf`); a `*.nas` neveket a router DNS-e oldja fel.
Ismeretlen névre vagy publikus IP-ről a kapcsolat bontódik. Jelenleg: `anachronos-db.nas`.

DataGrip (PostgreSQL):

- Host `anachronos-db.nas`, port `5432`, adatbázis és felhasználó `anachronos`, jelszó az `anachronos/.env` `POSTGRES_PASSWORD` értéke.
- SSH/SSL fül: SSL bekapcsolva, mód `require` (self-signed cert).
- Advanced fül: `sslNegotiation` = `direct`. Enélkül a kliens előbb titkosítatlanul kér TLS-t, amit az nginx nem ért.

`psql` (17+): `psql "host=anachronos-db.nas port=5432 dbname=anachronos user=anachronos sslmode=require sslnegotiation=direct"`.

Új DB: a konténer a `nas-bridge` hálózatra kerül, a név a `streams.conf` mapjébe és a
`base/configs/internal-tls.cnf` listájába, majd `sudo renew-internal-certificate.sh` a `/opt/compose/base` alól
(új certet készít és reloadol).
