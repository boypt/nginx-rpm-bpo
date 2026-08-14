## Note

Docker image build:
```
docker build -t ngxbuild:el5 -f ./Docker/Dockerfile.centos5 .
docker build -t ngxbuild:el6 -f ./Docker/Dockerfile.centos6 .
docker build -t ngxbuild:el7 -f ./Docker/Dockerfile.centos7 .
```

RPM Build:
```
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```

## Version

- **NGINX**: 1.30.4
- **Release**: b2 (NGINX_REL=2)
- **OpenSSL**: openssl-3.5.7
- **Perl**: perl-5.38.2