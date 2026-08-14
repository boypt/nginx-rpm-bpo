# AGENTS.md

Builds nginx RPMs backported to EOL CentOS (el5/el6/el7), with a modern OpenSSL statically bundled into nginx so the RPM has no runtime `openssl` dependency. Each distro builds inside its own Docker image.

## Version bump

- `version.env` is the single source of truth: `NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`, `PERL_VER`.
- For local overrides (e.g. custom `PKGREL`), create `version-local.env` (gitignored) — it is sourced after `version.env` and can override any variable.
- The `.src.rpm` files in `SOURCE/` are only spec-file **templates** — `rpmbuild.sh` overwrites their version/release via `sed` from `version.env`, and the real nginx/openssl source comes from auto-downloaded tarballs.

## Downloading tarballs

- `rpmbuild.sh` auto-downloads `nginx-${NGINX_VER}.tar.gz` from `nginx.org` and `${OPENSSL_VER}.tar.gz` from GitHub Releases into the rpmbuild SOURCES dir before building. No manual tarball placement needed.
- For pre-downloading outside Docker (e.g. CI caching), run `./pullsrc.sh` — it downloads nginx, openssl, and perl tarballs to `downloads/`.

## Build commands

Build images manually first, tagged to match the run script (note the `centosX` file name → `elX` tag):

```sh
docker build -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
docker build -f Docker/Dockerfile.centos6 -t ngxbuild:el6 .
docker build -f Docker/Dockerfile.centos5 -t ngxbuild:el5 .
```

Then run:

```sh
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```

The repo root is mounted at `/data` inside the container. All scripts (`rpmbuild.sh`, `pullsrc.sh`) source `version.env` from the repo root.

Building the el5 image requires `./downloads/perl-*.tar.gz` in the build context (referenced by `Dockerfile.centos5`). Run `./pullsrc.sh` first to download it.

All Dockerfiles accept `--build-arg MIRROR=0` to use official CentOS vault mirrors instead of Chinese mirrors. `Docker/modify_yum_source.sh` handles the mirror switching.

## rpmbuild.sh quirks

- Determines `DIST` via `rpm --eval '%{?dist}'`. el5 has no matching src.rpm, so it reuses the `.el6` src.rpm and adds `--nomd5 --nosignature`.
- Patches `SPECS/nginx.spec` with `sed`: bumps `base_version`/`base_release`, adds `Source100` (openssl tarball), appends `--with-openssl=... --with-openssl-opt=no-tests`, extracts the openssl tarball during `%setup`/`%autosetup` (excluding tests), and deletes `Requires: openssl`.
- `M32=1` switches to a 32-bit build: replaces `no-tests` with `linux-x86 no-tests`, adds `-m32` to `WITH_CC_OPT`/`WITH_LD_OPT`, and passes `--target=i686`.
- Uses `sed -i.bak`, so `.bak` backup files are left beside `nginx.spec`.
- Finished RPMs are copied to `/data/output/`.

## CI

Two GitHub Actions workflows:

- **`.github/workflows/build-images.yml`** — manual trigger (`workflow_dispatch`). Builds and pushes `ngxbuild:el5/el6/el7` images to `ghcr.io`. Passes `MIRROR=0` to use official CentOS vault mirrors.
- **`.github/workflows/build-rpm.yml`** — triggers on `v*` tags. Pulls pre-built images from GHCR, runs builds for el5 (x86_64 + i686)/el6/el7, uploads artifacts, and creates a GitHub Release with zipped RPMs.

## Repo hygiene

- Only `LICENSE` is committed; `Docker/`, `SOURCE/`, `rpmbuild.sh`, `pullsrc.sh`, `version.env`, and `.github/` are all untracked.