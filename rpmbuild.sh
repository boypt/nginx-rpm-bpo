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

# Copy pre-downloaded tarballs (from ./pullsrc.sh) into the rpmbuild SOURCES dir.
# Run ./pullsrc.sh first to populate downloads/.
mkdir -p ${RPMTOPDIR}/SOURCES

copy_sources() {
    local name=$1
    if [[ ! -f ${RPMTOPDIR}/SOURCES/${name}.tar.gz ]]; then
        if [[ -f /data/downloads/${name}.tar.gz ]]; then
            echo "Using pre-downloaded ${name}.tar.gz..."
            install -v -m 644 /data/downloads/${name}.tar.gz ${RPMTOPDIR}/SOURCES/
        else
            echo "!!! ${name}.tar.gz not found in /data/downloads/"
            echo "!!! Run ./pullsrc.sh first to download the sources."
            exit 1
        fi
    fi
}

copy_sources nginx-${NGINX_VER}
copy_sources ${OPENSSL_VER}

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
		-e '/^BuildRequires:.*openssl/d' \
		${RPMTOPDIR}/SPECS/nginx.spec
elif [[ $SRC_DIST == .el7 ]]; then
	sed -i.bak \
		-e "/^%define base_version/s|[0-9.]\+|${NGINX_VER}|" \
		-e "/^%define base_release/s|[0-9]?*|${NGINX_REL}|" \
		-e "/Source9: .*/a Source100: $OPENSSL_VER.tar.gz" \
		-e "s|--with-http_ssl_module|--with-http_ssl_module --with-openssl=$OPENSSL_VER --with-openssl-opt=no-tests|g" \
		-e '/^%autosetup/a tar zxf %{SOURCE100} --exclude=openssl*/tests' \
		-e '/.*Requires: openssl.*/d' \
		-e '/^BuildRequires:.*openssl/d' \
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

# Build dynamic modules (el6/el7 only, no el5)
if [[ $DIST != .el5 ]]; then
    MODULES="nginx-module-njs nginx-module-geoip nginx-module-image-filter nginx-module-xslt nginx-module-perl"
    for module in $MODULES; do
        echo "=== Building $module ==="
        cp /data/SOURCE/${module}.copyright ${RPMTOPDIR}/SOURCES/
        if [[ $module == nginx-module-njs ]]; then
            copy_sources njs-${NJS_VER}
        fi
        cp /data/SOURCE/${module}.spec ${RPMTOPDIR}/SPECS/
        sed -i \
            -e "/^%define base_version/s|[0-9.]\+|${NGINX_VER}|" \
            -e "/^%define base_release/s|[0-9]?*|${NGINX_REL}|" \
            ${RPMTOPDIR}/SPECS/${module}.spec
        if [[ $module == nginx-module-njs ]]; then
            sed -i -e "/^%define njs_version/s|[0-9.]\+|${NJS_VER}|" \
                   -e "/^%define openssl_version/s|openssl-.*|${OPENSSL_VER}|" ${RPMTOPDIR}/SPECS/${module}.spec
        fi
        if [[ $DIST == .el6 ]]; then
            sed -i -e 's|pcre2-config|pcre-config|g' -e 's|pcre2-devel|pcre-devel|g' ${RPMTOPDIR}/SPECS/${module}.spec
            # njs on el6: libedit too old (rl_on_new_line missing), build CLI without readline
            if [[ $module == nginx-module-njs ]]; then
                sed -i -e '/BuildRequires: libedit-devel/d' ${RPMTOPDIR}/SPECS/${module}.spec
            fi
        fi
        rpmbuild -bb ${RPMTOPDIR}/SPECS/${module}.spec "${TARGET_OPT[@]+"${TARGET_OPT[@]}"}"
    done
fi

mkdir -p /data/output && \
find $RPMTOPDIR/RPMS -name '*.rpm' -exec install -v -m644 {} /data/output \;