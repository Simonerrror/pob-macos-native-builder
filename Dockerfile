FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WINEPREFIX=/wine-prefix \
    WINEDEBUG=-all

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        cabextract \
        curl \
        dbus-x11 \
        fluxbox \
        net-tools \
        procps \
        tini \
        unzip \
        wine \
        wine32 \
        wine64 \
        winbind \
        xauth \
        xorgxrdp \
        xrdp \
        xserver-xorg-core \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/pob /run/xrdp /root

COPY docker/entrypoint.sh /usr/local/bin/pob-entrypoint
COPY docker/pob-session.sh /usr/local/bin/pob-session

RUN chmod +x /usr/local/bin/pob-entrypoint /usr/local/bin/pob-session

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD netstat -ltn | grep -q ':3389 ' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/pob-entrypoint"]
