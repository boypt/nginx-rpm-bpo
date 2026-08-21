%define nginx_user nginx
%define nginx_group nginx
%define _group System Environment/Daemons

%if (0%{?rhel} == 7)
%define epoch 1
Epoch: %{epoch}
%define dist .el7
%endif

BuildRequires: gd-devel

%define base_version 1.30.4
%define base_release 1%{?dist}.ngx
%define bdir %{_builddir}/%{name}-%{base_version}

Summary: nginx image filter dynamic module
Name: nginx-module-image-filter
Version: %{base_version}
Release: %{base_release}
Vendor: NGINX Packaging <nginx-packaging@f5.com>
URL: https://nginx.org/
Group: %{_group}

Source0: nginx-%{base_version}.tar.gz
Source1: nginx-module-image-filter.copyright

License: 2-clause BSD-like license

BuildRoot: %{_tmppath}/%{name}-%{base_version}-%{base_release}-root
BuildRequires: zlib-devel
BuildRequires: pcre2-devel
Requires: nginx-r%{base_version}
Provides: %{name}-r%{base_version}

%description
nginx image filter dynamic module.

%define WITH_CC_OPT $(echo %{optflags} $(pcre2-config --cflags))
%define WITH_LD_OPT -Wl,-z,relro -Wl,-z,now -Wl,-as-needed

%define BASE_CONFIGURE_ARGS $(echo "--prefix=%{_sysconfdir}/nginx --sbin-path=%{_sbindir}/nginx --modules-path=%{_libdir}/nginx/modules --conf-path=%{_sysconfdir}/nginx/nginx.conf --error-log-path=%{_localstatedir}/log/nginx/error.log --http-log-path=%{_localstatedir}/log/nginx/access.log --pid-path=%{_localstatedir}/run/nginx.pid --lock-path=%{_localstatedir}/run/nginx.lock --http-client-body-temp-path=%{_localstatedir}/cache/nginx/client_temp --http-proxy-temp-path=%{_localstatedir}/cache/nginx/proxy_temp --http-fastcgi-temp-path=%{_localstatedir}/cache/nginx/fastcgi_temp --http-uwsgi-temp-path=%{_localstatedir}/cache/nginx/uwsgi_temp --http-scgi-temp-path=%{_localstatedir}/cache/nginx/scgi_temp --user=%{nginx_user} --group=%{nginx_group} --with-compat --with-file-aio --with-threads --with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module")
%define MODULE_CONFIGURE_ARGS $(echo "--with-http_image_filter_module=dynamic")

%prep
%setup -qcTn %{name}-%{base_version}
tar --strip-components=1 -zxf %{SOURCE0}
ln -s . nginx

%build
cd %{bdir}
./configure %{BASE_CONFIGURE_ARGS} %{MODULE_CONFIGURE_ARGS} \
    --with-cc-opt="%{WITH_CC_OPT}" \
    --with-ld-opt="%{WITH_LD_OPT}" \
    --with-debug
make %{?_smp_mflags} modules
for so in `find %{bdir}/objs/ -type f -name "*.so"`; do \
debugso=`echo $so | sed -e 's|\.so$|-debug.so|'`; \
mv $so $debugso; \
done
./configure %{BASE_CONFIGURE_ARGS} %{MODULE_CONFIGURE_ARGS} \
    --with-cc-opt="%{WITH_CC_OPT}" \
    --with-ld-opt="%{WITH_LD_OPT}"
make %{?_smp_mflags} modules

%install
cd %{bdir}
%{__rm} -rf $RPM_BUILD_ROOT
%{__mkdir} -p $RPM_BUILD_ROOT%{_datadir}/doc/nginx-module-image-filter
%{__install} -m 644 -p %{SOURCE1} \
    $RPM_BUILD_ROOT%{_datadir}/doc/nginx-module-image-filter/COPYRIGHT
%{__mkdir} -p $RPM_BUILD_ROOT%{_libdir}/nginx/modules
for so in `find %{bdir}/objs/ -maxdepth 1 -type f -name "*.so"`; do \
%{__install} -m755 $so \
   $RPM_BUILD_ROOT%{_libdir}/nginx/modules/; \
done

%check
%{__rm} -rf $RPM_BUILD_ROOT/usr/src
cd %{bdir}
grep -v 'usr/src' debugfiles.list > debugfiles.list.new && mv debugfiles.list.new debugfiles.list
cat /dev/null > debugsources.list

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{_libdir}/nginx/modules/*
%dir %{_datadir}/doc/nginx-module-image-filter
%{_datadir}/doc/nginx-module-image-filter/*

%post
if [ $1 -eq 1 ]; then
cat <<BANNER
----------------------------------------------------------------------

The image filter dynamic module for nginx has been installed.
To enable this module, add the following to /etc/nginx/nginx.conf
and reload nginx:

    load_module modules/ngx_http_image_filter_module.so;

Please refer to the module documentation for further details:
https://nginx.org/en/docs/http/ngx_http_image_filter_module.html

----------------------------------------------------------------------
BANNER
fi

%changelog
* Fri Aug 21 2026 Nginx Packaging <nginx-packaging@f5.com> - 1.30.4-1%{?dist}.ngx
- base version updated to 1.30.4-1
