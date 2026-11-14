FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bird2 gettext-base \
 && rm -rf /var/lib/apt/lists/* \
 && chown -R root:root /etc/bird && chmod 755 /etc/bird
# ^ the package makes /etc/bird bird-owned 0750; bird runs here as root under
#   cap_drop ALL (no DAC_OVERRIDE), which then cannot read its own config.
COPY bird.conf.tmpl /etc/bird/bird.conf.tmpl
# bird has no env support, so the config is rendered at start. The template
# must stay free of literal `$` (envsubst runs unrestricted).
CMD ["sh", "-c", "mkdir -p /run/bird && envsubst < /etc/bird/bird.conf.tmpl > /run/bird/bird.conf && exec bird -f -c /run/bird/bird.conf"]
