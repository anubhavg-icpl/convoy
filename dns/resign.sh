#!/bin/sh -e
# Build the unsigned zone, sign it, tell NSD. Run on every start, weekly, and
# by hand after editing zone.tmpl:  docker compose exec dns resign.sh
#
# Unsigned zone = zone.tmpl (envsubst: DOMAIN, IPV4, IPV6 only, so $ORIGIN and
# $TTL survive) + records derived from live key material, so they can never
# drift from what the servers actually present:
#   TLSA 3 1 1  = SHA-256 of the SPKI of /certs/fullchain.pem (web 443, SMTP 25)
#   mail._domainkey TXT = /dkim/mail.txt written by opendkim-genkey
cd /data

spki=$(openssl x509 -in /certs/fullchain.pem -noout -pubkey \
  | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)
{
  envsubst '$DOMAIN $IPV4 $IPV6' < /etc/nsd/zone.tmpl
  echo "_443._tcp IN TLSA 3 1 1 $spki"
  echo "_25._tcp.mail IN TLSA 3 1 1 $spki"
  cat /dkim/mail.txt 2>/dev/null || true
} > zone

keys=$(ls keys/K*.private | sed 's/\.private$//')
# -n -t 0: NSEC3, zero extra iterations, no salt (RFC 9276 section 3.1).
# -u: SOA serial = unix time, so every re-sign bumps it without editing the zone.
# shellcheck disable=SC2086
ldns-signzone -n -t 0 -u -e "$(date -u -d '+30 days' +%Y%m%d)" \
  -o "$DOMAIN" -f zone.signed.new zone $keys
mv zone.signed.new zone.signed

# Not running yet on first boot; entrypoint starts NSD right after.
nsd-control -c /run/nsd/nsd.conf reload >/dev/null 2>&1 || true
