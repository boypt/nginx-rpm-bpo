# AGENTS.md

Nginx RPM Backport (`nginx-rpm-bpo`): builds nginx RPMs backported to EOL CentOS (el5/el6/el7 x86_64 plus el7 aarch64 via `aarch64_el7`), with a modern OpenSSL statically bundled into nginx so the RPM has no runtime `openssl` dependency. Each distro builds inside its own Docker image.

## Version bump

- `version.env` is the single source of truth: `NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`, `PERL_VER`, `NJS_VER`.
- For local overrides (e.g. custom `PKGREL`), create `version-local.env` (gitignored) — it is sourced after `version.env` and can override any variable.
- The `.src.rpm` files in `SOURCE/` are only spec-file **templates** — `rpmbuild.sh` overwrites their version/release via `sed` from `version.env`, and the real nginx/openssl source comes from auto-downloaded tarballs.

## Release process

When releasing a new nginx version (e.g. `1.30.4`), follow this order:

1. **Bump `NGINX_REL` in `version.env`** — if not already set, set it to `1` (build 1); if already set, increment the number (`1` → `2` → `3` ...). `NGINX_REL` is the build counter per nginx version; the `b` prefix appears only in the tag name (`v1.30.4_b2`), not in `version.env`. Also bump `NJS_VER` if updating njs.
2. **Update `README.md`** — add/refresh the `## Version` section with the current `NGINX_VER`, release build (`bN`), `OPENSSL_VER`, `PERL_VER`, and `NJS_VER` plus dynamic modules list.
3. **Commit** the changes (e.g. `chore: bump NGINX_REL to 2 for v1.30.4 release`).
4. **Tag the commit** as `v${NGINX_VER}_b${NGINX_REL}` (e.g. `v1.30.4_b2`) and push the tag.

Pushing the `v*` tag triggers `.github/workflows/build-rpm.yml`, which builds RPMs for el5 (x86_64 + i686)/el6/el7 plus `aarch64_el7`, packages each distro's RPMs into zips (`rpm-el7-x86_64.zip` etc., including `nginx-module-*` on el6/el7/aarch64), uploads artifacts, and creates a GitHub Release with the zip files. The built RPMs are **not** committed to the repo — only the tag/commit triggers the build.

Deleting a test tag: `git push origin --delete v1.30.4_b2` (also delete the release on GitHub if one was created).

## Downloading tarballs

- Run `./pullsrc.sh` first — it downloads nginx, openssl, perl, and njs tarballs to `downloads/`. `rpmbuild.sh` does **not** download anything; it copies from `/data/downloads/` (the mounted `downloads/` dir) into the rpmbuild SOURCES dir, and exits with a hint if they're missing.
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

Local convention: launch long builds detached (logs under `/tmp/opencode/ngxbpo/*.log`) and display them live in a Herdr side pane (`herdr pane split --current --direction right --no-focus`, then `herdr pane run <pane> tail -F <logs>`), so progress is visible without polling.

Then run:

```sh
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```

The repo root is mounted at `/data` inside the container. All scripts (`rpmbuild.sh`, `pullsrc.sh`) source `version.env` from the repo root.

Building the el5 image requires `./downloads/perl-*.tar.gz` in the build context (referenced by `Dockerfile.centos5`). Run `./pullsrc.sh` first to download it.

`Docker/modify_vault_source.sh` rewrites yum repo baseurls to multiple failover mirrors (there is no `MIRROR` build-arg). Mirror lists live in arrays: `VAULT` (HTTPS, fastest-reliable-first with the canonical vault.centos.org LAST — it persistently 403s repomd.xml from some networks and would waste a retry round per repo; el7/el8 and the altarch tree), `VAULT_HTTP` (plain HTTP for el5/el6 — Python 2.4 / old curl cannot handle HTTPS), and `EPEL` (plain HTTP EPEL archive shared by el5/6/7). For `aarch64` (`uname -m = aarch64`), the el7 vault suffix gets `ALTARCH=/altarch` prepended so it uses the CentOS AltArch tree. The script also handles `.el8` (reserved for future use; not built yet).

### Docker image slimming techniques (applied 2026-08, learned from php-buildscript)

1. **Bind mounts instead of COPY for build-time-only inputs.** A COPY layer stays in the image forever even if a later RUN deletes it. All Dockerfiles consume `modify_vault_source.sh` via `RUN --mount=type=bind`, and the el5 builder extracts the perl tarball from a bind-mounted `downloads/` — neither enters an image layer.
2. **`.dockerignore` keeps the context minimal**: only `Docker/` + `downloads/perl-*.tar.gz` are sent to the builder (~21MB instead of the whole repo incl. `.git`, all tarballs, `output/`). Bind-mount sources must be allowed through `.dockerignore` or the build fails.
3. **Locale pruning** in every image: keep only `en*` message catalogs, truncate/remove `/usr/lib/locale/locale-archive` (glibc regenerates on demand; build tooling runs in the C locale). Measure first: centos:6/7 bases are already lean here (~2MB), but **el5 glibc-common ships ~60MB of compiled locale dirs under `/usr/lib/locale/<name>/`** — prune non-`en*` dirs there too.
4. **Package list trimmed to what the pipeline actually uses** — **no system openssl package is needed at all**: everything compiles against the bundled OpenSSL tarball (`--with-openssl=...`), and `rpmbuild.sh` strips BOTH runtime `Requires:` and `BuildRequires:` openssl lines from the main spec (the `/.*Requires: openssl.*/d` pattern even matches `BuildRequires: openssl-devel` by substring; an explicit `/^BuildRequires:.*openssl/d` was added so this doesn't depend on the substring accident). Dropped from the images: `openssl-devel`, `autoconf`/`automake` (nginx/njs ship pre-generated configure scripts), and `wget` from the explicit list (pullsrc.sh runs host-side; on el5/el6 rpmdevtools pulls wget back in transitively, el7 is truly clean).
   **Gotcha (broke the v1.30.4_b7 release):** the non-njs module specs (geoip/image-filter/xslt/perl) enable SSL modules but carried NO `--with-openssl`, so nginx's configure silently probed SYSTEM OpenSSL — b6 only passed because openssl-devel happened to be installed. Fix: `rpmbuild.sh` now wires those specs to the bundled tarball too (adds `Source101` + %prep extraction + `--with-openssl=... --with-openssl-opt=no-tests`). With `--with-openssl` set, nginx's configure skips the system probe entirely (`auto/lib/openssl/conf`: feature tests only run when `$OPENSSL == NONE`) and `make` builds openssl into `.openssl`.
5. **Layer hygiene**: each image installs packages in a single RUN with `yum clean all` so yum caches never persist across layers (the old centos5 final stage left caches in its first RUN layer).
6. **Never blind-`yum remove` post-install cruft on el5/el6** — removal cascades unpredictably through boot/system chains. Don't install it in the first place instead.
7. **Verify trims with a real build**: package cuts are only proven safe by running `rpmbuild.sh` end-to-end inside the slimmed image (done for el6 2026-08: main nginx + all 5 dynamic modules built successfully).

## rpmbuild.sh quirks

- Determines `DIST` via `rpm --eval '%{?dist}'`. el5 has no matching src.rpm, so it reuses the `.el6` src.rpm and adds `--nomd5 --nosignature`.
- Requires `./pullsrc.sh` to have been run: copies `nginx-${NGINX_VER}.tar.gz`, `${OPENSSL_VER}.tar.gz`, and `njs-${NJS_VER}.tar.gz` (for modules) from `/data/downloads/` into the rpmbuild SOURCES dir (old el5 `wget` has no HTTPS support, so all downloads happen on the host / CI runner).
- Patches `SPECS/nginx.spec` with `sed`: bumps `base_version`/`base_release`, adds `Source100` (openssl tarball), appends `--with-openssl=... --with-openssl-opt=no-tests`, extracts the openssl tarball during `%setup`/`%autosetup` (excluding tests), and deletes `Requires: openssl`. For modules, loops over 5 `nginx-module-*` specs (el6/el7 only), patches `base_version`/`base_release`/`njs_version`, handles `pcre2→pcre` on el6, and builds each with `rpmbuild -bb`.
- `M32=1` switches to a 32-bit build: replaces `no-tests` with `linux-x86 no-tests`, adds `-m32` to `WITH_CC_OPT`/`WITH_LD_OPT`, and passes `--target=i686`.
- Uses `sed -i.bak` for the main spec patch, but the M32 block uses `sed -i` (no backup). `.bak` files may be left beside `nginx.spec`.
- Finished RPMs are copied to `/data/output/`.

## CI

Two GitHub Actions workflows:

- **`.github/workflows/build-images.yml`** — manual trigger (`workflow_dispatch`). Builds and pushes images to `ghcr.io` as `ghcr.io/${{ github.repository }}:elX` (not `ngxbuild:elX` — that local tag is only for manual builds). Matrix: `build-amd64` (el5/el6/el7 on `ubuntu-latest`) + `build-arm64` (`aarch64_el7` on `ubuntu-latest` with `setup-qemu-action` + `platforms: linux/arm64`). Cache: `type=gha`. Tags are per-arch (e.g. `ghcr.io/boypt/nginx-rpm-bpo:aarch64_el7`), not multi-arch manifests. Runs `./pullsrc.sh` first for the el5 build (needs the perl tarball in the build context).
- **`.github/workflows/build-rpm.yml`** — triggers on `v*` tags. Pulls pre-built images from GHCR and builds RPMs. Matrix: `build-amd64` (el6/el7/el5 on `ubuntu-latest`) + `build-arm64` (`aarch64_el7` on `ubuntu-24.04-arm`, native ARM — no QEMU). After each build, packages RPMs into a per-distro zip (`rpm-el7-x86_64.zip`, etc.). The final `release` job needs both `build-amd64` and `build-arm64` to complete, then uploads artifacts and creates a GitHub Release with the zip files. **Manifest mismatch fix:** the `aarch64_el7` image is `linux/arm64` only (not a multi-arch manifest), so it must run on an ARM runner (`ubuntu-24.04-arm`), not `ubuntu-latest` — running it on `ubuntu-latest` would fail because that runner is x86_64 and cannot execute a single-arch ARM64 image.

**Gotchas:**

- `/data/output` is the host's `output/` dir mounted via `-v $(pwd):/data`; the container's `builder` user (UID 1000) cannot write to a host dir owned by the runner user. The workflow runs `mkdir -p output && chmod 777 output` before `docker run`, so this must stay in sync with the Dockerfiles' `mkdir -p /data/output && chown builder:builder /data/output` (which only applies to non-mounted local builds).

## Repo hygiene

- All project files (`Docker/`, `SOURCE/`, `rpmbuild.sh`, `pullsrc.sh`, `version.env`, `.github/`, `.gitignore`, `README.md`, `AGENTS.md`) **are** committed.
- **Never commit build artifacts**: `.gitignore` excludes `output/` (RPMs), `downloads/` (tarballs), `rpm-*/` dirs, `version-local.env`, and `*.bak`. If RPMs were accidentally committed, `git rm -r --cached` them.
- History hygiene: when fixing a failed release attempt, prefer squashing fix commits into one clean commit (e.g. `git rebase -i` with `fixup`) instead of preserving fix history.