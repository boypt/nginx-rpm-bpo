# Nginx RPM Backport (nginx-rpm-bpo)

Builds nginx RPMs backported to EOL CentOS releases (el5 / el6 / el7), with a modern OpenSSL statically bundled into nginx so the resulting RPM has **no runtime `openssl` dependency**.

Each distro builds inside its own Docker image, so you don't need an old CentOS machine — just Docker.

## Current version

| Component | Version |
|---|---|
| NGINX | 1.30.4 |
| Release | b2 |
| OpenSSL (bundled) | openssl-3.5.7 |
| Perl (el5 only, built into image) | perl-5.38.2 |

## How it works

- `version.env` is the single source of truth for versions (`NGINX_VER`, `NGINX_REL`, `OPENSSL_VER`, `PERL_VER`).
- `rpmbuild.sh` patches the spec template from `SOURCE/`, downloads the nginx/openssl tarballs (or reuses pre-downloaded ones from `downloads/`), builds the RPM, and copies it to `output/`.
- The el5 image compiles its own perl 5.38 into `/usr/local/perl` because CentOS 5 ships perl 5.8, which is too old for modern OpenSSL/nginx.
- CI (GitHub Actions) builds and publishes the Docker images to GHCR, and a `v*` tag triggers an RPM build + GitHub Release with the RPM files directly.

## Manual build

### 1. Download sources (optional but recommended)

`rpmbuild.sh` can download nginx/openssl tarballs itself, but the el5 image build needs the perl tarball in the build context, and el5's old `wget` has no HTTPS support. Pre-download everything first:

```sh
./pullsrc.sh
```

This downloads `nginx-*.tar.gz`, `openssl-*.tar.gz`, and `perl-*.tar.gz` into `downloads/`.

### 2. Build the Docker images

```sh
docker build -f Docker/Dockerfile.centos7 -t ngxbuild:el7 .
docker build -f Docker/Dockerfile.centos6 -t ngxbuild:el6 .
docker build -f Docker/Dockerfile.centos5 -t ngxbuild:el5 .
```

> The el5 image requires `./downloads/perl-*.tar.gz` in the build context — run `./pullsrc.sh` first.

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

- el6 / el7 build x86_64 RPMs.
- el5 builds x86_64 by default; pass `M32=1` to build the i686 (32-bit) RPM instead.

Finished RPMs land in `output/`.

## Release process

1. Bump `NGINX_REL` in `version.env` (increment the build counter).
2. Update the `## Current version` section above.
3. Commit, then tag as `v${NGINX_VER}_b${NGINX_REL}` (e.g. `v1.30.4_b2`) and push the tag.
4. CI builds RPMs for el5 (x86_64 + i686)/el6/el7, uploads artifacts, and creates a GitHub Release.

## License

MIT