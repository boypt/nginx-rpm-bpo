#!/bin/bash

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"

docker images
docker run --rm -v $__dir/..:/data ngxbuild:el6
docker run --rm -v $__dir/..:/data ngxbuild:el7
docker run --rm -v $__dir/..:/data -e M32=1 ngxbuild:el5

