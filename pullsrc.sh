#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

source version.env
[[ -f version-local.env ]] && source version-local.env

NGINX_URL="https://nginx.org/download/nginx-${NGINX_VER}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/${OPENSSL_VER}/${OPENSSL_VER}.tar.gz"
PERL_URL="https://www.cpan.org/src/5.0/${PERL_VER}.tar.gz"

mkdir -p downloads

pushd downloads

if [[ ! -f nginx-${NGINX_VER}.tar.gz ]]; then
    echo "Downloading nginx-${NGINX_VER}.tar.gz..."
    wget --no-check-certificate -q \
        -O nginx-${NGINX_VER}.tar.gz "$NGINX_URL" || \
        echo "!!! Please download nginx-${NGINX_VER}.tar.gz in $PWD by yourself."
else
    echo "nginx-${NGINX_VER}.tar.gz already exists, skipping."
fi

if [[ ! -f ${OPENSSL_VER}.tar.gz ]]; then
    echo "Downloading ${OPENSSL_VER}.tar.gz..."
    wget --no-check-certificate -q \
        -O ${OPENSSL_VER}.tar.gz "$OPENSSL_URL" || \
        echo "!!! Please download ${OPENSSL_VER}.tar.gz in $PWD by yourself."
else
    echo "${OPENSSL_VER}.tar.gz already exists, skipping."
fi

if [[ ! -f ${PERL_VER}.tar.gz ]]; then
    echo "Downloading ${PERL_VER}.tar.gz..."
    wget --no-check-certificate -q \
        -O ${PERL_VER}.tar.gz "$PERL_URL" || \
        echo "!!! Please download ${PERL_VER}.tar.gz in $PWD by yourself."
else
    echo "${PERL_VER}.tar.gz already exists, skipping."
fi

NJS_URL="https://github.com/nginx/njs/archive/refs/tags/${NJS_VER}.tar.gz"
if [[ ! -f njs-${NJS_VER}.tar.gz ]]; then
    echo "Downloading njs-${NJS_VER}.tar.gz..."
    wget --no-check-certificate -q \
        -O njs-${NJS_VER}.tar.gz "$NJS_URL" || \
        echo "!!! Please download njs-${NJS_VER}.tar.gz in $PWD by yourself."
else
    echo "njs-${NJS_VER}.tar.gz already exists, skipping."
fi

popd
echo "Done."