# E-mail-küldés (SMTP2GO)

A szolgáltatások az SMTP2GO-n keresztül küldenek levelet; az `ananasz.hu` domain ott ellenőrzött feladó,
így bármely `@ananasz.hu` feladócím használható. A havi keret kicsi, ezért csak a szükséges értesítések legyenek bekapcsolva.

Kapcsolat: `mail.smtp2go.com`, port `587`, STARTTLS (ha a 587 nem elérhető: `2525`).

Minden szolgáltatás saját SMTP-felhasználót kap az SMTP2GO **SMTP Users** oldalán; így külön tiltható,
és a küldési napló szolgáltatásonként szűrhető. A felhasználónév és jelszó a stack `.env` fájljába kerül
(`SMTP_USERNAME`, `SMTP_PASSWORD`, aposztrófok közé), majd a stack könyvtárából `docker compose up -d`.

| Szolgáltatás | Beállítás helye | Feladó | Levelek |
| --- | --- | --- | --- |
| Authelia | `auth/.env`, `auth/configs/configuration.yml` | `auth@ananasz.hu` | jelszó-visszaállítás, 2FA-regisztráció kódja |
| Vaultwarden | `vaultwarden/.env`, `vaultwarden/compose.yml` | `vaultwarden@ananasz.hu` | meghívó, e-mail-ellenőrzés, új eszköz, e-mailes 2FA |
| Grafana | `monitoring/.env`, `configs/grafana/provisioning/alerting/` | `grafana@ananasz.hu` | riasztások az `ALERT_EMAIL` címre |
| Jellyseerr | webes felület | `seer@ananasz.hu` | kérések jóváhagyása, elérhetővé vált média |
| Immich | webes felület | `photos@ananasz.hu` | meghívó, albummegosztás |

## Ellenőrzés

- Authelia: az `auth.ananasz.hu` oldalon „Reset password”. A felhasználóknak a `users_database.yml`-ben
  valós `email` kell. Indításkor nincs SMTP-ellenőrzés, a hibás belépési adat csak küldéskor, a logban látszik:
  `docker logs authelia`.
- Vaultwarden: `/admin` → SMTP Email Settings → Send test email.
- Grafana: Alerting → Contact points → `email` → Test.

## Webes felületen beállítandó

Jellyseerr (`https://seer.ananasz.hu`): Settings → Notifications → Email. Sender Name `Jellyseerr`,
Sender Address `seer@ananasz.hu`, SMTP Host/Port a fenti, Encryption Method „Always use STARTTLS”,
SMTP felhasználó és jelszó; Test, majd a szükséges értesítéstípusok. A felhasználók a saját profiljukban
adják meg az e-mail-címüket. Settings → General → Application URL: `https://seer.ananasz.hu` (linkek a levélben).

Immich (`https://photos.ananasz.hu`): Administration → Settings → Notification Settings → Email.
Host/Port a fenti, SMTP felhasználó és jelszó, From address `Immich <photos@ananasz.hu>`; Send test email.
Server Settings → External Domain: `https://photos.ananasz.hu` (linkek a levélben).

Ezek a beállítások a szolgáltatás saját config-volume-jában/DB-jében vannak.
