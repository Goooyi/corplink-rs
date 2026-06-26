# Container Usage

This image runs `corplink-rs` in userspace netstack mode and exposes one mixed
HTTP/SOCKS5 proxy port. It does not require `/dev/net/tun`, `NET_ADMIN`,
privileged mode, host route changes, or host DNS changes.

## Build

```bash
docker build -t corplink-rs:patched .
```

The Dockerfile uses mirror-friendly defaults for the Docker Hub builder images
and Tsinghua Debian apt mirrors in the Rust builder stage. If those mirrors are
slow in your environment, override them:

```bash
docker build \
  --build-arg GO_IMAGE=golang:1.24-bookworm \
  --build-arg RUST_IMAGE=rust:1.96-bookworm \
  --build-arg RUNTIME_IMAGE=gcr.io/distroless/cc-debian12:nonroot \
  -t corplink-rs:patched .
```

For Docker Hub later:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t YOUR_DOCKERHUB_USER/corplink-rs:patched \
  .
```

## Config

The container defaults to `/data/config.json`. For proxy-only container use,
set at least:

```json
{
  "socks5_listen": "0.0.0.0:1080",
  "auto_setup_routes": false,
  "use_vpn_dns": false,
  "route_mode": "split",
  "force_protocol": "tcp"
}
```

The existing key is still named `socks5_listen` for compatibility, but the
listener accepts both SOCKS5 and HTTP proxy traffic on the same port.

`corplink-rs` persists login state back to the config file and writes cookies
under `/data`, so mount `/data` read-write.

## Run

```bash
docker run -d --name corplink-rs \
  --read-only \
  -p 1089:1080 \
  -v "$PWD/config-data:/data" \
  corplink-rs:patched
```

Use either proxy protocol on the same host port:

```bash
curl --socks5-hostname 127.0.0.1:1089 http://intranet.example/
curl -x http://127.0.0.1:1089 http://intranet.example/
```
