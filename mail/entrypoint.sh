#!/bin/sh -e
# Mail stack: `entrypoint.sh opendkim|postfix|dovecot`. One mailbox, me@DOMAIN;
# postmaster/abuse/noc/tech/root alias to it.
#
# Invariants:
#  - Postfix delivers to Maildir at /var/mail/vhosts/DOMAIN/me/ as uid/gid 5000;
#    Dovecot reads the same volume with the same ids. Change both or neither.
#  - Only locally submitted mail (sendmail inside the postfix container) is DKIM
#    signed: the milter signs for localhost clients only, and there is no
#    submission port.
#  - Config is generated here from env on every start; do not hand-edit files
#    inside the containers.
D=${DOMAIN:?}

case "$1" in
opendkim)
  [ -s /dkim/mail.private ] || opendkim-genkey -D /dkim -d "$D" -s mail -b 2048
  chown opendkim /dkim/mail.private
  chmod 644 /dkim/mail.txt # dns container publishes this record
  printf '%s\n' "Domain $D" 'Selector mail' 'KeyFile /dkim/mail.private' \
    'Socket inet:8891' 'Canonicalization relaxed/simple' 'Mode s' \
    'UserID opendkim' > /run/opendkim.conf
  exec opendkim -f -x /run/opendkim.conf
  ;;

postfix)
  postconf -e \
    "compatibility_level = 3.10" \
    "myhostname = mail.$D" "mydomain = $D" "myorigin = $D" \
    "mydestination = localhost" \
    "mynetworks = 127.0.0.0/8 [::1]/128" \
    "inet_protocols = all" \
    "maillog_file = /dev/stdout" \
    "virtual_mailbox_domains = $D" \
    "virtual_mailbox_base = /var/mail/vhosts" \
    "virtual_mailbox_maps = inline:{ me@$D=$D/me/ }" \
    "virtual_alias_maps = inline:{ postmaster@$D=me@$D, abuse@$D=me@$D, noc@$D=me@$D, tech@$D=me@$D, root@$D=me@$D }" \
    "virtual_uid_maps = static:5000" "virtual_gid_maps = static:5000" \
    "smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination" \
    "smtpd_tls_cert_file = /certs/fullchain.pem" \
    "smtpd_tls_key_file = /certs/privkey.pem" \
    "smtpd_tls_security_level = may" \
    "smtpd_tls_protocols = >=TLSv1.2" "smtpd_tls_mandatory_protocols = >=TLSv1.2" \
    "smtpd_tls_ciphers = high" "smtpd_tls_mandatory_ciphers = high" \
    "smtp_tls_protocols = >=TLSv1.2" \
    "smtp_tls_security_level = dane" "smtp_dns_support_level = dnssec" \
    "smtpd_milters = inet:opendkim:8891" "non_smtpd_milters = inet:opendkim:8891" \
    "milter_default_action = accept"
  chown 5000:5000 /var/mail/vhosts
  # Debian chroots smtpd. `postfix start-fg` itself runs configure-instance.sh,
  # which syncs resolv.conf/hosts into the chroot so `opendkim` resolves.
  exec postfix start-fg
  ;;

dovecot)
  # Single mailbox, so a one-line passwd-file. It is world-readable on purpose:
  # the auth process is unprivileged and the container holds nothing else.
  echo "me@$D:{PLAIN}${MAIL_PASSWORD:?}" > /run/dovecot-users
  cat > /run/dovecot.conf <<EOF
dovecot_config_version = 2.4.0
dovecot_storage_version = 2.4.0
protocols = imap
log_path = /dev/stderr
ssl = required
ssl_server_cert_file = /certs/fullchain.pem
ssl_server_key_file = /certs/privkey.pem
mail_driver = maildir
mail_path = /var/mail/vhosts/%{user | domain}/%{user | username}
mail_uid = 5000
mail_gid = 5000
first_valid_uid = 5000
passdb passwd-file {
  passwd_file_path = /run/dovecot-users
}
userdb static {
}
EOF
  exec dovecot -F -c /run/dovecot.conf
  ;;

*) exec "$@" ;;
esac
