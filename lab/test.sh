#!/bin/sh
# End-to-end checks against the running lab (started by `./convoy check`).
# Every check goes through the boundary a real client hits: BGP table, DNS
# query, TLS handshake, SMTP/IMAP session, HTTP response. Prints one line per
# check and exits non-zero if any failed.
cd "$(dirname "$0")/.." || exit 1
. ./env.example
dc() { docker compose --env-file env.example -p convoy-lab -f compose.yaml -f compose.lab.yaml "$@"; }
x() { svc=$1; shift; dc exec -T "$svc" "$@" 2>&1; }
CA=/certs/fullchain.pem # self-signed bootstrap cert doubles as its own CA
fail=0

# check NAME COMMAND...: passes when the command (usually a function below) exits 0.
check() {
  name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; fail=1; fi
}
# retry N COMMAND...: sessions, sync and delivery need a few seconds after boot.
retry() {
  n=$1; shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; n=$((n - 1)); sleep 2; done
  return 1
}
not() { ! "$@"; }
has() { grep -Eqi -- "$1"; }

# --- BGP + route origin validation ------------------------------------------
proto_up()  { x bird birdc show protocols | has "$1.*Established"; }
route()     { x bird birdc show route table master6 | has "^$1 "; }
only_own()  { [ "$(x peer birdc show route protocol up | grep -Ec '^[0-9a-f]+:.*/')" = 1 ] \
              && x peer birdc show route protocol up | has "^$PREFIX"; }
check "bgp: session with lab peer established"     retry 30 proto_up lab_peer
check "rov: RTR session to routinator established" retry 30 proto_up rpki1
check "rov: valid-origin route imported"           retry 15 route 2001:db8:100::/48
check "rov: unknown-origin route imported"         route 2001:db8:300::/48
check "rov: invalid-origin route rejected"         not route 2001:db8:200::/48
check "bgp: peer receives only the own prefix"     only_own

# --- DNS: signed zone, DoT, derived records ---------------------------------
dig()  { x probe kdig @dns "$@"; }
# SPKI SHA-256 of the cert a live endpoint presents: spki HOST:PORT SNI [s_client args]
spki() { x probe sh -c "openssl s_client -connect $1 -servername $2 $3 </dev/null 2>/dev/null \
  | openssl x509 -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1"; }
rrsig()    { dig +dnssec "$DOMAIN" SOA | has RRSIG; }
dot()      { dig +tls-ca=$CA "+tls-hostname=ns1.$DOMAIN" "$DOMAIN" SOA | has 'status: NOERROR'; }
https_rr() { dig +short "$DOMAIN" HTTPS | has 'alpn=.*h3'; }
dkim_rr()  { dig +short "mail._domainkey.$DOMAIN" TXT | has 'v=DKIM1'; }
tlsa()     { s=$(spki "$2" "$3" "$4"); [ -n "$s" ] && dig +short "$1" TLSA | has "3 1 1 $s"; }
check "dns: SOA answered with RRSIG"            rrsig
check "dns: signed zone verifies"               x dns ldns-verify-zone /data/zone.signed
check "dns: DoT answers on 853, cert verified"  dot
check "dns: HTTPS record advertises h3"         https_rr
check "dns: DKIM key published"                 dkim_rr
check "dane: TLSA 443 matches cert nginx serves"  tlsa "_443._tcp.$DOMAIN" "$DOMAIN:443" "$DOMAIN" ""
check "dane: TLSA 25 matches cert postfix serves" tlsa "_25._tcp.mail.$DOMAIN" "mail.$DOMAIN:25" "mail.$DOMAIN" "-starttls smtp"

# --- Web: HTTP/2, HTTP/3, headers, 404, compression -------------------------
curl()     { x probe curl -s --cacert $CA "$@"; }
httpv()    { [ "$(curl "$1" -o /dev/null -w '%{http_version}' "https://$DOMAIN/")" = "$2" ]; }
header()   { curl -D - -o /dev/null -H 'Accept-Encoding: br' "https://$DOMAIN/style.css" | has "^$1"; }
notfound() { [ "$(curl -o /dev/null -w '%{http_code}' "https://$DOMAIN/nope")" = 404 ] \
             && curl "https://$DOMAIN/nope" | has '404'; }
redirect() { [ "$(curl -o /dev/null -w '%{http_code} %{redirect_url}' "http://$DOMAIN/x")" = "301 https://$DOMAIN/x" ]; }
mtasts()   { curl "https://mta-sts.$DOMAIN/.well-known/mta-sts.txt" | has "^mx: mail.$DOMAIN"; }
check "web: HTTP/3 over QUIC"               httpv --http3-only 3
check "web: HTTP/2"                         httpv --http2 2
check "web: Alt-Svc advertises h3"          header 'alt-svc: h3='
check "web: HSTS"                           header 'strict-transport-security: max-age='
check "web: CSP"                            header 'content-security-policy: '
check "web: nosniff"                        header 'x-content-type-options: nosniff'
check "web: brotli"                         header 'content-encoding: br'
check "web: custom 404 page, 404 status"    notfound
check "web: plain HTTP redirects to HTTPS"  redirect
check "web: MTA-STS policy served"          mtasts

# --- NTP + NTS ---------------------------------------------------------------
# chronyd -Q: one-shot client that measures the offset and exits without
# setting the clock; it fails unless the NTS-KE handshake and auth succeed.
synced() { x ntp chronyc tracking | has 'Leap status *: Normal'; }
# maxdistance: with -x the lab server cannot discipline its clock, so its root
# dispersion is huge; this check is about authentication, not accuracy.
nts()    { x probe chronyd -Q -t 20 "server ntp.$DOMAIN iburst nts" "ntstrustedcerts $CA" "maxdistance 100000"; }
nts_ke() { x ntp chronyc serverstats | has 'NTS-KE connections accepted *: [1-9]'; }
check "ntp: server has a time source"            retry 30 synced
check "ntp: NTS-authenticated time served"      retry 5 nts
check "ntp: server counted the NTS-KE session"  nts_ke

# --- Mail: inbound over STARTTLS, alias, relay, DKIM, IMAP -------------------
swaks()     { x probe swaks --server "mail.$DOMAIN" "$@"; }
inbound()   { swaks --tls --tls-verify --tls-ca-path $CA --from someone@example.net \
              --to "abuse@$DOMAIN" --header 'Subject: lab-inbound'; }
relay()     { swaks --from a@example.net --to b@example.org; }
submit()    { x postfix sh -c "printf 'Subject: lab-signed\n\nhello\n' | sendmail -f me@$DOMAIN me@$DOMAIN"; }
# The cert has no name for dovecot (IMAP is localhost-only in production), so
# connect to it under the mail name.
imap()      { curl --connect-to "mail.$DOMAIN:993:dovecot:993" -u "me@$DOMAIN:$1" "imaps://mail.$DOMAIN/$2"; }
mailbox()   { imap "$MAIL_PASSWORD" "INBOX;UID=$1;SECTION=HEADER" | has "$2"; }
check "mail: inbound to alias accepted over STARTTLS" inbound
check "mail: relay to foreign domain refused"         not relay
check "mail: local submission accepted"               submit
check "mail: alias mail lands in mailbox (IMAPS)"     retry 15 mailbox 1 '^Subject: lab-inbound'
check "mail: submitted mail is DKIM-signed"           retry 15 mailbox 2 "^DKIM-Signature:.* d=$DOMAIN;"
check "mail: wrong IMAP password rejected"            not imap wrong INBOX

[ $fail = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $fail
