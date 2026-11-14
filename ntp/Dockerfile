FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends chrony ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && chown root:root /var/lib/chrony
COPY chrony.conf /etc/chrony/chrony.conf
# -u root: the NTS key in /certs is root-only and shared with other services.
# The container is still confined by cap_drop ALL + SYS_TIME/NET_BIND_SERVICE,
# which is also why /var/lib/chrony is chowned to root above: without
# DAC_OVERRIDE root cannot write a _chrony-owned directory.
CMD ["chronyd", "-d", "-u", "root"]
