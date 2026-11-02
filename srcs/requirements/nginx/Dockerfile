FROM debian:12.11-slim

# nginx: the only web-facing service, and the ONLY entrypoint per subject.
# openssl: used once at startup to generate the self-signed TLS certificate.
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl && \
    rm -rf /var/lib/apt/lists/*

# TLSv1.2/1.3 only, single vhost for egokce.42.fr, fastcgi_pass to the
# wordpress container — see conf/nginx.conf for details.
COPY conf/nginx.conf /etc/nginx/nginx.conf

COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

# Served and written by php-fpm in the wordpress container; shared here
# read/write via the same named volume so nginx can serve the files
# WordPress manages (uploads, themes, etc.).
VOLUME /var/www/html

EXPOSE 443

# init.sh generates the self-signed cert on first run only, then always
# finishes with `exec nginx -g 'daemon off;'`, making nginx PID 1.
ENTRYPOINT ["/usr/local/bin/init.sh"]
