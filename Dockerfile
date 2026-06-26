ARG GO_IMAGE=m.daocloud.io/docker.io/library/golang:1.24-bookworm
ARG RUST_IMAGE=m.daocloud.io/docker.io/library/rust:1.96-bookworm
ARG RUNTIME_IMAGE=gcr.io/distroless/cc-debian12:nonroot

FROM ${GO_IMAGE} AS libwg-builder
ARG LIBWG_VERSION=container
WORKDIR /src

COPY libwg/wireguard-go/go.mod libwg/wireguard-go/go.sum ./libwg/wireguard-go/
RUN cd libwg/wireguard-go && go mod download

COPY libwg/wireguard-go ./libwg/wireguard-go
RUN set -eux; \
    cd libwg/wireguard-go; \
    printf 'package main\n\nconst Version = "%s"\n' "${LIBWG_VERSION}" > version.go; \
    cp version.go libwg/version.go; \
    CGO_ENABLED=1 go build -trimpath -buildmode=c-archive -o /out/libwg.a ./libwg

FROM ${RUST_IMAGE} AS rust-builder
ARG DEBIAN_FRONTEND=noninteractive
ARG APT_DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian
ARG APT_SECURITY_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian-security
WORKDIR /src

RUN set -eux; \
    if [ -n "${APT_DEBIAN_MIRROR}" ]; then \
      sed -i \
        -e "s#http://deb.debian.org/debian-security#${APT_SECURITY_MIRROR}#g" \
        -e "s#http://deb.debian.org/debian#${APT_DEBIAN_MIRROR}#g" \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends clang libclang-dev pkg-config ca-certificates; \
    rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock build.rs ./
COPY src ./src
COPY --from=libwg-builder /out/libwg.a ./libwg/libwg.a
COPY --from=libwg-builder /out/libwg.h ./libwg/libwg.h

RUN set -eux; \
    cargo build --release; \
    strip target/release/corplink-rs; \
    mkdir -p /empty-data

FROM ${RUNTIME_IMAGE}
LABEL org.opencontainers.image.title="corplink-rs"
LABEL org.opencontainers.image.description="Minimal corplink-rs container with userspace gVisor netstack and mixed HTTP/SOCKS5 proxy"

COPY --from=rust-builder /src/target/release/corplink-rs /usr/local/bin/corplink-rs
COPY --from=rust-builder --chown=nonroot:nonroot /empty-data/ /data/

ENV RUST_LOG=info
WORKDIR /data
USER nonroot:nonroot
EXPOSE 1080
STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/corplink-rs"]
CMD ["/data/config.json"]
