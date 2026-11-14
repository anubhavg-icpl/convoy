# convoy

Your own autonomous system on one VPS, as a Docker Compose stack.

| Service | Software | What you get |
|---|---|---|
| Routing | BIRD 2 + Routinator | BGP origination of one IPv6 prefix, RPKI route origin validation on peer imports, strict export filter |
| DNS | NSD + ldns | Authoritative zone, DNSSEC (ECDSA P-256, NSEC3), DNS over TLS, TLSA and DKIM records derived automatically |
| Time | chrony | Public NTP server with NTS |
| Mail | Postfix, Dovecot, OpenDKIM | Inbound SMTP with STARTTLS, DKIM signing, outbound DANE, IMAPS, MTA-STS, TLS-RPT |
| Web | nginx | HTTP/2 and HTTP/3, brotli, strict security headers, custom 404 |
| TLS | certbot | One Let's Encrypt cert shared by every service |

## Try it

Needs Docker with Compose v2.24 or newer. Nothing is published to the host.

```sh
./convoy check
```

This builds the images, boots an offline lab (a second BGP speaker, a local
RPKI source, a client container) and runs 32 end-to-end checks: BGP session
up, an RPKI-invalid route rejected, the signed zone verified, TLSA matching the
live certs, HTTP/3 negotiated, NTS-authenticated time, mail delivered and
DKIM-signed.

## Deploy

You need a VPS with a public IPv4 and IPv6 address, a domain, and for the
routing part an ASN, an IPv6 prefix and a BGP session with your upstream.

```sh
cp env.example .env      # fill in your domain, addresses, ASN, prefix
$EDITOR bird/peers.conf   # your BGP sessions
./convoy up
./convoy ds               # give this DS record to your registrar
./convoy cert             # after the domain's NS points at this host
```

Then point your registrar's glue records at `ns1.<domain>`, create a ROA for
your prefix at your RIR, and run `./convoy renew` weekly from a timer.

Before relying on it, read "Not covered by the gate" in [AGENTS.md](AGENTS.md):
the lab cannot test public ports, ACME or a real RPKI sync.

## Notes

- Routing is optional. Without an ASN, remove the `bird` and `routinator`
  services; everything else stands alone.
- HSTS is sent without `includeSubDomains` or `preload`, and MTA-STS starts in
  `testing` mode. Tighten both once the deployment has run cleanly for a while.
- Outbound DANE needs a DNSSEC-validating resolver on the host; none is
  shipped here.
