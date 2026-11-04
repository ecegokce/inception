# Same base/version policy as the other services: penultimate stable Debian,
# explicit patch tag, no "latest".
FROM debian:12.11-slim

# php8.2-fpm: the FastCGI process manager nginx will talk to (no nginx here).
# php8.2-cli: provides the `php` binary that wp-cli needs to run itself.
# php8.2-mysqli/mysql: MySQL/MariaDB driver for WordPress's DB layer.
# Remaining php8.2-* packages: extensions WordPress core expects/uses.
# default-mysql-client: lets init.sh/wp-cli check DB connectivity.
# curl: used once, at build time, to fetch wp-cli.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-cli php8.2-mysql php8.2-curl php8.2-gd \
        php8.2-mbstring php8.2-xml php8.2-zip php8.2-intl \
        default-mysql-client curl ca-certificates less && \
    rm -rf /var/lib/apt/lists/*

# wp-cli, pinned to a specific release tag (never "latest") so builds are
# reproducible; installed at build time, so no network dependency at runtime.
RUN curl -fsSL -o /usr/local/bin/wp-cli.phar \
        https://github.com/wp-cli/wp-cli/releases/download/v2.11.0/wp-cli-2.11.0.phar && \
    chmod +x /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec php /usr/local/bin/wp-cli.phar "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

# listen on 0.0.0.0:9000 (not the default 127.0.0.1) so nginx, running in
# a separate container, can reach php-fpm over the docker network.
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

# Shared with nginx via the "wordpress_data" named volume so nginx can
# serve the static files php-fpm writes (uploads, themes, etc.).
VOLUME /var/www/html

EXPOSE 9000

# init.sh installs/configures WordPress on first run only, then always
# finishes with `exec php-fpm8.2 -F`, making php-fpm PID 1.
ENTRYPOINT ["/usr/local/bin/init.sh"]
