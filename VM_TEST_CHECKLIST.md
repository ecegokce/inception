# VM Test Checklist

Run these in order on the 42 campus Linux VM. Replace `<repo-url>` with
wherever you push this repo (or copy it over) before cloning.

## 0. Clone and sanity-check line endings

```sh
git clone <repo-url> inception
cd inception
grep -rlP '\r' --include='*.sh' . ; echo "exit=$?"   # expect "no output" + exit=1
```

If that grep prints any filename, a script has CRLF endings — fix before
continuing (`sed -i 's/\r$//' <file>`), or it'll fail with
`bad interpreter: /bin/bash^M`.

## 1. First-time setup

```sh
make init
cat srcs/.env                      # sanity-check values, esp. DOMAIN_NAME
ls -la secrets/                    # should contain 4 .txt files, mode 600
```

## 2. /etc/hosts

```sh
echo "127.0.0.1   egokce.42.fr" | sudo tee -a /etc/hosts
```

## 3. Build and start

```sh
make
make ps                            # all 3 "Up", mariadb "healthy"
```

If `make` errors immediately about missing `secrets/`/`srcs/.env`, step 1
was skipped or failed.

## 4. Per-container checks

```sh
docker ps --format '{{.Names}}\t{{.Status}}'
docker inspect -f '{{.State.Pid}} {{.Config.Entrypoint}}' mariadb wordpress nginx

# PID 1 inside each container should be the real service, not bash:
docker exec mariadb   ps -p 1 -o comm=   # expect: mariadbd
docker exec wordpress ps -p 1 -o comm=   # expect: php-fpm8.2
docker exec nginx     ps -p 1 -o comm=   # expect: nginx
```

## 5. TLS checks

```sh
# Port 80 must be closed:
curl -sv http://egokce.42.fr/ 2>&1 | head -5     # expect connection refused

# TLS1.2 accepted:
openssl s_client -connect egokce.42.fr:443 -tls1_2 </dev/null 2>&1 | grep -E "Protocol|Cipher"

# TLS1.3 accepted:
openssl s_client -connect egokce.42.fr:443 -tls1_3 </dev/null 2>&1 | grep -E "Protocol|Cipher"

# TLS1.1 must be REJECTED (expect an error, no handshake):
openssl s_client -connect egokce.42.fr:443 -tls1_1 </dev/null 2>&1 | tail -5
```

## 6. Site and admin panel

```sh
curl -sk https://egokce.42.fr/ | grep -i "<title"
```

Then in a browser: https://egokce.42.fr (accept the self-signed cert
warning), confirm the site loads, then log in at
https://egokce.42.fr/wp-admin with `WP_ADMIN_USER` (from `srcs/.env`) and
the password in `secrets/wp_admin_password.txt`.

## 7. Two DB users exist

```sh
docker exec wordpress wp user list --path=/var/www/html --allow-root
```

Expect two rows: the admin user (role `administrator`, username does NOT
contain "admin") and the second user (role from `WP_USER_ROLE`, default
`editor`).

## 8. Data persistence across down/up

```sh
docker exec wordpress wp option get blogname --path=/var/www/html --allow-root
make down
make up
make ps                                          # wait for healthy again
docker exec wordpress wp option get blogname --path=/var/www/html --allow-root
```

Both `blogname` reads should match, and the admin login from step 6 should
still work — no re-install should have happened (check logs for
"skipping install"/"skipping setup"):

```sh
docker logs wordpress | grep -i skip
docker logs mariadb   | grep -i skip
```

## 9. Restart policy (crash recovery)

```sh
docker kill nginx
sleep 3
docker ps --format '{{.Names}}\t{{.Status}}'     # nginx should be back up
```

Repeat for `wordpress` and `mariadb` if you want to be thorough.

## 10. Host data location

```sh
sudo ls -la /home/egokce/data/mariadb
sudo ls -la /home/egokce/data/wordpress
```

Both should be non-empty and contain the expected files
(`ibdata1`/`.ibd` files for mariadb, `wp-config.php`/`wp-content` for
wordpress).

---

## Most likely failure points, in order of likelihood

1. **CRLF line endings** — any `.sh` script with `\r` fails with
   `bad interpreter`. Check with the grep in step 0.
2. **Volume/file permission issues** — if nginx can't read files
   php-fpm wrote (403s on uploads, etc.), check `chown -R www-data` ran
   in `wordpress/tools/init.sh` and that both containers' `www-data` UID
   actually matches (should, since both come from the same Debian base).
3. **MariaDB init** — if `wordpress` can't connect, check
   `docker logs mariadb` for bootstrap errors, and confirm
   `/home/egokce/data/mariadb` isn't leftover from a previous, differently
   configured run (if so, `make fclean` first).
4. **php-fpm socket/port mismatch** — if nginx gets 502/504, confirm
   `conf/www.conf` in `wordpress/` has `listen = 0.0.0.0:9000` (not the
   default `127.0.0.1:9000` or a unix socket path), and that
   `nginx.conf`'s `fastcgi_pass` says `wordpress:9000`.
5. **Healthcheck never turns healthy** — `docker inspect mariadb` and
   check the healthcheck log (`docker inspect --format
   '{{json .State.Health}}' mariadb`); usually means the root password in
   the healthcheck command doesn't match what bootstrap actually set.
