# Debian 12 "bookworm" is the penultimate stable Debian release (13 "trixie"
# is current stable as of writing) — subject requires penultimate stable,
# and forbids the "latest" tag, so a pinned patch version is used.
FROM debian:12.11-slim

# mariadb-server: the only package we actually need; it brings mariadbd and
# the install/admin client tools with it. No recommends to keep the image lean.
RUN apt-get update && \
    apt-get install -y --no-install-recommends mariadb-server && \
    rm -rf /var/lib/apt/lists/* /var/lib/mysql/*

# Custom bind-address / logging tweaks, see conf/50-server.cnf for why.
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

COPY tools/init.sh /usr/local/bin/init.sh
# chmod happens inside the image build, not on the host: Windows/OneDrive
# filesystems do not reliably preserve the executable bit.
RUN chmod +x /usr/local/bin/init.sh

# MariaDB stores its data files here; the named volume is mounted at this
# path in docker-compose.yml so data survives container recreation.
VOLUME /var/lib/mysql

EXPOSE 3306

# init.sh does first-run bootstrap (or skips it) and always finishes with
# `exec mariadbd`, so mariadbd itself becomes PID 1 in the foreground.
ENTRYPOINT ["/usr/local/bin/init.sh"]
