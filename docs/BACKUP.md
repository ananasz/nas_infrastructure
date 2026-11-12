# Mentés Filenre

A `nas-backup.sh` restic + rclone segítségével titkosított mentési pontokat készít.
Az első futás minden szükséges adatot feltölt, a továbbiak deduplikálva csak az új
adatblokkokat. Minden mentési pont teljes állapotként állítható vissza; heti/havi
új teljes feltöltés nem kell. Naponta 03:30 után fut, 7 napi, 5 heti és 12 havi
pontot tart meg. A fotók kezdeti feltöltése napokig is tarthat; a ZFS-pillanatkép
addig helyet foglal a közben törölt/módosított adatoknak is.

## Tartalom és konzisztencia

- anaChronos: minden alkalommal teljes SQL-dump a futó Postgresből (konzisztens DB-nézet).
- Cetli: leállított CouchDB teljes adatkönyvtára tarban, valamint `/opt/couchdb/etc`.
  A DB a helyi másolás után újraindul; a felhőfeltöltés alatt már elérhető.
- Immich: az `immich_server` leállítása, teljes SQL-dump, ZFS-pillanatkép, újraindítás.
  A feltöltés a változatlan pillanatképből megy. A fotókönyvtárat ilyenkor más
  folyamat sem módosíthatja. A fotók alatt külön gyermek mount/dataset nem támogatott.
  Kimarad: `thumbs`, `encoded-video`, `backups` (helyettük saját friss dump készül).
  A profilképek és az eredeti fájlok bekerülnek. Külső Immich-könyvtár nincs a mentésben.
- Vaultwarden: néhány másodpercre leállított konténer teljes `/data` volume-a tarban
  (SQLite DB, attachmentek, sendek, `rsa_key*`, `config.json`); az `icon_cache` kimarad.
- A négy stack teljes konfigurációja, `.env` fájlokkal; konténer-metaadatok az
  image-verziók azonosításához. Ezek titkokat tartalmaznak, ezért a helyi staging is 0700.

A dumpok helye `/var/lib/nas-backup/staging`, helyigényük a két SQL-dump, a teljes
CouchDB és a Vaultwarden-adat mérete. Siker után is megmaradnak a következő futásig.
Ez nem másik lemezes helyi mentés. Hibánál a szkript megpróbálja újraindítani az általa leállított konténereket.
Gépösszeomlás/SIGKILL után kézzel ellenőrizni kell a konténereket, a bind mountot
és a `nas-backup-*` ZFS-pillanatképeket.

## Beállítás a NAS-on

1. Telepíts resticet, **rclone >= 1.73**-at (ebben jelent meg a Filen backend),
   Filen CLI-t a hivatalos kiadásokból, valamint `zfsutils-linux`, `util-linux`, `tar` csomagokat.
   A disztribúció rclone-csomagja lehet túl régi. Ellenőrzés: `restic version`,
   `rclone version`, `rclone help backends`.
2. Másold fel a repó fájljait a [telepítési leírás](DEPLOYMENT.md) szerint.
   A `/opt/compose/backup/.env` a `.env.example` másolata legyen, root tulajdonossal,
   0600 joggal. `zfs list -o name,mountpoint` alapján töltsd ki a `PHOTOS_DATASET` értékét.
3. Rootként: `install -d -m 0700 /opt/compose/backup/secrets`.
   A Filen CLI-ben jelentkezz be, majd `export-api-key`. Ezután
   `rclone config --config /opt/compose/backup/secrets/rclone.conf`: új remote neve
   `filen`, típusa `filen`; add meg a kért hitelesítést az interaktív felületen.
   A kulcsot és jelszót ne másold gitbe vagy parancssori argumentumba.
   `chmod 0600 /opt/compose/backup/secrets/rclone.conf`.
4. Generálj külön restic-jelszót:

   ```sh
   sudo sh -c 'umask 077; openssl rand -base64 48 > /opt/compose/backup/secrets/restic-password'
   sudo nas-backup.sh init
   sudo nas-backup.sh backup
   sudo nas-backup.sh snapshots
   sudo nas-backup.sh check
   ```

   Az `init` csak egyszer kell. A restic-jelszó és a Filen-hozzáférés legyen a NAS-tól
   független, biztonságos helyen is megőrizve; nélkülük katasztrófa után nincs visszaállítás.
   Filen-jelszócsere után az API-kulcsot is újra kell exportálni és az rclone-konfigot frissíteni.
5. Az első mentés és egy visszaállítási próba után:

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now nas-backup.timer
   ```

## Ellenőrzés és karbantartás

`journalctl -u nas-backup.service`, `systemctl status nas-backup.timer` és
`/var/lib/nas-backup/last-success`: csak teljesen sikeres backup + retention + takarítás
után frissül az utóbbi. A mentés nem készít még Grafana-riasztást; ezt külön be kell kötni,
pl. 48 óránál régebbi siker esetére. Havonta `sudo nas-backup.sh check` (5% adatot is
visszaolvas), időnként teljes `restic check --read-data` a lent betöltött környezettel.

A `forget` csak mentési pontokat távolít el; a már nem használt blokkokat külön
`sudo nas-backup.sh prune` szabadítja fel. Havonta futtasd és ellenőrizd a Filen
tárhelyhasználatát, a kukát/verziókat is: a backend törlése nem feltétlenül szabadít
fel azonnal felhőkvótát. A prune/check/backup közös helyi zárral fut a wrapperen át.

## Visszaállítási próba és helyreállítás

Root shellben, külön célkönyvtárba (soha ne közvetlenül az éles adatokra):

```sh
set -a
. /opt/compose/backup/.env
set +a
restic snapshots --tag nas-data
restic restore SNAPSHOT_ID --target /var/lib/nas-restore
```

1. A `var/lib/nas-backup/staging` alól a dumpokat és a Cetli tartalmát ellenőrizd.
   Válassz véletlenszerű fotókat/videókat a `var/lib/nas-backup/photos` alól és nyisd meg őket.
2. Izolált, az elmentett image-verzióknak megfelelő DB-kben próbáld ki a visszatöltést.
   anaChronos: üres DB létrehozása az eredeti userrel és adatbázisnévvel, majd
   `psql -v ON_ERROR_STOP=1 -U USER -d DATABASE < anachronos.sql`. A szerepköröket/jelszót
   a mentett Compose és `.env` alapján hozd létre. A dump nem tartalmaz cluster-szerepköröket.
3. Cetli: leállított, azonos verziójú üres példány adatvolume-jába csomagold ki a
   `cetli-data.tar`-t rootként, numerikus tulajdonosok megőrzésével; állítsd vissza
   az `etc` konfigurációt és a `.env`-et. Indítás után ellenőrizd a DB-ket és belépést.
4. Immich: azonos Immich/Postgres-verzió, friss DB-volume; az alkalmazásszerver álljon.
   A fotókat az eredeti `/nas-data/zfs-pool/photos` helyre másold vissza (rejtett
   `.immich` fájlokkal és jogosultságokkal együtt). Az SQL-dumpot a verzióhoz tartozó
   [hivatalos restore-eljárással](https://docs.immich.app/administration/backup-and-restore/)
   töltsd be. A kihagyott könyvtárakhoz szükséges `.immich` markereket is hozd létre
   a verzió leírása szerint; indítás után generáltasd újra a bélyegképeket és videókat.
   Ellenőrizd az albumokat, felhasználókat és régi képek letöltését is.
5. Vaultwarden: azonos verziójú, leállított konténer üres `vaultwarden-data` volume-jába
   csomagold ki a `vaultwarden-data.tar`-t rootként, numerikus tulajdonosok megőrzésével;
   állítsd vissza a `.env`-et. Indítás után a webes trezorban lépj be, nyiss meg néhány
   bejegyzést és attachmentet. Az `rsa_key*` nélkül minden kliensnek újra be kell lépnie.

Források: [restic rclone backend](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#other-services-via-rclone),
[rclone Filen](https://rclone.org/filen/),
[CouchDB mentés](https://docs.couchdb.org/en/stable/maintenance/backups.html).
