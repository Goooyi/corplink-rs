# corplink-rs patched container

This fork packages `corplink-rs` as a small, unprivileged container for proxy-only
Corplink access.

The container runs WireGuard in userspace through `wireguard-go` and gVisor
netstack. It does not create a kernel TUN device, does not need `NET_ADMIN`, does
not change host routes, and does not change host DNS. It exposes one local proxy
port that accepts both SOCKS5 and HTTP proxy traffic.

## What Is Different In This Fork

- Uses `Goooyi/wireguard-go` instead of `PinkD/wireguard-go`.
- Includes the TCP bind stability fix needed for Corplink TCP gateways.
- Adds a mixed HTTP/SOCKS5 proxy listener on one port.
- Adds a minimal distroless container image.
- Keeps config-file based operation. No web UI is required.

Current fork commits:

- `corplink-rs`: patched container variant, local image tag `corplink-rs:patched`
- `wireguard-go`: `0f2c9ae Add mixed HTTP and SOCKS5 proxy`

## Upstream And Credits

This fork is built on top of work from several projects:

- [PinkD/corplink-rs](https://github.com/PinkD/corplink-rs): upstream Rust
  Corplink client.
- [PinkD/wireguard-go](https://github.com/PinkD/wireguard-go): modified
  `wireguard-go` library used by upstream `corplink-rs`.
- [WireGuard/wireguard-go](https://git.zx2c4.com/wireguard-go/): original
  userspace WireGuard implementation.
- [gVisor netstack](https://gvisor.dev/docs/user_guide/networking/): userspace
  TCP/IP stack used for proxy-only VPN access without a kernel TUN interface.
- [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless):
  minimal Debian-based runtime image used by the container.
- [riba2534/corplink-web](https://hub.docker.com/r/riba2534/corplink-web):
  inspiration for the zero-privilege container workflow and single mixed proxy
  port. This fork does not include its web UI.

This repository keeps the upstream license file. See [license.txt](license.txt).

## Runtime Model

Set `socks5_listen` in the config and the program enters userspace netstack
proxy mode.

In this mode:

- no root is required
- no `/dev/net/tun` is required
- no `--privileged` is required
- no `NET_ADMIN` capability is required
- no system routes are installed
- no host DNS files are changed
- DNS lookups for proxied hostnames are resolved inside the VPN netstack

The config field is still named `socks5_listen` for compatibility, but the
listener accepts both:

- SOCKS5
- HTTP proxy, including `CONNECT`

## Minimal Config

Create a writable directory and put `config.json` in it:

```bash
mkdir -p ./config-data
```

Example `./config-data/config.json`:

```json
{
  "company_name": "your_company_name",
  "username": "your_username",
  "password": "your_password",
  "platform": "feilian",
  "interface_name": "corplink",
  "device_name": "corplink-rs-container",
  "socks5_listen": "0.0.0.0:1080",
  "vpn_select_strategy": "default",
  "use_vpn_dns": false,
  "auto_setup_routes": false,
  "route_mode": "split",
  "force_protocol": "tcp"
}
```

Notes:

- JSON does not allow comments.
- `force_protocol: "tcp"` is useful for Corplink deployments where UDP does not
  work or the official client selects TCP.
- `corplink-rs` updates the config with generated keys, login state, server
  metadata, and device data.
- Cookies are written next to the config file inside the mounted data directory.
- Mount the whole directory, not only the file.

## Optional Proxy Auth

Add these fields to require proxy authentication:

```json
{
  "socks5_username": "proxy_user",
  "socks5_password": "proxy_password"
}
```

SOCKS5 uses username/password auth. HTTP proxy uses Basic
`Proxy-Authorization`.

## Build The Image

Build locally:

```bash
docker build -t corplink-rs:patched .
```

The Dockerfile uses a multi-stage build:

- Go builder builds `libwg.a`
- Rust builder builds `corplink-rs`
- distroless Debian 12 runtime contains only the final binary and runtime libs

The final image built locally is about `49MB` on arm64.

The Dockerfile defaults to mirror-friendly Docker Hub builder image names and
Tsinghua Debian apt mirrors. If your network works better with upstream images:

```bash
docker build \
  --build-arg GO_IMAGE=golang:1.24-bookworm \
  --build-arg RUST_IMAGE=rust:1.96-bookworm \
  --build-arg RUNTIME_IMAGE=gcr.io/distroless/cc-debian12:nonroot \
  -t corplink-rs:patched .
```

## Run

```bash
docker run -d --name corplink-rs \
  --read-only \
  -p 1089:1080 \
  -v "$PWD/config-data:/data" \
  corplink-rs:patched
```

The image defaults to:

```text
/usr/local/bin/corplink-rs /data/config.json
```

Check logs:

```bash
docker logs -f corplink-rs
```

Expected ready line:

```text
mixed HTTP/SOCKS5 proxy ready at 0.0.0.0:1080
```

## Use The Proxy

SOCKS5:

```bash
curl --socks5-hostname 127.0.0.1:1089 http://intranet.example/
```

HTTP proxy:

```bash
curl -x http://127.0.0.1:1089 http://intranet.example/
```

With auth:

```bash
curl --socks5-hostname proxy_user:proxy_password@127.0.0.1:1089 http://intranet.example/
curl -x http://proxy_user:proxy_password@127.0.0.1:1089 http://intranet.example/
```

## Multi-Architecture Build

The Dockerfile is intended to build for both `linux/arm64` and `linux/amd64`.

Local multi-arch build test:

```bash
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t corplink-rs:patched \
  .
```

Later, after Docker Hub login and repository setup:

```bash
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t YOUR_DOCKERHUB_USER/corplink-rs:patched \
  --push \
  .
```

You do not need Docker Hub for local use. Docker Hub is only needed if you want
to pull this image from another machine or share it.

## Push To Docker Hub

First create a Docker Hub repository, for example:

```text
YOUR_DOCKERHUB_USER/corplink-rs
```

Log in locally:

```bash
docker login
```

For a quick single-architecture push from the image already built on this
machine:

```bash
docker tag corplink-rs:patched YOUR_DOCKERHUB_USER/corplink-rs:patched
docker push YOUR_DOCKERHUB_USER/corplink-rs:patched
```

For a proper multi-architecture image, build and push directly with Buildx:

```bash
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t YOUR_DOCKERHUB_USER/corplink-rs:patched \
  --push \
  .
```

On another machine:

```bash
docker pull YOUR_DOCKERHUB_USER/corplink-rs:patched
docker run -d --name corplink-rs \
  --read-only \
  -p 1089:1080 \
  -v "$PWD/config-data:/data" \
  YOUR_DOCKERHUB_USER/corplink-rs:patched
```

Do not bake `config.json`, cookies, or other secrets into the image. Mount a
writable `/data` directory at runtime instead.

## Native Binary Mode

The non-container binary can still be built and run directly. Without
`socks5_listen`, it uses the traditional WireGuard/TUN path and may require
root/admin privileges to create interfaces, install routes, or change DNS.

Build manually:

```bash
cd libwg
./build.sh
cd ..
cargo build --release
```

Run:

```bash
RUST_LOG=info ./target/release/corplink-rs config.json
```

## TODO

- Measure memory after comparing against an actively connected `corplink-web`
  session, not only an idle web UI listener.
- Investigate feature-gating or stripping unused QR/image/terminal dependencies
  for the container build.
- Consider a tiny optional web UI only for login flows that benefit from browser
  interaction, such as QR, SSO, or manual verification.
- Consider a `no-ui` or `proxy-only` build profile that removes QR/login display
  helpers when config-file login is enough.
- Evaluate switching Rust HTTP TLS from native OpenSSL to Rustls to simplify
  runtime dependencies.
- Keep the current TCP buffer tuning unless profiling shows it is wasteful;
  reducing buffers may hurt throughput on this Corplink TCP path.

## Troubleshooting

If login succeeds but intranet access fails, check:

- `force_protocol` is set to `"tcp"` if UDP does not work in your environment.
- `socks5_listen` is `0.0.0.0:1080` inside the container.
- the host port mapping is correct, for example `-p 1089:1080`.
- clients use `--socks5-hostname` for SOCKS5 so hostname DNS goes through the
  proxy.
- `/data` is writable because config state and cookies are persisted there.

If the container exits with config write errors, you probably mounted a single
read-only config file. Mount a writable directory to `/data` instead.
