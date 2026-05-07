FROM debian:bookworm-slim

# gettext-base  → provides envsubst (config template rendering)
# curl          → used by OpenFang tools and the binary download
# ca-certificates → HTTPS for Ollama + Discord + RSS feeds
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Download the OpenFang binary from GitHub releases.
# Supports linux/amd64 (x86_64) and linux/arm64 (aarch64).
RUN set -e; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
      x86_64)  TARGET="x86_64-unknown-linux-gnu" ;; \
      aarch64) TARGET="aarch64-unknown-linux-gnu" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac; \
    URL="https://github.com/RightNow-AI/openfang/releases/latest/download/openfang-${TARGET}.tar.gz"; \
    echo "Downloading $URL ..."; \
    curl -fsSL "$URL" | tar -xz -C /usr/local/bin; \
    chmod +x /usr/local/bin/openfang; \
    openfang --version

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 4200

ENTRYPOINT ["/docker-entrypoint.sh"]
