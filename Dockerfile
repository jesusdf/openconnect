FROM docker.io/alpine:3.17.2

# BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
# COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo 'null')"
ARG BUILD_DATE 
ARG COMMIT_SHA

# https://github.com/opencontainers/image-spec/blob/master/spec.md
LABEL org.opencontainers.image.title='openconnect' \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.description='AnyConnect-compatible client to route host traffic' \
      org.opencontainers.image.documentation='https://github.com/jesusdf/openconnect/blob/master/README.md' \
      org.opencontainers.image.version='1.0' \
      org.opencontainers.image.source='https://github.com/jesusdf/openconnect' \
      org.opencontainers.image.revision="${COMMIT_SHA}"

RUN apk add --no-cache openconnect \
    # add vpn-slice with dependencies (dig) https://github.com/dlenski/vpn-slice
    && apk add --no-cache bash python3 bind-tools py3-pip tzdata ifupdown-ng \
    && pip3 install "vpn-slice[dnspython,setproctitle]" \
    && apk del py3-pip \
    && rm -f /sbin/apk \
             /usr/bin/wget \
             /usr/sbin/sendmail \
             /usr/bin/nc

COPY ./entrypoint.sh /vpn/entrypoint.sh
WORKDIR /vpn

HEALTHCHECK --start-period=15s --retries=1 \
  CMD pgrep openconnect || exit 1

ENTRYPOINT ["/vpn/entrypoint.sh"]
