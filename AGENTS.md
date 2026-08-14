# AGENTS.md

Builds nginx RPMs backported to EOL CentOS (el5/el6/el7), with a modern OpenSSL statically bundled into nginx so the RPM has no runtime `openssl` dependency. Each distro builds inside its own Docker image.

## Layout vs. scripts mismatch (read this first)

The scripts were written for an older repo layout and no longer match this tree. Do not trust paths blindly:

- `docker_build.sh` mounts `$__dir/..` (the repo's **parent** directory) at `/data`, not the repo root.
- Dockerfile `CMD` runs `/data/NGINX/rpmbuild.sh`; `rpmbuild.sh` reads `/data/SOURCES/...` and writes `/data/NGINX/output/`.
- This repo is `nginx-rpm-bpo` and has `SOURCE/` (singular). There is no `NGINX/` or `SOURCES/` directory.

The scripts assume an original layout (`NGINX/` dir with `SOURCES/`). Running them as-is will operate on the wrong directory or fail. Verify and fix the mount/paths before running.

## Version bump

- `version.env` is the single source of truth: `NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`.
- Bumping also requires manually obtaining the upstream tarballs `nginx-${NGINX_VER}.tar.gz` and `${OPENSSL_VER}.tar.gz` and placing them in the source dir. Nothing downloads them automatically; they are not in the repo.
- The `.src.rpm` files in `SOURCE/` are only spec-file **templates** — `rpmbuild.sh` overwrites their version/release via `sed` from `version.env`, and the real nginx/openssl source comes from the injected tarballs.

## Build commands

Images are **not** built by `docker_build.sh` — it only lists and runs them. Build them manually first, tagged to match the run script (note the `centosX` file name → `elX` tag):

```sh
docker build -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
docker build -f Docker/Dockerfile.centos6 -t ngxbuild:el6 .
docker build -f Docker/Dockerfile.centos5 -t ngxbuild:el5 .
```

Then `./docker_build.sh` runs `ngxbuild:el6`, `ngxbuild:el7`, and `ngxbuild:el5` (el5 with `M32=1` → 32-bit i686 build).

Building the el5 image also requires `./SOURCES/perl-*.tar.gz` in the build context (referenced by `Dockerfile.centos5`); it is not present in the repo.

## rpmbuild.sh quirks

- Determines `DIST` via `rpm --eval '%{?dist}'`. el5 has no matching src.rpm, so it reuses the `.el6` src.rpm and adds `--nomd5 --nosignature`.
- Patches `SPECS/nginx.spec` with `sed`: bumps `base_version`/`base_release`, adds `Source100` (openssl tarball), appends `--with-openssl=... --with-openssl-opt=no-tests`, extracts the openssl tarball during `%setup`/`%autosetup` (excluding tests), and deletes `Requires: openssl`.
- `M32=1` switches to a 32-bit build: drops `no-tests` for `linux-x86 no-tests`, adds `-m32` to `WITH_CC_OPT`/`WITH_LD_OPT`, and passes `--target=i686`.
- Uses `sed -i.bak`, so `.bak` backup files are left beside `nginx.spec`.
- Finished RPMs are copied to `/data/NGINX/output/`.

## Repo hygiene

- Only `LICENSE` is committed; `Docker/`, `SOURCE/`, `rpmbuild.sh`, `docker_build.sh`, and `version.env` are all untracked.
- `.README.md.swp` is a stale Vim swap file, not content; there is no `README.md`.
