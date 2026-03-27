# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WINEPREFIX=/wine-prefix \
    WINEDEBUG=-all

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' >/etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    dpkg --add-architecture i386 \
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
        tigervnc-standalone-server \
        tini \
        unzip \
        wine \
        wine32 \
        wine64 \
        winbind \
        xauth \
        xrdp \
    && apt-get clean

RUN mkdir -p /var/log/pob /run/xrdp /root

COPY docker/entrypoint.sh /usr/local/bin/pob-entrypoint
COPY docker/pob-session.sh /usr/local/bin/pob-session

RUN chmod +x /usr/local/bin/pob-entrypoint /usr/local/bin/pob-session

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD netstat -ltn | grep -q ':3389 ' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/pob-entrypoint"]
