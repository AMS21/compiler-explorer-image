#!/bin/bash

set -ex

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
SUDO=sudo
if [[ $UID = 0 ]]; then
    SUDO=
fi

if [[ -f /env ]]; then
    source /env
fi

DEV_MODE=$1
if [[ "x${DEV_MODE}x" = "xx" ]]; then
    DEV_MODE="dev"
fi

EXTERNAL_PORT=80
CONFIG_FILE=${DIR}/site-prod.sh
ARCHIVE_DIR=/opt/compiler-explorer-archive
if [[ "${DEV_MODE}" != "prod" ]]; then
    EXTERNAL_PORT=7000
    CONFIG_FILE=${DIR}/site-${DEV_MODE}.sh
else
    $SUDO docker pull -a mattgodbolt/compiler-explorer
fi
. ${CONFIG_FILE}

ALL="nginx unified"
$SUDO docker stop ${ALL} || true
$SUDO docker rm ${ALL} || true

CFG="-v ${CONFIG_FILE}:/site.sh:ro"
CFG="${CFG} -e GOOGLE_API_KEY=${GOOGLE_API_KEY}"
CFG="${CFG} -v /opt/compiler-explorer:/opt/compiler-explorer:ro"
CFG="${CFG} -v /var/run/docker.sock:/var/run/docker.sock"

get_released_code() {
    local S3_KEY=$(curl -sL https://s3.amazonaws.com/compiler-explorer/version/${BRANCH})
    local URL=https://s3.amazonaws.com/compiler-explorer/${S3_KEY}
    echo "Unpacking build from ${URL}"
    mkdir -p $1
    pushd $1
    echo ${S3_KEY} > s3_key
    curl -sL ${URL} | tar Jxf -
    if [[ $UID = 0 ]]; then
        chown -R ubuntu .
    fi
    popd
}

update_code() {
    local DEPLOY_DIR=${DIR}/.deploy
    rm -rf ${DEPLOY_DIR}
    get_released_code ${DEPLOY_DIR}
    CFG="${CFG} -v${DEPLOY_DIR}:/compiler-explorer:ro"
    # Back up the 'v' directory to the long-term archive
    # TODO; have the `ce` script do this and then we can mount the nfs drive readonly
    mkdir -p ${ARCHIVE_DIR}
    rsync -av ${DEPLOY_DIR}/out/dist/v/ ${ARCHIVE_DIR}
    CFG="${CFG} -v${ARCHIVE_DIR}:/opt/compiler-explorer-archive:ro"
}

start_container() {
    local NAME=$1
    local PORT=$2
    shift
    shift
    local TAG=${NAME}
    if [[ "${#NAME}" -eq 1 ]]; then
    	NAME="${NAME}x"
    fi
    local FULL_COMMAND="${SUDO} docker run --name ${NAME} ${CFG} -d -p ${PORT}:${PORT} $* mattgodbolt/compiler-explorer:${TAG}"
    local CONTAINER_UID=""
    $SUDO docker stop ${NAME} >&2 || true
    $SUDO docker rm ${NAME} >&2 || true
    CONTAINER_UID=$($FULL_COMMAND)
    sleep 2
    echo ${CONTAINER_UID}
}

wait_for_container() {
    local CONTAINER_UID=$1
    local NAME=$2
    local PORT=$3
    shift
    shift
    shift
    for tensecond in $(seq 15); do
        if ! $SUDO docker ps -q --no-trunc | grep ${CONTAINER_UID}; then
            echo "Container failed to start, logs:"
            $SUDO docker logs ${NAME}
            break
        fi
        if curl http://localhost:$PORT/ > /dev/null 2>&1; then
            echo "Server ${NAME} is up and running"
            return
        fi
        sleep 10
    done
    echo "Failed."
    $SUDO docker logs ${NAME}
}

trap "$SUDO docker stop ${ALL}" SIGINT SIGTERM SIGPIPE

update_code

UID_GCC=$(start_container unified 10240)
wait_for_container ${UID_GCC} unified 10240

$SUDO docker run \
    -p ${EXTERNAL_PORT}:80 \
    --name nginx \
    --volumes-from unified \
    -v /var/log/nginx:/var/log/nginx \
    -v /home/ubuntu:/var/www:ro \
    -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
    -v $(pwd)/nginx:/etc/nginx/sites-enabled:ro \
    --link unified:unified \
    nginx
