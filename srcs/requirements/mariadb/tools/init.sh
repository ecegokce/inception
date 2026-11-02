#!/bin/bash
# First-run initialization for MariaDB, with no infinite loop and no
# background daemon: everything here is a finite sequence of commands that
# ends in `exec mariadbd`, which then becomes PID 1.
set -euo pipefail

DB_DATADIR=/var/lib/mysql

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# Idempotency check: mariadb-install-db creates the "mysql" system database,
# so its presence means a previous run already initialized this volume
# (the volume is a named, persistent volume, so this script re-runs on
# every container start, not just the very first one).
if [ ! -d "${DB_DATADIR}/mysql" ]; then
	echo "[mariadb-init] data directory is empty, running first-time setup"

	mariadb-install-db \
		--user=mysql \
		--datadir="${DB_DATADIR}" \
		--auth-root-authentication-method=normal \
		>/dev/null

	# `--bootstrap` starts mariadbd without networking and reads SQL
	# straight from stdin, then exits on EOF. This lets us seed the
	# database and users once, synchronously, instead of starting the
	# real daemon and polling/sleeping until it accepts connections.
	mariadbd --bootstrap --user=mysql --datadir="${DB_DATADIR}" <<-EOSQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
DELETE FROM mysql.user WHERE User='';
FLUSH PRIVILEGES;
EOSQL

	echo "[mariadb-init] first-time setup complete"
else
	echo "[mariadb-init] data directory already initialized, skipping setup"
fi

# Foreground, listening on all interfaces (see conf/50-server.cnf) — this
# becomes PID 1 so Docker can see crashes and the `restart` policy applies.
exec mariadbd --user=mysql --datadir="${DB_DATADIR}"
