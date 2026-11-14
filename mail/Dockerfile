# One image, three services (compose runs it as opendkim / postfix / dovecot).
FROM debian:trixie-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      postfix dovecot-imapd opendkim opendkim-tools ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /usr/local/bin/
ENTRYPOINT ["entrypoint.sh"]
