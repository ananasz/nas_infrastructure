# Registry karbantartás

Napi retention 01:30-kor: repositorynként az utolsó 5 különböző image és minden 30 napnál frissebb marad.
A tagek ugyanazon digestre mutató változatai egy buildnek számítanak. Nincs külön védelem a futó verziókra.
Az idő az image `created` mezője; dátum nélkül a retention megtartja és naplózza az image-et.

Heti GC vasárnap 04:00-kor, a szerver helyi ideje szerint. A registry erre az időre leáll,
majd hiba esetén is visszaindul. A két feladat közös lockot használ.
Az API-törlést a Compose `REGISTRY_STORAGE_DELETE_ENABLED` beállítása engedélyezi.

Linuxon a repó gyökeréből telepítsd a unitokat; a stack fájljai legyenek már `/opt/compose/registry` alatt:

```sh
sudo install -o root -g root -m 0644 rootfs/etc/systemd/system/registry-* /etc/systemd/system/
cd /opt/compose/registry
docker compose --profile maintenance pull
sudo bash scripts/maintenance.sh retention --dry-run
sudo bash scripts/maintenance.sh gc --dry-run
sudo systemctl daemon-reload
sudo systemctl enable --now registry-retention.timer registry-gc.timer
```

A GC dry-run is megállítja a registryt. Kézi futtatásnál a `--dry-run` elhagyható.
Ellenőrzés: `journalctl -u registry-retention -u registry-gc`.

A retention API-n törli az elavult manifesteket és a csak hozzájuk tartozó platformmanifesteket.
A normál GC felszabadítja a rétegeiket. Korábbról megmaradt, már tag nélküli manifesteket nem töröl;
a `--delete-untagged` módhoz [nyitott adatvesztési hibajelentés](https://github.com/distribution/distribution/issues/4939) tartozik.
