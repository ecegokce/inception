# Inception — Developer Guide

## Prerequisites

- A Linux VM with Docker Engine and the Docker Compose plugin installed
  (`docker compose version` should work).
- `openssl` available on the host (used by `make init` to generate secrets,
  and inside the nginx container to generate the TLS certificate).

## Repo layout

```
Makefile                         entry point for every operation
srcs/docker-compose.yml          the 3 services, network, volumes, secrets
srcs/.env.example                committed template -> copied to srcs/.env
srcs/.env                        git-ignored, real config, created by `make init`
srcs/requirements/<service>/     one Dockerfile + conf/ + tools/ per service
secrets.example/                 committed placeholder secret files
secrets/                         git-ignored, real secrets, created by `make init`
```

## Config files and secrets

- **`srcs/.env`**: non-secret configuration (domain name, DB name, WordPress
  usernames/titles). Copied from `srcs/.env.example` by `make init` if it
  doesn't exist yet; edit it by hand to change e.g. `DOMAIN_NAME`.
- **`secrets/*.txt`**: one password per file (`db_password`,
  `db_root_password`, `wp_admin_password`, `wp_user_password`), generated
  randomly by `make init`. They are mounted into containers at
  `/run/secrets/<name>` by the compose `secrets:` section — never passed as
  environment variables or baked into an image.

Both `srcs/.env` and `secrets/` are listed in `.gitignore`. Only the
`.example` versions (with placeholder values) are committed.

## Building and launching

```sh
make init     # creates srcs/.env and secrets/*.txt (idempotent, run once)
make all      # mkdir -p host data dirs, then docker compose up -d --build
```

`make all` / `make build` / `make up` refuse to run if `secrets/` or
`srcs/.env` are missing, and tell you to run `make init` first.

Other targets: `make build` (build images only), `make up` (start without
rebuilding), `make down`, `make stop`, `make logs`, `make ps`, `make clean`
(remove containers + locally built images, keep volumes/data),
`make fclean` (also remove volumes and the host data directory — may need
`sudo` since the data is root-owned by the containers), `make re`
(`fclean` + `all`).

Every target that touches Docker calls
`docker compose -f srcs/docker-compose.yml --env-file srcs/.env ...`, so
compose is never invoked directly/inconsistently.

## How each container starts

All three images use the same pattern: a small `tools/init.sh` entrypoint
that does one-time setup *idempotently* (safe to re-run on every container
start), then replaces itself with the real service via `exec`, so that
service — not a shell — ends up as PID 1. There is no polling/sleep loop
anywhere.

- **mariadb**: on an empty data directory, runs `mariadb-install-db` then
  `mariadbd --bootstrap` fed a one-shot SQL script (create DB, create the
  WordPress DB user, set the root password). On a non-empty data directory
  (i.e. the volume already has data), this is skipped. Finishes with
  `exec mariadbd`.
- **wordpress**: if `wp-config.php` doesn't exist yet, downloads WordPress,
  configures it, installs it, and creates the second WordPress user, all
  via wp-cli, reading passwords from `/run/secrets/*`. Otherwise skipped.
  Finishes with `exec php-fpm8.2 -F`, listening on `0.0.0.0:9000`.
- **nginx**: generates a self-signed certificate for `DOMAIN_NAME` if one
  isn't already on disk, then `exec nginx -g 'daemon off;'`. Listens on
  443 only, TLS 1.2/1.3, proxies `.php` requests to `wordpress:9000`.

`wordpress` only starts once mariadb's healthcheck passes
(`depends_on: condition: service_healthy` in the compose file), which is
how "wait for the DB" is handled without a loop in any entrypoint script.

## Managing containers and volumes

```sh
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f <service>
docker exec -it mariadb bash
docker exec -it wordpress bash
docker volume ls          # shows mariadb_data / wordpress_data
docker volume inspect srcs_mariadb_data
```

## Where data is stored, and how it persists

The two named volumes (`mariadb_data`, `wordpress_data`) use the `local`
driver with `driver_opts: type: none, o: bind, device: ...`, which makes a
named volume that is physically backed by a specific host directory rather
than Docker's internal storage area:

- `mariadb_data`   -> `/home/egokce/data/mariadb`
- `wordpress_data` -> `/home/egokce/data/wordpress`

`make all` creates both directories before starting compose. Because this
is a real named volume (not a bind mount in the compose file itself), it
satisfies the subject's "named volumes only" requirement while still
putting the bytes where the subject also requires them to be.

Data survives `make down` + `make up` (and plain container
crashes/restarts) because the volume — and the host directory behind it —
is untouched by either. Only `make fclean` (or `docker compose ... down -v`)
removes it.
