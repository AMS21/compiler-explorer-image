#!/bin/bash

docker run --rm --name gcc.build -v$HOME/.s3cfg:/root/.s3cfg:ro mattgodbolt/gcc-builder bash build.sh trunk s3://compiler-explorer/opt/
