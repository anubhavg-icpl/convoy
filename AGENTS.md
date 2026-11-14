# convoy

A whole hobby autonomous system on one VPS, as Docker Compose: BGP with RPKI
route origin validation (BIRD 2 + Routinator), authoritative DNS with DNSSEC,
DANE and DoT (NSD), NTP with NTS (chrony), mail (Postfix, Dovecot, OpenDKIM)
and a static site over HTTP/2 + HTTP/3 (nginx). Config is plain files rendered
from `.env`; there is no application code.

## Commands

| Command | What it does |
|---|---|
| `./convoy check` | The gate (CI runs it too: `.github/workflows/check.yml`). Builds everything, boots the offline lab, runs `lab/test.sh`, tears down. Needs only Docker. |
| `./convoy lab <compose args>` | Poke at the lab: `./convoy lab up -d --build`, `./convoy lab logs bird`, `sh lab/test.sh` |
| `./convoy up` | Production stack (needs `.env`, copy from `env.example`) |
| `./convoy ds` | Print the DS record for the registrar |
| `./convoy cert` / `renew` | Let's Encrypt cert via HTTP-01, then restart TLS consumers |

## Structure

One directory per service image (`bird/ dns/ ntp/ mail/ web/`); `mail/` is one
image run three ways (opendkim, postfix, dovecot) selected by its entrypoint
argument. `compose.yaml` is production. `compose.lab.yaml` is an override that
moves the same images onto one private bridge and adds a BGP peer, a
SLURM-fed Routinator and a `probe` client container. `lab/` holds the lab's
fixtures and the test script.

## Conventions

- Defaults are documentation ranges (example.com, 192.0.2.0/24, 2001:db8::/32,
  AS64496). Real values live only in the untracked `.env`.
- Config is rendered at container start with `envsubst` or `postconf -e`; no
  templating engine, no generated files in the repo.
- Every container runs with `cap_drop: ALL` plus the few capabilities it needs.
- Derived DNS records (TLSA, DKIM) are computed in `dns/resign.sh` from the
  live cert and key, never hand-written into `dns/zone.tmpl`.
- Image versions are pinned; base images come from Debian trixie packages.

## Landmines

- **One cert, five consumers.** dns (DoT), web, postfix, dovecot and ntp (NTS)
  all read `/certs/fullchain.pem`. Replacing it without `./convoy reload-certs`
  leaves stale TLSA records in the zone: DANE validation then fails for mail
  and web. The `certs` service only writes a self-signed cert when none exists.
- **`bird/bird.conf.tmpl` must contain no literal `$`** other than the four
  template variables; `envsubst` runs unrestricted over it.
- **`export_own` is the only leak guard.** Every BGP session must use the
  `transit` or `peer` template. A session with a looser export leaks routes.
- **`import table on` in the `peer` template is load-bearing.** Without it,
  routes received before the RTR session is up are judged "unknown" forever
  and RPKI-invalid routes stay installed after every restart.
- **Routinator listens on `[::]` in the lab, `0.0.0.0` in production.** BIRD
  tries only the first address a name resolves to; the lab resolves to IPv6.
- **`in` is a reserved word in sh**; the exec helper in `lab/test.sh` is `x`.
- **`birdc show route` prints the ROA table too.** Route assertions must name
  `table master6` or an invalid prefix "appears" via its ROA.
- **Lab chrony runs `-x` with `local stratum 10`** so it never touches the
  host clock and needs no upstream. Its root dispersion is therefore huge;
  the NTS check sets `maxdistance` and tests authentication, not accuracy.
- **Mail checks address messages by IMAP UID 1 and 2**, so they need the fresh
  volumes `./convoy check` provides. Re-running `sh lab/test.sh` against a
  used lab still passes but no longer proves new delivery.
- **DNSSEC keys live in the `dnsdata` volume.** Deleting it changes the DS
  record; the zone goes bogus until the registrar is updated.
- **Zone signatures last 30 days**, re-signed weekly by a loop in
  `dns/entrypoint.sh`. A dns container that is stopped for a month serves
  expired signatures on start until the first re-sign completes.

## Not covered by the gate

`./convoy check` cannot exercise host networking, public ports, ACME issuance,
a real RPKI sync, or kernel route installation. Those paths in `compose.yaml`
and the `cert`/`renew` commands are untested until run on a real host.
