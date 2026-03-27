# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' >/etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bubblewrap \
        ca-certificates \
        curl \
        dbus \
        flatpak \
        flatpak-builder \
        git \
        xdg-dbus-proxy \
    && apt-get clean

WORKDIR /workspace

