#!/bin/bash
# Generates the self-signed TLS certificate on first run only, then always
# finishes with `exec nginx`, making nginx PID 1.
set -euo pipefail

CERT_DIR=/etc/nginx/ssl
CERT_FILE="${CERT_DIR}/${DOMAIN_NAME}.crt"
KEY_FILE="${CERT_DIR}/${DOMAIN_NAME}.key"

mkdir -p "${CERT_DIR}"

# Idempotency check: the cert/key don't live on a persistent volume, but
# the container can still be restarted without being rebuilt, so this
# avoids regenerating (and thus silently rotating) the cert on every
# restart for no reason.
if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
	echo "[nginx-init] generating self-signed certificate for ${DOMAIN_NAME}"
	openssl req -x509 -nodes \
		-days 365 \
		-newkey rsa:2048 \
		-keyout "${KEY_FILE}" \
		-out "${CERT_FILE}" \
		-subj "/C=FR/ST=IDF/L=Paris/O=42/OU=inception/CN=${DOMAIN_NAME}"
	chmod 600 "${KEY_FILE}"
else
	echo "[nginx-init] certificate already present, skipping generation"
fi

exec nginx -g "daemon off;"
