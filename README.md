*This project has been created as part of the 42 curriculum by egokce.*

# Inception

## Description

Inception is a system administration project. The goal is to build a small
web infrastructure with **Docker Compose** inside a virtual machine. Every
service runs in its own container, and each image is built from my own
Dockerfile on top of `debian:bookworm`. No ready-made images from Docker Hub
are used, except for the Debian base.

The stack serves a **WordPress** website over **HTTPS only**:

```
            host :443
                │
        ┌───────▼───────┐   FastCGI :9000   ┌──────────────┐   SQL :3306   ┌─────────────┐
        │     nginx     │ ────────────────▶ │  wordpress   │ ────────────▶ │   mariadb   │
        │ TLS 1.2 / 1.3 │                   │   php-fpm    │               │  database   │
        └───────┬───────┘                   └──────┬───────┘               └──────┬──────┘
                │ (read-only)                      │                              │
                └──────────── wordpress_data ──────┘                       mariadb_data
                         /home/egokce/data/wordpress              /home/egokce/data/mariadb

                        all three containers on the "inception" bridge network
```

- **nginx** is the only entry point. It listens on port 443, handles TLS
  with a self-signed certificate, serves static files, and forwards `.php`
  requests to `wordpress:9000`.
- **wordpress** runs WordPress with php-fpm only, without a web server.
  On the first start, wp-cli downloads WordPress, writes `wp-config.php`,
  installs the site and creates two users: an administrator and an editor.
- **mariadb** holds the WordPress database. On the first start it creates
  the database, the WordPress DB user and the root password.

### Use of Docker and sources in this project

| Path | Content |
|------|---------|
| `Makefile` | Entry point: builds, starts, stops and cleans the stack |
| `srcs/docker-compose.yml` | The 3 services, the network, the 2 volumes and the 4 secrets |
| `srcs/.env` | Non-secret settings: domain, DB name, WordPress usernames (git-ignored) |
| `secrets/*.txt` | One password per file (git-ignored) |
| `srcs/requirements/<service>/Dockerfile` | Image definition for each service |
| `srcs/requirements/<service>/conf/` | Config files: `nginx.conf`, `www.conf` (php-fpm), `50-server.cnf` (MariaDB) |
| `srcs/requirements/<service>/tools/init.sh` | Entrypoint script: one-time setup, then `exec` of the real daemon |

### Main design choices

- **Debian bookworm** as the base for all images. It is stable and its
  packages (nginx, php8.2-fpm, mariadb-server) work without extra setup.
- **One process per container, running as PID 1.** Each `init.sh` does its
  setup and then calls `exec` to replace itself with the daemon (`nginx -g
  "daemon off;"`, `php-fpm8.2 -F`, `mariadbd`). This way the daemon gets
  signals directly and `docker stop` shuts it down cleanly. There is no
  `tail -f`, `sleep infinity` or `while true` anywhere.
- **Idempotent setup.** Each `init.sh` first checks whether setup was
  already done: the MariaDB system tables exist, WordPress is installed,
  the certificate exists. If so, it skips setup, so a restart never
  reinstalls anything or deletes data.
- **Startup order without polling loops.** MariaDB has a `healthcheck`
  (`mysqladmin ping`), and WordPress uses `depends_on: condition:
  service_healthy`. WordPress therefore starts only after the database
  accepts connections.
- **TLS 1.2 / 1.3 only**, on port 443 only. Port 80 is never opened.
- **`restart: always`** on every service, so a container that crashes is
  started again.
- **Passwords as Docker secrets.** Other settings go in `.env`.

### Virtual Machines vs Docker

| | Virtual Machine | Docker container |
|---|---|---|
| Isolation | Full guest OS with its own kernel, on a hypervisor | Shares the host kernel, isolated with namespaces and cgroups |
| Size / startup | GBs, boots in tens of seconds | MBs, starts in about a second |
| Overhead | Hardware is emulated and every VM runs a full OS | Close to native performance |
| Security boundary | Stronger, because each VM has its own kernel | Weaker, because a kernel bug can affect every container |
| Typical use | Different OSes, strong isolation | Packaging and running applications in a reproducible way |

This project uses both. The VM is the isolated machine required by the
subject. Inside it, Docker runs each service in its own lightweight,
rebuildable container.

### Secrets vs Environment Variables

| | Environment variables (`.env`) | Docker secrets |
|---|---|---|
| Where the value ends up | Process environment. It is visible with `docker inspect` and `/proc/<pid>/environ`, and child processes and logs can leak it | A file mounted at `/run/secrets/<name>`, only in the containers that list it |
| Scope | Every container that uses the `env_file` | Only the services that declare the secret |
| Suitable for | Non-sensitive settings | Passwords, keys, tokens |

Here, `srcs/.env` holds only non-sensitive values (domain, DB name,
usernames, emails). The four passwords (`db_password`, `db_root_password`,
`wp_admin_password`, `wp_user_password`) are Docker secrets. The `init.sh`
scripts read them with `cat /run/secrets/...`. MariaDB only gets the DB
secrets, and nginx gets none.

### Docker Network vs Host Network

| | User-defined bridge network | Host network (`network_mode: host`) |
|---|---|---|
| Isolation | Containers get their own network stack and private IPs | The container uses the host's network stack directly |
| Name resolution | Built-in DNS: containers reach each other by service name (`mariadb`, `wordpress`) | None between containers. Everything is `localhost` |
| Exposure | Only ports published with `ports:` are reachable from outside | Every port the container listens on is open on the host |
| Port conflicts | None, since each container has its own ports | Possible with host services |

The project uses one bridge network called `inception`, and `network_mode:
host`, `links` and `--link` are not used (the subject forbids them).
MariaDB (3306) and php-fpm (9000) can only be reached inside this network.
Only nginx publishes a port (`443:443`).

### Docker Volumes vs Bind Mounts

| | Named volume | Bind mount |
|---|---|---|
| Managed by | Docker (`docker volume ls`, `inspect`, `rm`) | Nobody. It is just a host path |
| Location | Docker's storage area by default (`/var/lib/docker/volumes`) | Any host path you give |
| Portability | Declared by name, no dependency on the host's folder layout | Depends on that path existing on the host |
| Typical use | Persistent application data | Sharing source code or config during development |

The subject requires named volumes, with the data stored in
`/home/<login>/data`. The two volumes (`mariadb_data`, `wordpress_data`) are
therefore **named volumes** using the `local` driver with `type: none, o:
bind, device: /home/egokce/data/...`. Docker manages them like any other
named volume, and their content is written to the required host folder.
The `wordpress_data` volume is shared: it is read-write for WordPress and
read-only (`:ro`) for nginx, which only needs to serve the files.

## Instructions

### Requirements

- A Linux VM with Docker Engine and the Docker Compose plugin
  (`docker compose version` must work)
- `make`, and `sudo` rights (only needed by `make fclean`)

### Configuration

Two items are git-ignored, so you must create them before the first run:

1. **`srcs/.env`**:

   ```sh
   DOMAIN_NAME=egokce.42.fr
   MYSQL_DATABASE=wordpress
   MYSQL_USER=wp_user
   WP_TITLE=Inception
   WP_ADMIN_USER=egokce_owner          # must not contain "admin"
   WP_ADMIN_EMAIL=egokce_owner@egokce.42.fr
   WP_USER=editor_eg
   WP_USER_EMAIL=editor_eg@egokce.42.fr
   WP_USER_ROLE=editor
   ```

2. **`secrets/`**, at the repository root, with one password per file:

   ```sh
   mkdir -p secrets
   for s in db_password db_root_password wp_admin_password wp_user_password; do
       openssl rand -base64 18 > secrets/$s.txt
   done
   ```

3. Point the domain to the local machine:

   ```sh
   echo "127.0.0.1 egokce.42.fr" | sudo tee -a /etc/hosts
   ```

### Build and run

```sh
make          # creates /home/egokce/data/{mariadb,wordpress}, builds and starts everything
make ps       # container status
make logs     # follow logs
make stop     # stop containers (keep them)
make start    # start stopped containers again
make down     # remove containers (data is kept)
make clean    # down + remove the built images
make fclean   # clean + remove volumes and /home/egokce/data (deletes all data)
make re       # fclean + make
```

Then open **https://egokce.42.fr** for the site and
**https://egokce.42.fr/wp-admin** for the admin panel. The browser will
warn about the self-signed certificate. Accept it to continue.

More documentation:
- [USER_DOC.md](USER_DOC.md): using and administering the running stack
- [DEV_DOC.md](DEV_DOC.md): setting up, building and maintaining the project

## Resources

### References

- [Docker documentation](https://docs.docker.com/): Dockerfile reference, Compose file reference
- [Compose: secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/) and [bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [Docker networking: bridge](https://docs.docker.com/engine/network/drivers/bridge/)
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
- [NGINX documentation](https://nginx.org/en/docs/): `ngx_http_ssl_module`, `ngx_http_fastcgi_module`
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/): `mariadb-install-db`, server system variables
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)

### Use of AI

I used AI (Claude) as a learning and review assistant. I did not use it to
generate the project without understanding it.

- **Learning concepts:** I asked questions to understand Docker and Compose:
  how named volumes with `o: bind` work, port mapping (`443:443`), PID 1 and
  `exec`, `healthcheck` + `depends_on`, why php-fpm must listen on
  `0.0.0.0:9000`, and the difference between secrets and environment
  variables.
- **Reviewing and debugging:** I asked it to review my Dockerfiles,
  `init.sh` scripts and `docker-compose.yml` against the subject rules
  (no infinite loops, no passwords in Dockerfiles, no `latest` tag), and to
  help read error logs.
- **Documentation:** I used it to help write and structure `README.md`,
  `USER_DOC.md` and `DEV_DOC.md`.

I tested every configuration myself in the VM, and I can explain every
part of it.
