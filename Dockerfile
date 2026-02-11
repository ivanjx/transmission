FROM docker.io/alpine:3.22 AS base

FROM base AS builder

RUN set -ex && \
	apk add --no-cache --upgrade \
		git \
		python3 \
		build-base \
		ccache \
		cmake \
		curl-dev \
		gettext-dev \
		openssl-dev \
		linux-headers \
		samurai \
        nodejs \
        npm

WORKDIR /app
COPY . .

ENV CCACHE_DIR=/root/.ccache
ENV CCACHE_BASEDIR=/app
ENV CCACHE_COMPILERCHECK=content

RUN --mount=type=cache,id=transmission-ccache,target=/root/.ccache \
    --mount=type=cache,id=transmission-obj,target=/app/obj \
    ccache -z && \
    cmake -S . -B obj -G Ninja \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_C_COMPILER_LAUNCHER=ccache \
        -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -D ENABLE_CLI=OFF \
        -D ENABLE_DAEMON=ON \
        -D ENABLE_GTK=OFF \
        -D ENABLE_MAC=OFF \
        -D ENABLE_QT=OFF \
        -D ENABLE_TESTS=OFF \
        -D ENABLE_UTILS=OFF \
        -D ENABLE_UTP=ON \
        -D ENABLE_WERROR=OFF \
        -D ENABLE_DEPRECATED=OFF \
        -D ENABLE_NLS=ON \
        -D INSTALL_WEB=ON \
        -D REBUILD_WEB=ON \
        -D INSTALL_DOC=OFF \
        -D INSTALL_LIB=OFF \
        -D RUN_CLANG_TIDY=OFF \
        -D WITH_INOTIFY=ON \
        -D WITH_CRYPTO="openssl" \
        -D WITH_SYSTEMD=OFF && \
    cmake --build obj --config Release && \
    cmake --build obj --config Release --target install/strip && \
    ccache -s

FROM base AS runtime

RUN set -ex && \
    apk update && \
    apk add --no-cache --upgrade libcurl libintl libgcc libstdc++ tzdata

COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share /usr/local/share

ENTRYPOINT [ "transmission-daemon" ]
CMD [ "--config-dir", "/config", "--foreground" ]
