# Nginx Custom Builder

## 项目说明

本项目用于自动化编译定制版 Nginx，支持 amd64 与 arm64 架构。

功能：

-   GitHub Actions 自动构建
-   手动本地构建
-   多架构编译
-   GitHub Release 发布
-   SHA256 校验
-   构建信息记录

## 构建流程

    Git Push / 手动触发
            |
            v
    GitHub Actions
            |
       +----+----+
       |         |
     amd64     arm64
     runner    runner
       |         |
       +----+----+
            |
         Docker Builder
            |
         编译 Nginx
            |
       GitHub Release

## 支持版本

默认版本：

    nginx 1.30.4

版本配置：

    config/nginx-version.conf

示例：

``` bash
NGINX_VERSION=1.30.4
```

## 包含模块

官方模块：

-   http_ssl_module
-   http_v2_module
-   stream
-   stream_ssl_module
-   threads

第三方模块：

-   ngx_http_substitutions_filter_module
-   ngx_http_proxy_connect_module
-   nginx_upstream_check_module

## 依赖版本

    OpenSSL 1.1.1w
    PCRE 8.45
    Zlib 1.3.1

## 手动构建

构建 amd64：

``` bash
./build-nginx.sh amd64
```

构建 arm64：

``` bash
./build-nginx.sh arm64
```

指定版本：

``` bash
./build-nginx.sh amd64 1.31.3
```

## Docker 构建

示例：

``` bash
docker build   --build-arg TARGETARCH=amd64   -t nginx-builder:amd64 .
```

运行：

``` bash
docker run   --rm   -e OUTPUT_DIR=/output   -v $(pwd)/output:/output   nginx-builder:amd64
```

## 输出文件

示例：

    output/
    ├── nginx-1.30.4-glibc2.17-amd64.tar.gz
    ├── nginx-1.30.4-glibc2.17-amd64.tar.gz.sha256
    ├── build-info.txt
    └── build.log

## SHA256 校验

``` bash
sha256sum -c nginx-*.sha256
```

## GitHub Actions

支持：

-   push master 自动构建
-   workflow_dispatch 手动构建
-   输入 nginx_version 指定版本
-   手动控制第三方模块是否编译，默认全部开启：
    -   enable_sub_filter
    -   enable_proxy_connect
    -   enable_upstream_check

## HAP Webhook

GitHub Actions 可将 Release 信息推送到明道云 HAP Webhook。附件字段使用
JSON 字符串传递多个下载地址：

```json
{
  "project_name": "nginx",
  "repository": "1447443432/nginx-make",
  "version": "1.30.4",
  "tag": "nginx-1.30.4",
  "release_url": "https://github.com/1447443432/nginx-make/releases/tag/nginx-1.30.4",
  "amd64_name": "nginx-1.30.4-glibc2.17-amd64.tar.gz",
  "amd64_url": "https://example.com/nginx-amd64.tar.gz",
  "amd64_sha256": "sha256-value",
  "arm64_name": "nginx-1.30.4-glibc2.17-arm64.tar.gz",
  "arm64_url": "https://example.com/nginx-arm64.tar.gz",
  "arm64_sha256": "sha256-value",
  "attachment_urls": "[\"https://example.com/nginx-amd64.tar.gz\",\"https://example.com/nginx-arm64.tar.gz\"]",
  "commit_sha": "e7daeca",
  "run_id": "manual-test-20260821",
  "run_url": "https://github.com/1447443432/nginx-make/actions",
  "build_status": "success"
}
```

其中 `attachment_urls` 必须是字符串形式的 JSON 数组，HAP 工作流可将其中
的下载地址写入附件字段。

## 构建参数

### BUILD_JOBS

控制编译线程：

``` bash
BUILD_JOBS=4 ./build.sh
```

### DEBUG

开启调试：

``` bash
DEBUG=true ./build.sh
```

### SHOW_BUILD_LOG

显示完整编译日志：

``` bash
SHOW_BUILD_LOG=true ./build.sh
```

### 第三方模块开关

本地构建时可通过环境变量关闭第三方模块，默认值为 `true`：

``` bash
ENABLE_SUB_FILTER=false ./build-nginx.sh amd64
ENABLE_PROXY_CONNECT=false ./build-nginx.sh amd64
ENABLE_UPSTREAM_CHECK=false ./build-nginx.sh amd64
```

## 版本兼容

nginx 1.30：

    proxy_connect_rewrite_130.patch

nginx 1.31：

    proxy_connect_rewrite_131.patch

nginx 1.31.x 使用：

    --with-cc-opt=-Wno-error

避免新版本源码 warning 被编译器当成 error。

## 架构说明

推荐：

    amd64 -> amd64 runner
    arm64 -> arm64 runner

不建议使用 QEMU 模拟编译。

## 目录结构

    .
    ├── Dockerfile
    ├── build-nginx.sh
    ├── build.sh
    ├── config
    ├── docker
    ├── modules
    ├── nginx
    └── .github
        └── workflows
            └── build-nginx.yml
