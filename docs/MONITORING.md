# Monitoring

A `monitoring` stack mindent helyben gyűjt és tárol. Grafana: `http://grafana.nas`
(admin jelszó: `monitoring/.env`).

| Forrás | Gyűjtő | Tár |
| --- | --- | --- |
| Konténerlogok (minden konténer stdout/stderr) | Alloy | Loki, 30 nap |
| Host: CPU, RAM, hálózat, lemez I/O, fájlrendszerek, ZFS, hwmon | Alloy (node exporter) | VictoriaMetrics |
| Konténer CPU/RAM/hálózat/I/O | cAdvisor | VictoriaMetrics |
| Lemezek SMART-adatai | smartctl-exporter | VictoriaMetrics |

A metrikák megőrzése a `.env` `METRICS_RETENTION` értéke (alapból 180 nap).
A Glances helyett a node exporter és a cAdvisor adja ugyanezt Grafanában.

Dashboardok (`configs/grafana/dashboards/`, a Grafana 30 másodpercenként beolvassa):

- **Metrics**: host CPU, RAM, swap, load, hálózat, rendszerlemez, konténer-összesítők;
- **Container STATS**: konténerenkénti erőforrás-táblázat;
- **Disks**: SMART-állapot, hőmérséklet, hibás szektorok, NVMe-kopás, ZFS pool állapot, fájlrendszerek, lemez I/O;
- **Container LOGS**: logkereső projekt/konténer/szöveg szerint.

A UI-ban módosított provisionált dashboardot Save as-szel mentsd, vagy a JSON-t szerkeszd a repóban.
Egy konténer logja a `logging.collect: "false"` címkével zárható ki.

## Ellenőrzés

A `/opt/compose/monitoring` könyvtárból:

```sh
docker compose run --rm --no-deps alloy validate /etc/alloy/config.alloy
docker compose logs --tail 50 smartctl-exporter
```

Grafana Explore, Metrics adatforrás: `up{host="nas"}`, minden job (`node`, `cadvisor`, `smartctl`) értéke `1`.

## SMART

A `smartctl-exporter` privilegizált konténer, percenként lekérdezi az összes lemezt.
Ha a HDD-k elalvását (spindown) használod, a lekérdezés felébresztheti őket;
ilyenkor az exporter verziójának megfelelő power-mode beállítást vagy ritkább gyűjtést kell beállítani.
Időzített SMART self-test (pl. `smartd` a hoston) ettől független, javasolt.

Riasztási szabály még nincs; javaslat: [tervek](PLANS.md#riasztások). Az értesítési csatorna kész:
minden riasztás e-mailben az `ALERT_EMAIL` címre megy (`configs/grafana/provisioning/alerting/`, [SMTP](EMAIL.md)).
