# Tanúsítványok

Let's Encrypt, webroot módszerrel. A certek a `certs` volume-ban vannak, az nginx csak olvassa.
A `certbot` konténer a `maintenance` profilban van, csak kézi és időzített futtatáskor indul.
A parancsok a `/opt/compose/base` könyvtárból futnak.

A `*.ananasz.hu` HTTP-vhost (`configs/conf.d/00-default.conf`) minden aldomainre kiszolgálja
az ACME-challenge-et, így új névhez nem kell külön HTTP-vhost. DNS a NAS publikus IP-jére mutasson.

## Új domain

```sh
docker compose run --rm --no-deps certbot certonly --webroot -w /var/www/certbot -d NEV.ananasz.hu
```

Ezután a meglévők mintájára HTTPS-vhost a `configs/conf.d/` alá, majd nginx-teszt/reload
([frissítés](DEPLOYMENT.md#frissítés)).

## Megújítás

A `cert-renew.timer` naponta kétszer futtatja:

```sh
sh scripts/renew-certificates.sh --dry-run
sh scripts/renew-certificates.sh --renew
```

A régi certek a nginx-pluginnal készültek; a script a megújításkor webroot authenticatorra
és `null` installerre állítja őket.

## Törlés

A vhost előbb ne hivatkozzon a certre, majd nginx-teszt/reload. A név a listából:

```sh
docker compose run --rm --no-deps certbot certificates
docker compose run --rm --no-deps certbot delete --cert-name CERT_NAME
```
