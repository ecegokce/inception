FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-cli php8.2-mysql php8.2-curl php8.2-gd \
        php8.2-mbstring php8.2-xml php8.2-zip php8.2-intl \
        default-mysql-client curl ca-certificates less && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/wp-cli.phar \
        https://github.com/wp-cli/wp-cli/releases/download/v2.11.0/wp-cli-2.11.0.phar && \
    chmod +x /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec php /usr/local/bin/wp-cli.phar "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

VOLUME /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/init.sh"]
