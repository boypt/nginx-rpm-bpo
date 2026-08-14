
## Note

Docker image build:
```
	docker build -t ngxbuild:el5 -f ./NGINX/Dockerfile.centos5 .
	docker build -t ngxbuild:el6 -f ./NGINX/Dockerfile.centos6 .
	docker build -t ngxbuild:el7 -f ./NGINX/Dockerfile.centos7 .

```

RPM Build:

```
docker run --rm -v .:/data ngxbuild:el6
docker run --rm -v .:/data ngxbuild:el7
docker run --rm -v .:/data -e M32=1 ngxbuild:el5
```
