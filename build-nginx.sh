#!/bin/bash
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${BASE_DIR}"

ARCH=${1:-amd64}
DEBUG_MODE=${DEBUG_MODE:-false}
OUTPUT_DIR=${OUTPUT_DIR:-${BASE_DIR}/output}
IMAGE_NAME=${IMAGE_NAME:-nginx-builder:${ARCH}}

DOCKER_BUILD_LOG=${OUTPUT_DIR}/docker-build.log
BUILD_LOG=${OUTPUT_DIR}/build.log
STAGE_LOG=${OUTPUT_DIR}/stage-time.log

START_TIME=$(date +%s)

mkdir -p "${OUTPUT_DIR}"
rm -f "${DOCKER_BUILD_LOG}" "${BUILD_LOG}" "${STAGE_LOG}"

print_header()
{
    echo "================================="
    echo "nginx build start"
    echo "arch=${ARCH}"
    echo "output=${OUTPUT_DIR}"
    echo "debug=${DEBUG_MODE}"
    echo "image=${IMAGE_NAME}"
    echo "================================="
}

error()
{
    echo "[ERROR] $1"
    echo "log:"
    echo "$2"
    exit 1
}

wait_progress()
{
    local pid=$1
    local name=$2
    local start=$(date +%s)
    local dot=1

    while kill -0 "${pid}" 2>/dev/null
    do
        sleep 1
        local now=$(date +%s)
        local cost=$((now-start))

        case ${dot} in
        1) dots="." ;;
        2) dots=".." ;;
        3) dots="..." ;;
        esac

        printf "\r%-80s" "[INFO] ${name} running${dots} ${cost}s"

        dot=$((dot+1))
        [ ${dot} -gt 3 ] && dot=1
    done
    echo ""
}

build_image()
{
    echo "========== docker build =========="

    local start=$(date +%s)

    if [ "${DEBUG_MODE}" = "true" ]
    then
        docker build \
        --build-arg TARGETARCH=${ARCH} \
        -t "${IMAGE_NAME}" .
    else
        docker build \
        --build-arg TARGETARCH=${ARCH} \
        -t "${IMAGE_NAME}" . \
        > "${DOCKER_BUILD_LOG}" 2>&1 &

        local pid=$!

        wait_progress ${pid} "docker build"

        if ! wait ${pid}
        then
            error "docker build failed" "${DOCKER_BUILD_LOG}"
        fi
    fi

    local end=$(date +%s)
    echo "[OK] docker build ($((end-start))s)"
    echo "docker build=$((end-start))s" >> "${STAGE_LOG}"
}

run_builder()
{
    echo "========== docker run =========="

    local start=$(date +%s)

    if ! docker run --rm \
    -v "${OUTPUT_DIR}:/output" \
    -e DEBUG_MODE="${DEBUG_MODE}" \
    -e OUTPUT_DIR=/output \
    -e BUILD_LOG=/output/build.log \
    "${IMAGE_NAME}"
    then
        error "nginx build failed" "${BUILD_LOG}"
    fi

    local end=$(date +%s)
    echo "[OK] docker run ($((end-start))s)"
    echo "docker run=$((end-start))s" >> "${STAGE_LOG}"
}

check_output()
{
    echo "========== result =========="

    ls -lh "${OUTPUT_DIR}"

    PACKAGE=$(find "${OUTPUT_DIR}" -maxdepth 1 -name "nginx-*.tar.gz" | head -1)

    if [ -z "${PACKAGE}" ]
    then
        error "package not found" "${BUILD_LOG}"
    fi

    if command -v sha256sum >/dev/null 2>&1
    then
        sha256sum "${PACKAGE}" > "${PACKAGE}.sha256"
    fi

    local end=$(date +%s)

    echo "================================="
    echo "BUILD SUCCESS"
    echo "package:"
    echo "${PACKAGE}"
    echo ""
    echo "time:"
    cat "${STAGE_LOG}"
    echo "total=$((end-START_TIME))s"
    echo "================================="
}

main()
{
    case "${ARCH}" in
    amd64|arm64)
        ;;
    *)
        echo "Usage: $0 amd64|arm64"
        exit 1
        ;;
    esac

    command -v docker >/dev/null 2>&1 || {
        echo "docker not found"
        exit 1
    }

    print_header
    build_image
    run_builder
    check_output
}

main "$@"