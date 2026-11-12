# Cloudflare DNS és proxy

A DNS a Cloudflare-nél van. A narancs (proxied) rekordok forgalma a Cloudflare-en megy át,
a szürke (DNS only) rekordok közvetlenül a NAS publikus IP-jére mutatnak.

| Név | Mód | Ok |
| --- | --- | --- |
| `auth` | proxied | belépési oldal: WAF, bot- és rate-limit szabályok |
| `cetli`, `api.cetli` | proxied | kis kérések; a 60 s-os long-poll belefér a 100 s-os Cloudflare-limitbe |
| `anachronos` | proxied | kis kérések; az SSE 25 s-os heartbeatje belefér a 100 s-os limitbe |
| `seer` | proxied | sima webes felület |
| `registry` (Verdaccio) | proxied | kis csomagok; a 100 MB-os feltöltési limit megegyezik az nginx-limittel |
| `fin` | DNS only | videostreamelés: a Cloudflare feltételei tiltják a nagy videóforgalmat a CDN-en |
| `photos` | DNS only | ingyenes csomagban 100 MB a kérésméret-limit, a videók feltöltése elakadna |
| `vw` | DNS only | a `/admin` csak privát IP-ről érhető el, ami proxyn át nem teljesülne; nincs 100 MB-os attachmentlimit |
| `fs` | DNS only | nagy letöltések; csak kis fájloknál érdemes proxyzni |
| `docker` | DNS only | csak privát IP-ről érhető el (`lan-allow.conf`), a rétegek 100 MB fölöttiek |
| `qb` | DNS only | csak privát IP-ről érhető el; a rekord törölhető is, a `qb.nas` megmarad |

Mivel a DNS only rekordok úgyis megmutatják az otthoni IP-t, a proxy nem rejti el a szervert.
A haszna a proxied neveken: WAF- és bot-szabályok (pl. csak magyarországi forrás az `auth` nevére),
DDoS-szűrés, cache.

Beállítások a Cloudflare-en:

- SSL/TLS mód: **Full (strict)**, mert az origin érvényes Let's Encrypt-certet ad.
- **Always Use HTTPS kikapcsolva**: az nginx maga irányít át HTTPS-re, és a 80-as porton
  szolgálja ki a megújításhoz szükséges ACME-challenge-et (`acme.conf`).

Az nginx a proxied kéréseknél a `CF-Connecting-IP` fejlécből veszi a kliens címét
(`base/configs/snippets/cloudflare-real-ip.conf`), csak a Cloudflare tartományaiból érkező kapcsolatnál.
Így a logokban, az Autheliában és a későbbi CrowdSecben a valódi kliens-IP látszik.
A Cloudflare IP-listája ritkán változik; forrás a snippet fejlécében.
