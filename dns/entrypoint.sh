#!/bin/sh -e
# NSD authoritative server for one DNSSEC-signed zone, with DoT on 853.
#
# Invariants:
#  - Keys in /data/keys are generated once and never rotated here: the DS record
#    at the registrar is tied to the KSK. Losing the `dnsdata` volume means a new
#    KSK and a broken chain of trust until the DS is replaced.
#  - NSD only ever serves /data/zone.signed, which resign.sh rebuilds.
D=${DOMAIN:?}

mkdir -p /data/keys /run/nsd
cd /data/keys
if ! ls K*.private >/dev/null 2>&1; then
  ldns-keygen -k -a ECDSAP256SHA256 "$D" # KSK
  ldns-keygen -a ECDSAP256SHA256 "$D"    # ZSK
fi
echo "DS record for the registrar:"
cat K*.ds # written by ldns-keygen -k for the KSK only

cat > /run/nsd/nsd.conf <<EOF
server:
  username: nsd
  zonesdir: /data
  hide-version: yes
  ip-address: 0.0.0.0
  ip-address: ::
  # TLS is only served on addresses that name tls-port explicitly.
  ip-address: 0.0.0.0@853
  ip-address: ::@853
  tls-port: 853
  tls-service-key: /certs/privkey.pem
  tls-service-pem: /certs/fullchain.pem
remote-control:
  control-enable: yes
  control-interface: /run/nsd/nsd.ctl
zone:
  name: $D
  zonefile: zone.signed
EOF
# Must stay the last thing appended: these lines belong to the zone clause.
[ -z "$SECONDARY_IP" ] || printf '  notify: %s NOKEY\n  provide-xfr: %s NOKEY\n' \
  "$SECONDARY_IP" "$SECONDARY_IP" >> /run/nsd/nsd.conf

resign.sh
# Signatures last 30 days; weekly re-sign keeps three weeks of slack.
# ponytail: sleep loop, not cron. Restarting the container re-signs anyway.
(while sleep 604800; do resign.sh; done) &
exec nsd -d -c /run/nsd/nsd.conf
