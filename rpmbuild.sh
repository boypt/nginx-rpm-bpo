#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

source version.env
DIST=$(rpm --eval '%{?dist}')
RPMTOPDIR=$(rpm --eval '%_topdir')
SRC_DIST=$DIST 
SRC_OPTS=()

if [[ $DIST == .el5 ]]; then
  SRC_DIST=.el6
  SRC_OPTS=("--nomd5" "--nosignature")
fi
rpm -ivh /data/SOURCES/nginx*${SRC_DIST}.ngx.src.rpm "${SRC_OPTS[@]+"${SRC_OPTS[@]}"}"
install -v -m 644 /data/SOURCES/${OPENSSL_VER}.tar.gz ${RPMTOPDIR}/SOURCES
install -v -m 644 /data/SOURCES/nginx-${NGINX_VER}.tar.gz ${RPMTOPDIR}/SOURCES


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

mkdir -p /data/NGINX/output && \
find $RPMTOPDIR/RPMS -name '*.rpm' -exec install -v -m644 {} /data/NGINX/output \;
