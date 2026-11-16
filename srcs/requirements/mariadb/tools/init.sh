#!/bin/bash

set -euo pipefail

DB_DATADIR=/var/lib/mysql

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

if [ ! -d "${DB_DATADIR}/mysql" ]; then
	echo "[mariadb-init] data directory is empty, running first-time setup"

	mariadb-install-db \
		--user=mysql \
		--datadir="${DB_DATADIR}" \
		--auth-root-authentication-method=normal \
		>/dev/null

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

exec mariadbd --user=mysql --datadir="${DB_DATADIR}"
