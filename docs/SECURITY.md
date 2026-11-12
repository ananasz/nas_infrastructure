# CrowdSec

A `crowdsec` stack a konténerlogokból ismeri fel a támadásokat, a hoston futó firewall bouncer
pedig nftables-szel eldobja a kitiltott IP-k csomagjait. A közösségi blokklista (CAPI) is ide érkezik.

| Rész | Hol | Feladat |
| --- | --- | --- |
| `crowdsec` konténer | `/opt/compose/crowdsec` | logolvasás a Docker API-n át, scenariók, döntések (LAPI, SQLite) |
| `crowdsec-firewall-bouncer-nftables` | host, systemd | a döntések nftables-szetté alakítása (`input` és `forward` hook) |
| Grafana | `http://grafana.nas`, CrowdSec dashboard | állapot, tiltások, észlelések, logok |

## Mit figyel

| Konténer | Parser / collection | Mire tilt |
| --- | --- | --- |
| `nginx` | helyi `nas/nginx-json-logs`, `crowdsecurity/base-http-scenarios`, `http-cve` | szkennelés, ismert sérülékenységek próbálgatása, rossz user agentek, admin-felületek keresése |
| `authelia` | `LePresidente/authelia` | sikertelen belépések sorozata |
| `vaultwarden` | `Dominic-Wagner/vaultwarden` | hibás jelszó, admin token, 2FA-kód |

- Az nginx JSON-ban logol (`base/configs/nginx.conf`), amit a hivatalos `crowdsecurity/nginx-logs` nem ért;
  a helyi parser (`crowdsec/configs/parsers/s01-parse/`) ugyanazokat a mezőket tölti ki, így a hub HTTP-scenariói működnek.
  A log `$uri`-t tartalmaz query string nélkül (tokenek ne kerüljenek a Lokiba),
  ezért a paraméterekre épülő SQLi/XSS-scenariók nem jeleznek.
- A `nas/whitelist` a privát tartományokat (LAN, WireGuard, Docker) és a Cloudflare-tartományokat soha nem tiltja.
- Az SSH csak LAN/WG-ről érhető el, ezért nincs figyelve. Jellyfinhez és Immichhez is van hub-collection;
  igény esetén új acquisition-fájl kell (`configs/acquis.d/`), a konténer nevével és a collection által várt `type` címkével.
- Az Authelia saját kitiltása (regulation) megmarad; a CrowdSec ezt hálózati szinten egészíti ki.

## Hatókör: Cloudflare

A tiltás a hoston történik, így a **DNS only** neveknél (`fin`, `photos`, `vw`, `fs`, `docker`, `qb`)
és a közvetlenül a publikus IP-t szkennelőknél hatásos.
A **proxied** neveknél (`auth`, `cetli`, `anachronos`, `seer`, `registry`) a TCP-kapcsolat a Cloudflare-től jön,
a valódi kliens címe csak a `CF-Connecting-IP` HTTP-fejlécben van. Az észlelés és a döntés ezért a valódi IP-re szól
(`cloudflare-real-ip.conf`), de a host tűzfala csak a csomag forráscímét látja, a fejlécet nem:
a kitiltott kliens a Cloudflare-en át továbbra is eléri ezeket a neveket.
Ezeken a tiltást a Cloudflare WAF-szabályai adják ([Cloudflare](CLOUDFLARE.md)).

A Cloudflare-tartományok fehérlistája nem ennek a kerülőútja, hanem biztosíték: ha egy esemény valamiért
a Cloudflare címével kerülne be (pl. fejléc nélküli kérés), a tűzfal az összes proxied forgalmat eldobná.

Ha ez kevés: Cloudflare Worker bouncer, amely a döntéseket a Cloudflare-re viszi.
Ingyenes csomagban korlátos (napi 1000 KV-írás, kb. 1000 IP-s kezdő lista, napi 100 ezer worker-kérés,
utána a védelem kimarad), és a worker-route-okat kézzel Fail Openre kell állítani; most nem javasolt.

## Felületek

Külön felület nem kell, publikus aldomain pedig kifejezetten nem:

- A LAPI (8080) és a metrika (6060) csak a host loopbackjén érhető el; a bouncer és az Alloy innen éri el.
  Kifelé nyitott LAPI-val bárki döntéseket kérdezhetne le vagy kulcsot próbálgathatna.
- A CrowdSecnek nincs saját webes felülete (a régi Metabase-dashboard megszűnt). Napi használat: `cscli` és a Grafana-dashboard.
- Opcionális: **CrowdSec Console** (`app.crowdsec.net`, ingyenes fiók). A NAS csak kifelé kapcsolódik,
  portot nem kell nyitni; riasztáslista, térkép, blokklista-feliratkozások. A `.env` `ENROLL_KEY` értékével
  induláskor regisztrál, a Console-ban el kell fogadni.

## Telepítés

1. Bouncer-kulcs: `openssl rand -hex 32`, a `crowdsec/.env` `BOUNCER_KEY_FIREWALL` mezőjébe (`.env.example` alapján, `0600`).
2. Vaultwarden logformátum (`LOG_TIMESTAMP_FORMAT`, időzónával):

   ```sh
   cd /opt/compose/vaultwarden && docker compose up -d
   ```

   Ha az `/admin` felületen valaha mentettél beállítást, a `config.json` felülírja a környezeti változót;
   ilyenkor az Advanced Settings → Log timestamp format mezőben is `%Y-%m-%d %H:%M:%S.%3f%z` legyen.
3. CrowdSec:

   ```sh
   cd /opt/compose/crowdsec && docker compose up -d
   docker compose logs -f crowdsec   # első indításkor letölti a hub-elemeket
   ```

4. Firewall bouncer a hoston (a hivatalos csomagtároló, majd a nftables-változat):

   ```sh
   curl -s https://install.crowdsec.net | sudo sh
   sudo apt install crowdsec-firewall-bouncer-nftables
   ```

   A csomag a hoston nem talál `cscli`-t, ezért a kulcsot kézzel kell beírni.
   A `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml` fájlban `api_key:` = az 1. lépés kulcsa (`0600`).
   A repó beállításai a `.local` fájlban vannak, ez a csomagfájl fölé olvad:

   ```sh
   sudo install -o root -g root -m 0600 rootfs/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local /etc/crowdsec/bouncers/
   sudo systemctl enable --now crowdsec-firewall-bouncer
   sudo systemctl restart crowdsec-firewall-bouncer
   ```

   A Docker publikált portjai (80/443, 5432, qBittorrent) DNAT után a `forward` hookon mennek át,
   ezért kell az `input` mellett a `forward` is; az nftables-ben a `drop` a Docker saját szabályaitól függetlenül végleges.
5. Monitoring: `cd /opt/compose/monitoring && docker compose restart alloy`; a dashboardot a Grafana magától betölti.
6. Heti hub-frissítés: `sudo systemctl enable --now crowdsec-hub-upgrade.timer` (a unitokat a [telepítés](DEPLOYMENT.md#fájlok-másolása) másolja).

## Ellenőrzés

```sh
docker exec crowdsec cscli bouncers list        # firewall: friss "Last API pull"
docker exec crowdsec cscli metrics              # Acquisition: nginx/authelia/vaultwarden sorok, Parsers: hits
sudo nft list table ip crowdsec                 # input és forward lánc; szett és drop-szabály csak az első döntéstől
docker exec crowdsec cscli capi status          # közösségi blokklista: regisztráció, utolsó letöltés
```

A helyi nginx-parser próbája:

```sh
docker exec crowdsec cscli explain --type nas-nginx \
  --log '{"time":"2026-11-12T10:00:00+01:00","host":"fin.ananasz.hu","ip":"203.0.113.10","method":"GET","uri":"/.env","status":404,"request_id":"x","request_time":0.001,"upstream_time":"","upstream_status":"","bytes_sent":0,"agent":"curl/8"}'
```

Mindkét szakaszban (`s01-parse`: `nas/nginx-json-logs`, `s02-enrich`: `crowdsecurity/http-logs`) zöld pipa várható.

Tiltás próbája egy LAN-on kívüli géppel (pl. telefon mobilneten): `docker exec crowdsec cscli decisions add --ip IP --duration 5m`,
majd a `https://fin.ananasz.hu` nem tölt be; `cscli decisions delete --ip IP`.

## Napi használat

```sh
docker exec crowdsec cscli alerts list                  # helyi észlelések
docker exec crowdsec cscli decisions list               # helyi tiltások (a CAPI-listához: --origin CAPI / lists)
docker exec crowdsec cscli decisions delete --ip IP     # feloldás
```

A hub-elemeket (parserek, scenariók, adatfájlok) a `crowdsec-hub-upgrade.timer` hetente frissíti,
majd újraindítja a konténert; a helyi `nas/*` elemekhez nem nyúl, a döntések megmaradnak.
Kézzel, például egy friss CVE-scenario miatt: `sudo systemctl start crowdsec-hub-upgrade.service`.
Napló: `journalctl -u crowdsec-hub-upgrade.service`.

Ha valaki magát tiltja ki: LAN-ról vagy WireGuardról a tiltás nem érvényes (a privát címek fehérlistán vannak),
onnan feloldható. Tartós kivételhez (pl. egy rendszeresen használt publikus IP) `cscli allowlists`.

Az image verziója rögzített (`crowdsec/compose.yml`); frissítés előtt a kiadási jegyzet,
a bouncer az `apt` frissítésekkel jön. A döntések és riasztások nem kerülnek mentésbe: újraépíthetők.
