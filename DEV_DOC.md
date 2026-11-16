# Inception: Developer Guide

This guide explains how to set up, build and maintain the project. To use
the running site, read [USER_DOC.md](USER_DOC.md).

## Prerequisites

- A Linux VM (the project was developed on Debian) with:
  - Docker Engine and the Docker Compose plugin (`docker compose version`
    must work)
  - `make`
  - `openssl`, to generate the passwords
  - `sudo` rights, because `make fclean` deletes data folders owned by
    container users
- Your user must be in the `docker` group, or you must run the commands
  with `sudo`.

## Repository layout

```
Makefile                                 entry point for every operation
README.md / USER_DOC.md / DEV_DOC.md     documentation
secrets/                                 git-ignored, one password per .txt file
srcs/
├── .env                                 git-ignored, non-secret configuration
├── docker-compose.yml                   services, network, volumes, secrets
└── requirements/
    ├── mariadb/
    │   ├── Dockerfile
    │   ├── conf/50-server.cnf           bind-address 0.0.0.0, pid file
    │   └── tools/init.sh                first-run DB setup, then exec mariadbd
    ├── wordpress/
    │   ├── Dockerfile                   php8.2-fpm + extensions + wp-cli 2.11.0
    │   ├── conf/www.conf                php-fpm pool, listen 0.0.0.0:9000
    │   └── tools/init.sh                first-run WP install, then exec php-fpm8.2 -F
    └── nginx/
        ├── Dockerfile
        ├── conf/nginx.conf              443 ssl, TLSv1.2/1.3, fastcgi_pass wordpress:9000
        └── tools/init.sh                self-signed cert, then exec nginx
```

## Setting up the environment from scratch

`srcs/.env` and `secrets/` are git-ignored, so a fresh clone does not have
them. `make` stops with `error: missing secrets/ or srcs/.env` until you
create both.

### 1. `srcs/.env` (non-secret configuration)

```sh
cat > srcs/.env <<'EOF'
DOMAIN_NAME=egokce.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

WP_TITLE=Inception

WP_ADMIN_USER=egokce_owner
WP_ADMIN_EMAIL=egokce_owner@egokce.42.fr

WP_USER=editor_eg
WP_USER_EMAIL=editor_eg@egokce.42.fr
WP_USER_ROLE=editor
EOF
```

| Variable | Used by | Meaning |
|----------|---------|---------|
| `DOMAIN_NAME` | nginx, wordpress | Domain for the certificate and the WordPress site URL |
| `MYSQL_DATABASE`, `MYSQL_USER` | mariadb, wordpress | Database name and user created on the first run |
| `WP_TITLE` | wordpress | Site title |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL` | wordpress | Administrator. The username must not contain `admin` (subject rule) |
| `WP_USER`, `WP_USER_EMAIL`, `WP_USER_ROLE` | wordpress | Second, non-admin user |

> `server_name` and the certificate paths in `nginx.conf` are hard-coded to
> `egokce.42.fr`. If you change `DOMAIN_NAME`, update `nginx.conf` as well.

### 2. `secrets/` (passwords)

```sh
mkdir -p secrets
for s in db_password db_root_password wp_admin_password wp_user_password; do
    openssl rand -base64 18 > secrets/$s.txt
done
chmod 600 secrets/*.txt
```

`docker-compose.yml` declares each file in its top-level `secrets:`
section. Each service gets only the secrets it lists, mounted read-only at
`/run/secrets/<name>`:

| Secret | mariadb | wordpress | nginx |
|--------|:-:|:-:|:-:|
| `db_password` | ✔ | ✔ | |
| `db_root_password` | ✔ | | |
| `wp_admin_password` | | ✔ | |
| `wp_user_password` | | ✔ | |

Passwords never appear in a Dockerfile, an image layer or an environment
variable.

### 3. Domain name

```sh
echo "127.0.0.1 egokce.42.fr" | sudo tee -a /etc/hosts
```

### 4. Data folders

`make` creates them for you, so this step is only for information:

```sh
mkdir -p /home/egokce/data/mariadb /home/egokce/data/wordpress
```

## Building and launching

The Makefile wraps Docker Compose. Every Docker target runs:

```sh
docker compose -f srcs/docker-compose.yml --env-file srcs/.env <command>
```

| Target | Action |
|--------|--------|
| `make` / `make all` | `check-config`, create the data folders, then `up -d --build --force-recreate` |
| `make build` | Build the images only (`mariadb:1.0`, `wordpress:1.0`, `nginx:1.0`) |
| `make up` | Create and start the containers without rebuilding |
| `make start` / `make stop` | Start or stop existing containers |
| `make down` | Remove the containers and the network. Volumes and data are kept |
| `make logs` | `logs -f` for all services |
| `make ps` | Container status |
| `make clean` | `down` + remove the locally built images |
| `make fclean` | `clean` + `down -v` + `sudo rm -rf /home/egokce/data/{mariadb,wordpress}` |
| `make re` | `fclean` then `all`, a full reset from scratch |

### Startup sequence

1. **mariadb** starts. On an empty data folder, `init.sh` runs
   `mariadb-install-db`, then `mariadbd --bootstrap` with a SQL script that
   sets the root password, creates the database and user and removes
   anonymous users. It then runs `exec mariadbd`.
2. Compose runs the healthcheck (`mysqladmin ping`) every 5 s. When it
   succeeds, mariadb is `healthy`.
3. **wordpress** starts because of `depends_on: condition:
   service_healthy`. If `wp core is-installed` fails, wp-cli downloads
   WordPress, creates `wp-config.php` (`--dbhost=mariadb`), installs the
   site and creates the second user. It then runs `exec php-fpm8.2 -F`.
4. **nginx** creates a self-signed certificate in `/etc/nginx/ssl/` if
   there is none, then runs `exec nginx -g "daemon off;"`.

Each `init.sh` checks first whether its setup was already done, so it is
safe to run again on every restart. Each one ends with `exec`, so the
daemon becomes PID 1.

## Managing containers and volumes

```sh
# status and logs
make ps
docker logs -f wordpress

# open a shell inside a container
docker exec -it mariadb bash
docker exec -it wordpress bash
docker exec -it nginx bash

# connect to the database
docker exec -it mariadb sh -c 'mariadb -uroot -p"$(cat /run/secrets/db_root_password)"'

# WordPress CLI
docker exec -it wordpress wp user list --allow-root --path=/var/www/html

# rebuild and restart a single service
docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build nginx

# network and volumes
docker network ls                      # srcs_inception
docker network inspect srcs_inception
docker volume ls                       # srcs_mariadb_data, srcs_wordpress_data
docker volume inspect srcs_mariadb_data

# test the nginx config inside the container
docker exec nginx nginx -t
```

Compose adds the project name (`srcs`, from the folder of the compose file)
in front of the network and volume names.

## Where the data is stored and how it persists

| Volume | Mounted in | Host folder |
|--------|------------|-------------|
| `mariadb_data` | mariadb: `/var/lib/mysql` | `/home/egokce/data/mariadb` |
| `wordpress_data` | wordpress: `/var/www/html` (rw), nginx: `/var/www/html` (`:ro`) | `/home/egokce/data/wordpress` |

Both are **named volumes** using the `local` driver with `driver_opts: type:
none, o: bind, device: <host path>`. Docker manages them by name, and their
content is written to the host folders above.

What deletes the data:

| Action | Containers | Images | Data in `/home/egokce/data` |
|--------|:-:|:-:|:-:|
| Container crash / `restart: always` | restarted | kept | **kept** |
| `make stop` / `make start` | stopped / started | kept | **kept** |
| `make down` / `make up` | removed / recreated | kept | **kept** |
| `make clean` | removed | removed | **kept** |
| VM reboot | restarted automatically | kept | **kept** |
| `make fclean` / `make re` | removed | removed | **deleted** |

Because the first-run setup is skipped when data already exists, changes
made in WordPress (posts, users, settings) survive rebuilds. To check:
create a post, run `make down && make up`, and the post is still there.
