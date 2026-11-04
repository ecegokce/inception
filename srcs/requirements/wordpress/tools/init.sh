#!/bin/bash
# Installs WordPress via wp-cli on first run only; ends with `exec php-fpm`
# so php-fpm becomes PID 1. No "wait for DB" loop here: the mariadb
# healthcheck + `depends_on: condition: service_healthy` in compose
# guarantees the DB already accepts connections by the time this runs.
set -euo pipefail

WP_PATH=/var/www/html

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

# Idempotency check: wp-config.php only exists after a successful install,
# so its presence means this volume already holds a configured WordPress
# (the volume is a named, persistent volume, so init.sh re-runs on every
# container start, not just the very first one).
if ! wp core is-installed --path="${WP_PATH}" --allow-root 2>/dev/null; then
	echo "[wordpress-init] no wp-config.php found, installing WordPress"

	wp core download --force --path="${WP_PATH}" --allow-root

	wp config create --force \
		--path="${WP_PATH}" \
		--dbname="${MYSQL_DATABASE}" \
		--dbuser="${MYSQL_USER}" \
		--dbpass="${DB_PASSWORD}" \
		--dbhost=mariadb \
		--allow-root

	wp core install \
		--path="${WP_PATH}" \
		--url="https://${DOMAIN_NAME}" \
		--title="${WP_TITLE}" \
		--admin_user="${WP_ADMIN_USER}" \
		--admin_password="${WP_ADMIN_PASSWORD}" \
		--admin_email="${WP_ADMIN_EMAIL}" \
		--skip-email \
		--allow-root

	# Subject requires at least two DB users, one of them an administrator;
	# this is the second, non-administrator one.
	wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
		--path="${WP_PATH}" \
		--role="${WP_USER_ROLE}" \
		--user_pass="${WP_USER_PASSWORD}" \
		--allow-root

	# wp-cli runs as root here, so files land as root:root; nginx (running
	# as its own non-root user) and php-fpm (www-data) both need to read
	# and write this tree, so hand it to www-data once, after install.
	chown -R www-data:www-data "${WP_PATH}"

	echo "[wordpress-init] WordPress install complete"
else
	echo "[wordpress-init] WordPress already installed, skipping install"
fi

exec php-fpm8.2 -F
