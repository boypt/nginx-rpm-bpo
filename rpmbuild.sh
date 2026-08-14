#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

source version.env
[[ -f version-local.env ]] && source version-local.env

DIST=$(rpm --eval '%{?dist}')
RPMTOPDIR=$(rpm --eval '%_topdir')
SRC_DIST=$DIST 
SRC_OPTS=()

# Download URLs
NGINX_URL="https://nginx.org/download/nginx-${NGINX_VER}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/${OPENSSL_VER}/${OPENSSL_VER}.tar.gz"

# Download tarballs if not already in SOURCES
# First check downloads/ dir (pre-downloaded by CI via pullsrc.sh)
# Then try direct download from upstream
mkdir -p /tmp/nginx-downloads

if [[ ! -f ${RPMTOPDIR}/SOURCES/nginx-${NGINX_VER}.tar.gz ]]; then
    if [[ -f /data/downloads/nginx-${NGINX_VER}.tar.gz ]]; then
        echo "Using pre-downloaded nginx-${NGINX_VER}.tar.gz..."
        install -v -m 644 /data/downloads/nginx-${NGINX_VER}.tar.gz ${RPMTOPDIR}/SOURCES/
    else
        echo "Downloading nginx-${NGINX_VER}.tar.gz..."
        wget --no-check-certificate -q \
            -O /tmp/nginx-downloads/nginx-${NGINX_VER}.tar.gz "$NGINX_URL" || {
            echo "!!! Failed to download nginx-${NGINX_VER}.tar.gz"
            echo "!!! Please download it manually and place in the SOURCES dir."
            exit 1
        }
        install -v -m 644 /tmp/nginx-downloads/nginx-${NGINX_VER}.tar.gz ${RPMTOPDIR}/SOURCES/
    fi
fi

if [[ ! -f ${RPMTOPDIR}/SOURCES/${OPENSSL_VER}.tar.gz ]]; then
    if [[ -f /data/downloads/${OPENSSL_VER}.tar.gz ]]; then
        echo "Using pre-downloaded ${OPENSSL_VER}.tar.gz..."
        install -v -m 644 /data/downloads/${OPENSSL_VER}.tar.gz ${RPMTOPDIR}/SOURCES/
    else
        echo "Downloading ${OPENSSL_VER}.tar.gz..."
        wget --no-check-certificate -q \
            -O /tmp/nginx-downloads/${OPENSSL_VER}.tar.gz "$OPENSSL_URL" || {
            echo "!!! Failed to download ${OPENSSL_VER}.tar.gz"
            echo "!!! Please download it manually and place in the SOURCES dir."
            exit 1
        }
        install -v -m 644 /tmp/nginx-downloads/${OPENSSL_VER}.tar.gz ${RPMTOPDIR}/SOURCES/
    fi
fi

if [[ $DIST == .el5 ]]; then
  SRC_DIST=.el6
  SRC_OPTS=("--nomd5" "--nosignature")
fi
rpm -ivh /data/SOURCE/nginx*${SRC_DIST}.ngx.src.rpm "${SRC_OPTS[@]+"${SRC_OPTS[@]}"}"


if [[ $SRC_DIST == .el6 ]]; then
	sed -i.bak \
		-e "/^%define base_version/s|[0-9.]\+|${NGINX_VER}|" \
		-e "/^%define base_release/s|[0-9]?*|${NGINX_REL}|" \
		-e "/Source12: .*/a Source100: $OPENSSL_VER.tar.gz" \
		-e "s|--with-http_ssl_module|--with-http_ssl_module --with-openssl=$OPENSSL_VER --with-openssl-opt=no-tests|g" \
		-e '/%setup -q/a tar zxf %{SOURCE100} --exclude=openssl*/tests' \
		-e '/.*Requires: openssl.*/d' \
		${RPMTOPDIR}/SPECS/nginx.spec
elif [[ $SRC_DIST == .el7 ]]; then
	sed -i.bak \
		-e "/^%define base_version/s|[0-9.]\+|${NGINX_VER}|" \
		-e "/^%define base_release/s|[0-9]?*|${NGINX_REL}|" \
		-e "/Source9: .*/a Source100: $OPENSSL_VER.tar.gz" \
		-e "s|--with-http_ssl_module|--with-http_ssl_module --with-openssl=$OPENSSL_VER --with-openssl-opt=no-tests|g" \
		-e '/^%autosetup/a tar zxf %{SOURCE100} --exclude=openssl*/tests' \
		-e '/.*Requires: openssl.*/d' \
		${RPMTOPDIR}/SPECS/nginx.spec
fi


TARGET_OPT=( --define 'debug_package %{nil}' )
if [[ ${M32:-0} -eq 1 ]]; then
	sed -i \
		-e 's| --with-openssl-opt=no-tests||' \
		-e '/--with-cc-opt/i\    --with-openssl-opt="linux-x86 no-tests" \\' \
		-e '/^%define WITH_CC_OPT/s|WITH_CC_OPT |WITH_CC_OPT -m32 |' \
		-e '/^%define WITH_LD_OPT/s|WITH_LD_OPT |WITH_LD_OPT -m32 |' \
		${RPMTOPDIR}/SPECS/nginx.spec 
	TARGET_OPT+=( --target=i686 )
fi
rpmbuild -bb ${RPMTOPDIR}/SPECS/nginx.spec "${TARGET_OPT[@]+"${TARGET_OPT[@]}"}"

mkdir -p /data/output && \
find $RPMTOPDIR/RPMS -name '*.rpm' -exec install -v -m644 {} /data/output \;