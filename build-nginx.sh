#!/bin/bash
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${BASE_DIR}"

ARCH=${1:-amd64}
VERSION_ARG=${2:-}

OUTPUT_DIR="${BASE_DIR}/output"
IMAGE_NAME="nginx-builder:${ARCH}"
DOCKER_LOG="${OUTPUT_DIR}/docker-build.log"

START_TIME=$(date +%s)

init_env()
{
    mkdir -p "${OUTPUT_DIR}"

    if [ -f config/nginx-version.conf ]; then
        source config/nginx-version.conf
    fi

    if [ -n "${VERSION_ARG}" ]; then
        NGINX_VERSION="${VERSION_ARG}"
    else
        NGINX_VERSION=${NGINX_VERSION:-1.30.4}
    fi
}

print_header()
{
    echo "================================="
    echo "nginx build start"
    echo "arch=${ARCH}"
    echo "nginx=${NGINX_VERSION}"
    echo "output=${OUTPUT_DIR}"
    echo "image=${IMAGE_NAME}"
    echo "================================="
}

cost_time()
{
    echo "$(( $(date +%s)-$1 ))s"
}

show_progress()
{
    local pid=$1
    local name=$2

    local start
    start=$(date +%s)

    local index=1

    while kill -0 "${pid}" 2>/dev/null
    do
        sleep 1

        local cost
        local dots

        cost=$(( $(date +%s)-start ))

        case ${index} in
            1)
                dots="."
                ;;
            2)
                dots=".."
                ;;
            3)
                dots="..."
                ;;
        esac

        printf "\r[INFO] %s running%s %ss" \
            "${name}" \
            "${dots}" \
            "${cost}"

        index=$((index+1))

        if [ "${index}" -gt 3 ]; then
            index=1
        fi
    done

    echo ""
}

run_long_stage()
{
    local name=$1
    shift

    "$@" &

    local pid=$!

    show_progress "${pid}" "${name}"

    if wait "${pid}"
    then
        echo "[OK] ${name}"
    else
        echo "[ERROR] ${name}"
        exit 1
    fi
}

docker_build()
{
    docker build \
        --platform linux/${ARCH} \
        --no-cache \
        --build-arg TARGETARCH="${ARCH}" \
        -t "${IMAGE_NAME}" \
        . \
        >"${DOCKER_LOG}" 2>&1

    if [ $? -ne 0 ]; then
        echo ""
        echo "[ERROR] docker build failed"
        echo "log:"
        tail -100 "${DOCKER_LOG}" || true
        exit 1
    fi
}

docker_check()
{
    docker run \
        --rm \
        --entrypoint /bin/bash \
        --user 0:0 \
        "${IMAGE_NAME}" \
        -c "id"
}

docker_run()
{
    docker run \
        --rm \
        --user 0:0 \
        -e NGINX_VERSION="${NGINX_VERSION}" \
        -v "${OUTPUT_DIR}:/output" \
        "${IMAGE_NAME}"
}

check_result()
{
    local package

    echo "========== result =========="

    ls -lh "${OUTPUT_DIR}"

    package=$(find "${OUTPUT_DIR}" \
        -name "nginx-*.tar.gz" \
        | head -1)

    if [ -z "${package}" ]; then
        echo "[ERROR] package not found"
        exit 1
    fi

    echo "================================="
    echo "BUILD SUCCESS"
    echo "package:"
    echo "${package}"

    echo ""
    echo "total:"
    cost_time "${START_TIME}"

    echo "================================="
}

main()
{
    init_env
    print_header

    echo "========== docker build =========="
    run_long_stage "docker build" docker_build

    echo "========== docker check =========="
    docker_check

    echo "========== docker run =========="
    run_long_stage "docker run" docker_run

    check_result
}

main "$@"