FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends nsd ldnsutils openssl gettext-base \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh resign.sh /usr/local/bin/
CMD ["entrypoint.sh"]
