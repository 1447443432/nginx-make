#!/bin/bash
set -euo pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${BASE_DIR}"

DEFAULT_NGINX_VERSION="1.30.4"

if [ -f config/nginx-version.conf ]; then
    source config/nginx-version.conf
fi

ARCH=${1:-amd64}
NGINX_VERSION=${2:-${NGINX_VERSION:-${DEFAULT_NGINX_VERSION}}}

OUTPUT_DIR=${OUTPUT_DIR:-${BASE_DIR}/output}
BUILD_LOG=${OUTPUT_DIR}/build.log
STAGE_LOG=${OUTPUT_DIR}/stage-time.log
BUILD_INFO=${OUTPUT_DIR}/build-info.txt

BUILD_JOBS=${BUILD_JOBS:-$(nproc)}
DEBUG=${DEBUG:-false}

OPENSSL_VERSION="1.1.1w"
PCRE_VERSION="8.45"
ZLIB_VERSION="1.3.1"
SUB_FILTER_VERSION="0.6.4"
PROXY_CONNECT_VERSION="0.0.7"
UPSTREAM_CHECK_VERSION="0.4.0"

mkdir -p "${OUTPUT_DIR}"

: > "${BUILD_LOG}"
: > "${STAGE_LOG}"

if [ "${DEBUG}" = "true" ]; then
    set -x
fi

START_TIME=$(date +%s)
STAGE_START=0

stage_start()
{
    STAGE_START=$(date +%s)
}

stage_success()
{
    local end
    local cost
    end=$(date +%s)
    cost=$((end-STAGE_START))
    echo "[OK] $1 (${cost}s)"
    echo "$1=${cost}s" >> "${STAGE_LOG}"
}

stage_fail()
{
    echo ""
    echo "[ERROR] $1"
    echo "========== last log =========="
    tail -100 "${BUILD_LOG}" || true
    echo "=============================="
    exit 1
}

run_stage()
{
    local name=$1
    shift
    stage_start
    "$@" >> "${BUILD_LOG}" 2>&1 || stage_fail "${name}"
    stage_success "${name}"
}

show_progress()
{
    local pid=$1
    local name=$2
    local start
    local index=1

    start=$(date +%s)

    while kill -0 "${pid}" 2>/dev/null
    do
        sleep 1

        local now
        local cost
        local dots

        now=$(date +%s)
        cost=$((now-start))

        case ${index} in
            1) dots="." ;;
            2) dots=".." ;;
            3) dots="..." ;;
        esac

        printf "\r[INFO] %s running%s %ss" "${name}" "${dots}" "${cost}"

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

    stage_start

    "$@" >> "${BUILD_LOG}" 2>&1 &
    local pid=$!

    show_progress "${pid}" "${name}"

    if wait "${pid}"; then
        stage_success "${name}"
    else
        stage_fail "${name}"
    fi
}

validate_version()
{
    if ! echo "${NGINX_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
    then
        echo "invalid nginx version:${NGINX_VERSION}"
        exit 1
    fi
}

detect_arch()
{
    case "$(uname -m)" in
        x86_64)
            HOST_ARCH="amd64"
            ;;
        aarch64)
            HOST_ARCH="arm64"
            ;;
        *)
            echo "unsupported arch"
            exit 1
            ;;
    esac

    BUILD_ARCH="${ARCH}"
}

download_nginx()
{
    mkdir -p nginx

    NGINX_TAR="nginx/nginx-${NGINX_VERSION}.tar.gz"

    if [ -f "${NGINX_TAR}" ]; then
        echo "use existing nginx source"
        return
    fi

    echo "download nginx ${NGINX_VERSION}"

    curl -fL \
    -o "${NGINX_TAR}" \
    "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"

    test -f "${NGINX_TAR}" || exit 1
}

detect_nginx()
{
    NGINX_DIR="${BASE_DIR}/nginx/nginx-${NGINX_VERSION}"

    echo "nginx=${NGINX_VERSION}"
}

select_patch()
{
    local version

    version=$(echo "${NGINX_VERSION}" | awk -F. '{print $1"."$2}')

    case "${version}" in
        1.30)
            PROXY_PATCH="docker/patches/proxy_connect/proxy_connect_rewrite_130.patch"
            ;;
        1.31)
            PROXY_PATCH="docker/patches/proxy_connect/proxy_connect_rewrite_131.patch"
            ;;
        *)
            echo "unsupported nginx version:${version}"
            exit 1
            ;;
    esac

    test -f "${PROXY_PATCH}" || {
        echo "patch not found:${PROXY_PATCH}"
        exit 1
    }
}

extract_source()
{
    if [ ! -d "${NGINX_DIR}" ]; then
        tar zxf "${NGINX_TAR}" -C nginx
    fi

    rm -rf nginx-modules
    mkdir -p nginx-modules

    tar zxf modules/openssl-${OPENSSL_VERSION}.tar.gz \
        -C nginx-modules

    tar zxf modules/pcre-${PCRE_VERSION}.tar.gz \
        -C nginx-modules

    tar zxf modules/zlib-${ZLIB_VERSION}.tar.gz \
        -C nginx-modules

    tar zxf modules/ngx_http_substitutions_filter_module-${SUB_FILTER_VERSION}.tar.gz \
        -C nginx-modules

    tar zxf modules/ngx_http_proxy_connect_module-${PROXY_CONNECT_VERSION}.tar.gz \
        -C nginx-modules

    tar zxf modules/nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION}.tar.gz \
        -C nginx-modules
}

apply_patch()
{
    cd "${NGINX_DIR}"

    patch -p1 < "${BASE_DIR}/${PROXY_PATCH}"

    patch -p1 \
    < "${BASE_DIR}/nginx-modules/nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION}/check_1.20.1+.patch"
}

configure_nginx()
{
    cd "${NGINX_DIR}"

    ./configure \
    --prefix=/usr/local/nginx \
    --add-module=../../nginx-modules/ngx_http_substitutions_filter_module-${SUB_FILTER_VERSION} \
    --add-module=../../nginx-modules/ngx_http_proxy_connect_module-${PROXY_CONNECT_VERSION} \
    --add-module=../../nginx-modules/nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION} \
    --with-openssl=../../nginx-modules/openssl-${OPENSSL_VERSION} \
    --with-openssl-opt=no-shared \
    --with-pcre=../../nginx-modules/pcre-${PCRE_VERSION} \
    --with-zlib=../../nginx-modules/zlib-${ZLIB_VERSION} \
    --with-http_sub_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_slice_module \
    --with-http_auth_request_module \
    --with-http_secure_link_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads
}

compile_nginx()
{
    cd "${NGINX_DIR}"
    make -j"${BUILD_JOBS}"
}

install_nginx()
{
    cd "${NGINX_DIR}"
    make install
}

verify_nginx()
{
    /usr/local/nginx/sbin/nginx -V
}

check_binary()
{
    if [ ! -x /usr/local/nginx/sbin/nginx ]; then
        echo "nginx binary not found"
        exit 1
    fi
}

package_nginx()
{
    local glibc

    glibc=$(ldd --version 2>&1 \
    | head -1 \
    | grep -oE '[0-9]+\.[0-9]+' \
    | head -1)

    PACKAGE_NAME="nginx-${NGINX_VERSION}-glibc${glibc}-${BUILD_ARCH}.tar.gz"

    tar czf \
    "${OUTPUT_DIR}/${PACKAGE_NAME}" \
    -C /usr/local nginx

    sha256sum \
    "${OUTPUT_DIR}/${PACKAGE_NAME}" \
    > "${OUTPUT_DIR}/${PACKAGE_NAME}.sha256"

    cat > "${BUILD_INFO}" <<EOF
nginx_version=${NGINX_VERSION}
openssl_version=${OPENSSL_VERSION}
pcre_version=${PCRE_VERSION}
zlib_version=${ZLIB_VERSION}
proxy_connect_version=${PROXY_CONNECT_VERSION}
upstream_check_version=${UPSTREAM_CHECK_VERSION}
arch=${BUILD_ARCH}
glibc=${glibc}
build_jobs=${BUILD_JOBS}
EOF
}

main()
{
    run_stage "validate version" validate_version
    run_stage "detect arch" detect_arch
    run_stage "download nginx" download_nginx
    run_stage "detect nginx" detect_nginx
    run_stage "select patch" select_patch
    run_stage "extract source" extract_source
    run_stage "apply patch" apply_patch
    run_stage "configure nginx" configure_nginx
    run_long_stage "compile nginx" compile_nginx
    run_stage "install nginx" install_nginx
    run_stage "verify nginx" verify_nginx
    run_stage "check binary" check_binary
    run_stage "package nginx" package_nginx

    local end

    end=$(date +%s)

    echo ""
    echo "================================="
    echo "BUILD SUCCESS"
    echo "nginx=${NGINX_VERSION}"
    echo "arch=${BUILD_ARCH}"
    echo "total=$((end-START_TIME))s"
    echo "================================="
}

main "$@"