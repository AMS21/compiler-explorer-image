#!/bin/bash

set -ex

. /site.sh

./node_modules/.bin/supervisor -s -e node,js,properties -w app.js,etc,lib -- app.js --env amazon --port 20484 --lang FPC --static out/dist --archivedVersions /opt/compiler-explorer-archive ${EXTRA_ARGS}
