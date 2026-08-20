# AGENTS.md

Nginx RPM Backport (`nginx-rpm-bpo`): builds nginx RPMs backported to EOL CentOS (el5/el6/el7 x86_64 plus el7 aarch64 via `aarch64_el7`), with a modern OpenSSL statically bundled into nginx so the RPM has no runtime `openssl` dependency. Each distro builds inside its own Docker image.

## Version bump

- `version.env` is the single source of truth: `NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`, `PERL_VER`.
- For local overrides (e.g. custom `PKGREL`), create `version-local.env` (gitignored) — it is sourced after `version.env` and can override any variable.
- The `.src.rpm` files in `SOURCE/` are only spec-file **templates** — `rpmbuild.sh` overwrites their version/release via `sed` from `version.env`, and the real nginx/openssl source comes from auto-downloaded tarballs.

## Release process

When releasing a new nginx version (e.g. `1.30.4`), follow this order:

1. **Bump `NGINX_REL` in `version.env`** — if not already set, set it to `1` (build 1); if already set, increment the number (`1` → `2` → `3` ...). `NGINX_REL` is the build counter per nginx version; the `b` prefix appears only in the tag name (`v1.30.4_b2`), not in `version.env`.
2. **Update `README.md`** — add/refresh the `## Version` section with the current `NGINX_VER`, release build (`bN`), `OPENSSL_VER`, and `PERL_VER`.
3. **Commit** the changes (e.g. `chore: bump NGINX_REL to 2 for v1.30.4 release`).
4. **Tag the commit** as `v${NGINX_VER}_b${NGINX_REL}` (e.g. `v1.30.4_b2`) and push the tag.

Pushing the `v*` tag triggers `.github/workflows/build-rpm.yml`, which builds RPMs for el5 (x86_64 + i686)/el6/el7 plus `aarch64_el7`, uploads artifacts, and creates a GitHub Release. The built RPMs are **not** committed to the repo — only the tag/commit triggers the build.

Deleting a test tag: `git push origin --delete v1.30.4_b2` (also delete the release on GitHub if one was created).

## Downloading tarballs

- Run `./pullsrc.sh` first — it downloads nginx, openssl, and perl tarballs to `downloads/`. `rpmbuild.sh` does **not** download anything; it copies from `/data/downloads/` (the mounted `downloads/` dir) into the rpmbuild SOURCES dir, and exits with a hint if they're missing.
- CI runs `./pullsrc.sh` automatically (both workflows) before building images or RPMs.
- The perl tarball is only needed to build the el5 image: CentOS 5 ships perl 5.8 (too old for modern OpenSSL/nginx), so `Dockerfile.centos5` compiles perl 5.38 into `/usr/local/perl` from `./downloads/perl-*.tar.gz`.

## Build commands

Build images manually first, tagged to match the run script (note the `centosX` file name → `elX` tag):

```sh
docker build -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
docker build -f Docker/Dockerfile.centos6 -t ngxbuild:el6 .
docker build -f Docker/Dockerfile.centos5 -t ngxbuild:el5 .
```

`Docker/Dockerfile.centos7` serves both the `el7` (x86_64) and `aarch64_el7` (ARM64) targets. For aarch64, build/run with `--platform linux/arm64` locally so QEMU emulates the ARM64 container, or rely on the CI ARM runner (`ubuntu-24.04-arm`) which builds/runs it natively:

```sh
docker build --platform linux/arm64 -f Docker/Dockerfile.centos7 -t ngxbuild:aarch64_el7 .
```

Then run:

```sh
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```

The repo root is mounted at `/data` inside the container. All scripts (`rpmbuild.sh`, `pullsrc.sh`) source `version.env` from the repo root.

Building the el5 image requires `./downloads/perl-*.tar.gz` in the build context (referenced by `Dockerfile.centos5`). Run `./pullsrc.sh` first to download it.

All Dockerfiles accept `--build-arg MIRROR=0` to use official CentOS vault mirrors instead of Chinese mirrors. `Docker/modify_yum_source.sh` handles the mirror switching. Note: el5 always uses `archive.kernel.org` over plain HTTP (its wget has no HTTPS support), regardless of the `MIRROR` arg; `MIRROR` only matters for el6/el7. For `aarch64` (`uname -m = aarch64`), `modify_yum_source.sh` switches to the CentOS AltArch vault by appending `ALTARCH=/altarch` to the vault base URL (e.g. `.../centos-vault/altarch/7.9.2009/`). EL5 EPEL is also handled specially (uses `http://mirrors.aliyun.com/epel-archive` to avoid the old Python 2.4 TLS 1.0 → 302 → https failure on `archives.fedoraproject.org`).

## rpmbuild.sh quirks

- Determines `DIST` via `rpm --eval '%{?dist}'`. el5 has no matching src.rpm, so it reuses the `.el6` src.rpm and adds `--nomd5 --nosignature`.
- Requires `./pullsrc.sh` to have been run: copies `nginx-${NGINX_VER}.tar.gz` and `${OPENSSL_VER}.tar.gz` from `/data/downloads/` into the rpmbuild SOURCES dir (old el5 `wget` has no HTTPS support, so all downloads happen on the host / CI runner).
- Patches `SPECS/nginx.spec` with `sed`: bumps `base_version`/`base_release`, adds `Source100` (openssl tarball), appends `--with-openssl=... --with-openssl-opt=no-tests`, extracts the openssl tarball during `%setup`/`%autosetup` (excluding tests), and deletes `Requires: openssl`.
- `M32=1` switches to a 32-bit build: replaces `no-tests` with `linux-x86 no-tests`, adds `-m32` to `WITH_CC_OPT`/`WITH_LD_OPT`, and passes `--target=i686`.
- Uses `sed -i.bak` for the main spec patch, but the M32 block uses `sed -i` (no backup). `.bak` files may be left beside `nginx.spec`.
- Finished RPMs are copied to `/data/output/`.

## CI

Two GitHub Actions workflows:

- **`.github/workflows/build-images.yml`** — manual trigger (`workflow_dispatch`). Builds and pushes images to `ghcr.io` as `ghcr.io/${{ github.repository }}:elX` (not `ngxbuild:elX` — that local tag is only for manual builds). Matrix: `build-amd64` (el5/el6/el7 on `ubuntu-latest`) + `build-arm64` (`aarch64_el7` on `ubuntu-latest` with `setup-qemu-action` + `platforms: linux/arm64`). Cache: `type=gha`. Tags are per-arch (e.g. `ghcr.io/boypt/nginx-rpm-bpo:aarch64_el7`), not multi-arch manifests. Passes `MIRROR=0` to use official CentOS vault mirrors. Runs `./pullsrc.sh` first for the el5 build (needs the perl tarball in the build context).
- **`.github/workflows/build-rpm.yml`** — triggers on `v*` tags. Pulls pre-built images from GHCR and builds RPMs. Matrix: `build-amd64` (el6/el7/el5 on `ubuntu-latest`) + `build-arm64` (`aarch64_el7` on `ubuntu-24.04-arm`, native ARM — no QEMU). The final `release` job needs both `build-amd64` and `build-arm64` to complete, then uploads artifacts and creates a GitHub Release with the RPM files directly (no zip). **Manifest mismatch fix:** the `aarch64_el7` image is `linux/arm64` only (not a multi-arch manifest), so it must run on an ARM runner (`ubuntu-24.04-arm`), not `ubuntu-latest` — running it on `ubuntu-latest` would fail because that runner is x86_64 and cannot execute a single-arch ARM64 image.

**Gotchas:**

- `/data/output` is the host's `output/` dir mounted via `-v $(pwd):/data`; the container's `builder` user (UID 1000) cannot write to a host dir owned by the runner user. The workflow runs `mkdir -p output && chmod 777 output` before `docker run`, so this must stay in sync with the Dockerfiles' `mkdir -p /data/output && chown builder:builder /data/output` (which only applies to non-mounted local builds).

## Repo hygiene

- All project files (`Docker/`, `SOURCE/`, `rpmbuild.sh`, `pullsrc.sh`, `version.env`, `.github/`, `.gitignore`, `README.md`, `AGENTS.md`) **are** committed.
- **Never commit build artifacts**: `.gitignore` excludes `output/` (RPMs), `downloads/` (tarballs), `rpm-*/` dirs, `version-local.env`, and `*.bak`. If RPMs were accidentally committed, `git rm -r --cached` them.
- History hygiene: when fixing a failed release attempt, prefer squashing fix commits into one clean commit (e.g. `git rebase -i` with `fixup`) instead of preserving fix history.