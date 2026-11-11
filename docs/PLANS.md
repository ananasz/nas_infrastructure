# Tervek és javaslatok

Ezek még nincsenek megvalósítva; működő konfiguráció nem tartozik hozzájuk.

## Új szolgáltatások

- **Vaultwarden**: saját stack, SQLite volume-mal; admin token a `.env`-ben.
  Publikus elérésnél a `/admin` csak LAN-ról (`lan-allow.conf`).

## A NAS költöztetése után

A helyi hálózaton lévő eszközökhöz kötődnek, ezért csak a NAS új helyén érdemesek.

- **Frigate (NVR)**: 7 PoE kamera helyben rögzítve, a gyártói felhő helyett.
  Külön, dedikált HDD-k a felvételeknek (nem a ZFS média-pool). A kamerák külön VLAN-ba,
  internetelérés nélkül; távoli elérés a Frigate felületén keresztül.
  Detektálás: Intel iGPU (OpenVINO), dekódolás VAAPI/QSV.
- **Home Assistant**: host-hálózattal a helyi eszközök felderítéséhez; Zigbee/Z-Wave esetén USB-rádió.
- **AdGuard Home**: a router DHCP-je osztja ki DNS-nek, tartalék DNS-sel; átveheti a `*.nas` nevek feloldását.

GPU: az i5-12500 UHD 770 iGPU-ja (QSV/VAAPI, AV1-dekódolás, OpenVINO) a Jellyfin, Immich
és Frigate közös gyorsítója; dedikált NVIDIA kártya nem tervezett, mert a host-driver
és a container toolkit karbantartását, valamint állandó üresjárati fogyasztást jelent.

## Mentés (filen.io)

Javasolt: [restic](https://restic.net/) vagy Kopia titkosított, deduplikált tárolója a Filenen,
systemd timerrel. A Filen elérése rclone-on vagy a Filen CLI S3/WebDAV-szerverén keresztül
lehetséges; a pontos módot telepítés előtt ellenőrizni kell.

Mentendő: a Docker volume-ok (DB-knél előtte dump: CouchDB, anaChronos Postgres (`pg_dump`), Vaultwarden SQLite; az Immich naponta
maga dumpol a `photos/backups` alá),
`/opt/compose/*/.env`, a ZFS-pool fontos része (fotók; a média jellemzően nem).
A mentés sikerességét figyelni kell (pl. Grafana-riasztás vagy healthchecks-ping),
és időnként visszaállítási próba javasolt.

## Biztonság

- **CrowdSec** (fail2ban helyett/mellett): az nginx-logot a Docker-logokból olvassa,
  a `crowdsec-firewall-bouncer` a hoston tilt. Docker-portoknál a `DOCKER-USER` láncot is kezelnie kell.
  A közösségi blokklisták miatt hasznosabb, mint a fail2ban; ez utóbbi csak publikus SSH esetén kellene.
- Authelia: a beépített regulation (kitiltás hibás belépések után) alapból aktív;
  2FA (TOTP/WebAuthn) bekapcsolása javasolt.
- A publikusan elérhető felületek: Jellyfin, Jellyseerr, Immich, Authelia, Verdaccio, Cetli, anaChronos, fs.
  Ami nem kell kívülről, kerüljön a `lan-allow.conf` mögé.
- `unattended-upgrades` a hoston, SSH csak kulccsal és csak LAN/WireGuardról.

## Egységes belépés Autheliával

Két mód: **OIDC** (a szolgáltatás maga támogatja, a mobilkliensek is működhetnek) és
**forward auth** (nginx `auth_request` az Authelia felé, a szolgáltatás saját belépése kikapcsolva).
Forward auth csak böngészős felületnél jó; API-t vagy natív klienst használó útvonalakat
(pl. `/api` API-kulccsal) Authelia-szabállyal ki kell venni alóla.
Az Authelia sütije az `ananasz.hu` domainhez és HTTPS-hez kötött, ezért a `*.nas` nevek alatt nem használható;
a védett felületek `*.ananasz.hu` nevet kapnak. Adminfelületekhez `two_factor` szabály.

| Szolgáltatás | Mód | Saját belépés kikapcsolható |
| --- | --- | --- |
| Grafana | OIDC vagy auth proxy | igen (login form tiltható) |
| Immich | OIDC, mobilappal is | igen (jelszavas belépés tiltható) |
| Sonarr, Radarr, Prowlarr | forward auth, `AuthenticationMethod=External` | igen; `/api` kivétel a mobilappoknak |
| Bazarr | forward auth | igen (auth: none); `/api` kivétel |
| qBittorrent | forward auth + IP-whitelist a belépés megkerülésére | részben; az *arr-ok a belső hálón kapcsolódnak |
| Registry UI, Frigate, AdGuard Home | forward auth (Frigate: proxy-fejléc alapú felhasználó) | igen |
| Portainer CE | OAuth vagy forward auth | nem; a helyi admin megmarad |
| Jellyseerr | forward auth csak plusz rétegként | nem; Jellyfin-fiókkal lép be |
| Jellyfin | SSO-plugin (csak webes) | nem; a TV-/mobilkliensek saját belépést igényelnek |
| Vaultwarden | SSO (OIDC) | nem; a master password a titkosítás kulcsa |
| Home Assistant | csak közösségi integrációval | nem; a mobilapp saját belépést igényel |
| Verdaccio | — | nem; az npm CLI tokennel/jelszóval lép be |
| Docker registry | — | nem; IP-korlátozás marad (opcionálisan htpasswd) |

## Riasztások

Grafana alerting értesítési csatornával (pl. saját ntfy, Telegram vagy e-mail):
SMART-hiba vagy növekvő hibás szektorszám, lemezhőmérséklet, ZFS pool nem `online`,
fájlrendszer 90% fölött, `up == 0`, sikertelen cert-megújítás vagy mentés.

## További ötletek

- ZFS: rendszeres scrub (Debianon a `zfsutils-linux` alapból havonta futtatja) és snapshotok (sanoid).
- `smartd` a hoston időzített rövid/hosszú self-testekkel.
- Image-frissítési értesítés: Diun (automatikus frissítés helyett).
- Igény szerint: Paperless-ngx, Syncthing.

## Ansible TeamCity nélkül

A `rootfs/` szerkezet jól illeszkedik egy szerepkörhöz: fájlok másolása, `.env` sablon
ansible-vaultból, `community.docker.docker_compose_v2` a stackekhez, handlerrel nginx-reload.

| Mód | Előny | Hátrány |
| --- | --- | --- |
| Futtatás a fejlesztői gépről (WSL), `--check --diff`, majd élesben | Legegyszerűbb, mindig kézben van | Kézi indítás |
| `ansible-pull` systemd timerrel a NAS-on | Git-push után magától frissül | Deploy kulcs és vault-jelszó a NAS-on |
| Git-szolgáltatás CI-ja (GitHub/Forgejo Actions) saját runnerrel | Push-ra fut, naplózott | Runner üzemeltetése |
| Semaphore UI konténerben | Webes futtatás, ütemezés, napló | Még egy szolgáltatás |

Javaslat: első lépésként kézi futtatás a fejlesztői gépről; ha automatizmus kell, `ansible-pull` timer.
