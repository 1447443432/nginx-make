#!/bin/bash
set -euo pipefail

DEBUG_MODE=${DEBUG_MODE:-false}
OUTPUT_DIR=${OUTPUT_DIR:-/output}
BUILD_LOG=${BUILD_LOG:-${OUTPUT_DIR}/build.log}
BUILD_JOBS=${BUILD_JOBS:-$(nproc)}

mkdir -p "${OUTPUT_DIR}"

[ "${DEBUG_MODE}" = "true" ] && set -x

SCRIPT_START=$(date +%s)
STAGE_START=0
NGINX_DIR=""

OPENSSL_VERSION="1.1.1w"
PCRE_VERSION="8.45"
ZLIB_VERSION="1.3.1"
SUB_FILTER_VERSION="0.6.4"
PROXY_CONNECT_VERSION="0.0.7"
UPSTREAM_CHECK_VERSION="0.4.0"

stage_start()
{
    STAGE_START=$(date +%s)
}

success()
{
    local end=$(date +%s)
    local cost=$((end-STAGE_START))

    echo "[OK] $1 (${cost}s)"
    echo "$1=${cost}s" >> "${OUTPUT_DIR}/stage-time.log"
}

fail()
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

    "$@" >> "${BUILD_LOG}" 2>&1 || fail "${name} failed"

    success "${name}"
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

run_long_stage()
{
    local name=$1
    shift

    stage_start

    "$@" >> "${BUILD_LOG}" 2>&1 &

    local pid=$!

    wait_progress "${pid}" "${name}"

    if wait "${pid}"
    then
        success "${name}"
    else
        fail "${name} failed"
    fi
}

detect_arch()
{
    case "$(uname -m)" in
    x86_64)
        BUILD_ARCH="amd64"
        ;;
    aarch64)
        BUILD_ARCH="arm64"
        ;;
    *)
        fail "unsupported arch"
        ;;
    esac
}

detect_nginx()
{
    NGINX_TAR=$(find nginx -name "nginx-*.tar.gz" | head -1)

    [ -z "${NGINX_TAR}" ] && fail "nginx source not found"

    NGINX_VERSION=$(basename "${NGINX_TAR}" \
    | sed 's/nginx-//' \
    | sed 's/.tar.gz//')

    NGINX_DIR="$(pwd)/nginx-${NGINX_VERSION}"

    echo "nginx version=${NGINX_VERSION}"
    echo "nginx dir=${NGINX_DIR}"
}

select_patch()
{
    VERSION=$(echo "${NGINX_VERSION}" | awk -F. '{print $1"."$2}')

    case "${VERSION}" in
    1.30)
        PROXY_PATCH="docker/patches/proxy_connect/proxy_connect_rewrite_130.patch"
        ;;
    1.31)
        PROXY_PATCH="docker/patches/proxy_connect/proxy_connect_rewrite_131.patch"
        ;;
    *)
        fail "unsupported nginx version ${VERSION}"
        ;;
    esac

    [ -f "${PROXY_PATCH}" ] || fail "patch not found ${PROXY_PATCH}"
}

extract_source()
{
    tar zxf "${NGINX_TAR}"

    mkdir -p nginx-modules

    for m in \
    openssl-${OPENSSL_VERSION}.tar.gz \
    pcre-${PCRE_VERSION}.tar.gz \
    zlib-${ZLIB_VERSION}.tar.gz \
    ngx_http_substitutions_filter_module-${SUB_FILTER_VERSION}.tar.gz \
    ngx_http_proxy_connect_module-${PROXY_CONNECT_VERSION}.tar.gz \
    nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION}.tar.gz
    do
        tar zxf modules/${m} -C nginx-modules
    done
}

apply_patch()
{
    cd "${NGINX_DIR}"

    patch -p1 < "../${PROXY_PATCH}"

    patch -p1 \
    < "../nginx-modules/nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION}/check_1.20.1+.patch"
}

configure_nginx()
{
    cd "${NGINX_DIR}"

    ./configure \
    --prefix=/usr/local/nginx \
    --add-module=../nginx-modules/ngx_http_substitutions_filter_module-${SUB_FILTER_VERSION} \
    --add-module=../nginx-modules/ngx_http_proxy_connect_module-${PROXY_CONNECT_VERSION} \
    --add-module=../nginx-modules/nginx_upstream_check_module-${UPSTREAM_CHECK_VERSION} \
    --with-openssl=../nginx-modules/openssl-${OPENSSL_VERSION} \
    --with-openssl-opt=no-shared \
    --with-pcre=../nginx-modules/pcre-${PCRE_VERSION} \
    --with-zlib=../nginx-modules/zlib-${ZLIB_VERSION} \
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
    test -x /usr/local/nginx/sbin/nginx \
    || fail "nginx binary missing"

    echo "nginx binary:"
    ls -lh /usr/local/nginx/sbin/nginx
}

package_nginx()
{
    GLIBC_VERSION=$(ldd --version 2>&1 \
    | head -1 \
    | grep -oE '[0-9]+\.[0-9]+' \
    | head -1)

    PACKAGE_NAME="nginx-${NGINX_VERSION}-glibc${GLIBC_VERSION}-${BUILD_ARCH}.tar.gz"

    PACKAGE_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}"

    tar czf "${PACKAGE_FILE}" \
    -C /usr/local \
    nginx

    [ -f "${PACKAGE_FILE}" ] || fail "package missing"

    sha256sum "${PACKAGE_FILE}" > "${PACKAGE_FILE}.sha256"

    cat > "${OUTPUT_DIR}/build-info.txt" <<EOF
nginx_version=${NGINX_VERSION}
openssl_version=${OPENSSL_VERSION}
pcre_version=${PCRE_VERSION}
zlib_version=${ZLIB_VERSION}
proxy_connect_version=${PROXY_CONNECT_VERSION}
upstream_check_version=${UPSTREAM_CHECK_VERSION}
arch=${BUILD_ARCH}
glibc=${GLIBC_VERSION}
build_jobs=${BUILD_JOBS}
EOF

    echo "package=${PACKAGE_FILE}"
}

main()
{
    echo "========== nginx build =========="

    run_stage "detect arch" detect_arch
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

    local end=$(date +%s)

    echo ""
    echo "================================="
    echo "BUILD SUCCESS"
    echo "total time $((end-SCRIPT_START))s"
    echo "================================="
}

main "$@"