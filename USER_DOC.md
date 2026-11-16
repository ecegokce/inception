# Inception: User Guide

This guide is for people who use or administer the running stack. To build
or change the project, read [DEV_DOC.md](DEV_DOC.md).

## Services provided

The stack runs a WordPress website over HTTPS, split into three containers:

| Service     | Role |
|-------------|------|
| `nginx`     | The only entry point. Serves the site on **port 443 (HTTPS, TLS 1.2/1.3)** |
| `wordpress` | Runs WordPress with php-fpm. It is not reachable from outside |
| `mariadb`   | Stores the WordPress database. It is not reachable from outside |

The containers talk to each other over a private Docker network called
`inception`. Only nginx's port 443 is open on the host.

## Starting and stopping

Run these commands from the repository root:

| Command      | What it does |
|--------------|--------------|
| `make`       | Builds the images and starts all services (first run or after changes) |
| `make stop`  | Stops the containers without removing them |
| `make start` | Starts stopped containers again |
| `make down`  | Stops and removes the containers. **The data is kept** |
| `make up`    | Creates and starts the containers again, without rebuilding |
| `make logs`  | Follows the logs of all services (`Ctrl+C` to quit) |
| `make ps`    | Shows the status of the containers |

> ⚠️ `make fclean` and `make re` **delete all data**, including the database,
> posts and uploads. Use them only if you want to start from an empty site.

## Accessing the website and the admin panel

1. Make sure `/etc/hosts` on the machine where you open the browser
   contains this line:

   ```
   127.0.0.1   egokce.42.fr
   ```

2. Open the website: **https://egokce.42.fr**
3. Open the admin panel: **https://egokce.42.fr/wp-admin**

The certificate is self-signed, so the browser will show a security
warning. Choose "Advanced" → "Accept the risk / Proceed" to continue.
`http://` (port 80) does not work, by design.

## Credentials

| Account | Username | Password |
|---------|----------|----------|
| WordPress administrator | `WP_ADMIN_USER` in `srcs/.env` | `secrets/wp_admin_password.txt` |
| WordPress editor (second user) | `WP_USER` in `srcs/.env` | `secrets/wp_user_password.txt` |
| MariaDB WordPress user | `MYSQL_USER` in `srcs/.env` | `secrets/db_password.txt` |
| MariaDB root | `root` | `secrets/db_root_password.txt` |

To read a password:

```sh
cat secrets/wp_admin_password.txt
```

Notes:
- `srcs/.env` and `secrets/` are **never committed to git** (they are in
  `.gitignore`). Keep them private.
- The passwords are applied **only on the first start**, when the data
  folders are empty. Editing a secret file later does not change an existing
  password. To change a WordPress password afterwards, use the admin panel
  (Users → Profile), or reset everything with `make re`, which deletes all
  data.

## Checking that the services are running

```sh
make ps
```

All three containers should be `Up`, and `mariadb` should also show
`(healthy)`.

Other checks:

```sh
# logs of one service
docker logs nginx
docker logs wordpress
docker logs mariadb

# the site answers over HTTPS (-k accepts the self-signed certificate)
curl -kI https://egokce.42.fr

# only TLS 1.2 / 1.3 are accepted
openssl s_client -connect egokce.42.fr:443 -tls1_2 </dev/null | grep Protocol

# the database is up and contains the WordPress tables
docker exec mariadb sh -c 'mariadb -uroot -p"$(cat /run/secrets/db_root_password)" -e "SHOW TABLES FROM wordpress;"'
```

On the first start, the logs should contain lines like
`[mariadb-init] first-time setup complete` and
`[wordpress-init] WordPress install complete`. On later starts they say
`... already initialized / installed, skipping`.
