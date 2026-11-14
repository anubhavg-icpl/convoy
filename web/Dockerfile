# Debian's own nginx: trixie's 1.26 build already has --with-http_v3_module and
# Brotli ships as a packaged dynamic module, so there is no source build and
# security fixes arrive through apt (rebuild the image to pick them up).
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx libnginx-mod-http-brotli-filter gettext-base \
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log
COPY site.conf.tmpl /etc/nginx/site.conf.tmpl
# envsubst is limited to $DOMAIN so nginx's own $variables survive.
CMD ["sh", "-c", "envsubst '$DOMAIN' < /etc/nginx/site.conf.tmpl > /etc/nginx/sites-enabled/site && exec nginx -g 'daemon off;'"]
