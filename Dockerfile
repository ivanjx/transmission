# Dockerfile for Transmission release build (daemon + web client)
# Use official Ubuntu LTS as base
FROM ubuntu:24.04

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    libevent-dev \
    zlib1g-dev \
    libminiupnpc-dev \
    libsystemd-dev \
    ca-certificates \
    python3 \
    python3-pip \
    rsass \
    perl \
    esbuild \
    curl

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Set working directory
WORKDIR /build
COPY . /build

# Build Transmission (daemon and web client)
RUN cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release -DENABLE_DAEMON=ON -DENABLE_WEB=ON -DREBUILD_WEB=ON \
    && cmake --build build-release --target transmission-daemon transmission-web -- -j$(nproc)

# Final image for running Transmission daemon and web client
FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    libcurl4 \
    libevent-2.1-7 \
    zlib1g \
    libminiupnpc17 \
    && rm -rf /var/lib/apt/lists/*

# Copy built binaries from builder
COPY --from=0 /build/build-release/daemon/transmission-daemon /usr/local/bin/transmission-daemon
COPY --from=0 /build/build-release/web/public_html /usr/local/share/transmission/web

# Default settings
ENV TRANSMISSION_WEB_HOME=/usr/local/share/transmission/web
COPY settings.json /config/settings.json

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/transmission-daemon"]
CMD ["--foreground", "--config-dir", "/config"]
