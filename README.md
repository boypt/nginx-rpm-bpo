# Nginx RPM Backport (nginx-rpm-bpo)

Builds nginx RPMs backported to EOL CentOS releases (el5 / el6 / el7 x86_64 plus el7 aarch64 (`aarch64_el7`)), with a modern OpenSSL statically bundled into nginx so the resulting RPM has **no runtime `openssl` dependency**.

Each distro builds inside its own Docker image, so you don't need an old CentOS machine — just Docker.

## Current version

| Component | Version |
|---|---|
| NGINX | 1.30.4 |
| Release | b6 |
| OpenSSL (bundled) | openssl-3.5.7 |
| Perl (el5 only, built into image) | perl-5.38.2 |
| njs | 1.0.0 |
| Dynamic modules (el6/el7 only) | nginx-module-njs, nginx-module-geoip, nginx-module-image-filter, nginx-module-xslt, nginx-module-perl |

## How it works

- `version.env` is the single source of truth for versions (`NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`, `PERL_VER`, `NJS_VER`).
- `./pullsrc.sh` downloads the nginx/openssl/perl/njs tarballs into `downloads/`. `rpmbuild.sh` copies them from there, patches the spec template from `SOURCE/`, builds the RPM, and copies it to `output/`.
- The el5 image compiles its own perl 5.38 into `/usr/local/perl` because CentOS 5 ships perl 5.8, which is too old for modern OpenSSL/nginx.
- **aarch64 (ARM64) support**: the `aarch64_el7` target reuses the same el7 spec but is built and published under its own per-arch Docker tag `ghcr.io/boypt/nginx-rpm-bpo:aarch64_el7`. The image is QEMU-built (emulated), not a multi-arch manifest, so it is `linux/arm64` only. The CentOS AltArch vault is used for aarch64 packages, which means the vault base URL gets an `/altarch` suffix (e.g. `.../centos-vault/altarch/7.9.2009/`).
- CI (GitHub Actions) runs `pullsrc.sh` automatically, builds and publishes the Docker images to GHCR, and a `v*` tag triggers an RPM build + GitHub Release with **per-distro zip archives** (each zip contains all RPMs for that distro, including dynamic modules on el6/el7).

## Manual build

### 1. Download sources (required)

`rpmbuild.sh` does not download anything — run `./pullsrc.sh` first:

```sh
./pullsrc.sh
```

This downloads `nginx-*.tar.gz`, `openssl-*.tar.gz`, `perl-*.tar.gz`, and `njs-*.tar.gz` into `downloads/`. The el5 image build needs the perl tarball in the build context, and el5's old `wget` has no HTTPS support, so all downloads happen on the host.

### 2. Build the Docker images

```sh
docker build -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
docker build -f Docker/Dockerfile.centos6 -t ngxbuild:el6 .
docker build -f Docker/Dockerfile.centos5 -t ngxbuild:el5 .
```

> The el5 image requires `./downloads/perl-*.tar.gz` in the build context — run `./pullsrc.sh` first.

`Docker/Dockerfile.centos7` serves both the `el7` (x86_64) and `aarch64_el7` (ARM64) targets. For aarch64, build/run with `--platform linux/arm64` so QEMU emulates the ARM64 container locally:

```sh
docker build --platform linux/arm64 -f Docker/Dockerfile.centos7 -t ngxbuild:aarch64_el7 .
```

In CI the `aarch64_el7` image is built with QEMU (`setup-qemu-action` + `platforms: linux/arm64`) on `ubuntu-latest`, so you normally don't build it by hand.

By default the images use Chinese yum mirrors. To use official CentOS vault mirrors instead:

```sh
docker build --build-arg MIRROR=0 -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
```

### 3. Build the RPMs

The repo root is mounted at `/data` inside the container:

```sh
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```

For aarch64, run the per-arch image. Locally you can emulate it with QEMU via `--platform linux/arm64`:

```sh
docker run --platform linux/arm64 --rm -v .:/data ngxbuild:aarch64_el7
```

Or pull the published image directly:

```sh
docker run --rm -v .:/data ghcr.io/boypt/nginx-rpm-bpo:aarch64_el7
```

In CI the `aarch64_el7` RPM is built natively on an ARM runner (`ubuntu-24.04-arm`), so no QEMU emulation is needed there.

- el6 / el7 build x86_64 RPMs.
- `aarch64_el7` builds an `aarch64` (ARM64) RPM using the same el7 spec.
- el5 builds x86_64 by default; pass `M32=1` to build the i686 (32-bit) RPM instead.

Finished RPMs land in `output/`. On el6/el7 the output also contains dynamic module RPMs (`nginx-module-*`), each built as a separate `make modules` build with `--with-compat` for ABI compatibility.

Dynamic modules are installed separately and require the main `nginx` package:

```sh
yum install nginx-1.30.4-6.el7.ngx.x86_64.rpm
yum install nginx-module-njs-1.30.4+1.0.0-6.el7.ngx.x86_64.rpm
# then enable in nginx.conf: load_module modules/ngx_http_js_module.so;
```

## Release process

1. Bump `NGINX_REL` in `version.env` (increment the build counter).
2. Update the `## Current version` section above.
3. Commit, then tag as `v${NGINX_VER}_b${NGINX_REL}` (e.g. `v1.30.4_b2`) and push the tag.
4. CI builds RPMs for el5 (x86_64 + i686)/el6/el7 plus `aarch64_el7` (now 5 artifacts total: el5 x86_64, el5 i686, el6, el7, aarch64_el7), packages each distro's RPMs into a **zip** (`rpm-el7-x86_64.zip`, `rpm-el6-x86_64.zip`, etc.), uploads artifacts, and creates a GitHub Release with the zip files. The `build-arm64` job runs `aarch64_el7` natively on `ubuntu-24.04-arm`. Module RPMs (`nginx-module-*`) are included in the el6/el7/aarch64 zips (el5 zips contain only nginx + nginx-debug).

## License

MIT