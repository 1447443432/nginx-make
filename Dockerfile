ARG TARGETARCH=amd64

FROM registry.cn-hangzhou.aliyuncs.com/hap-mdy/linux_${TARGETARCH}_centos:7.9.2009

WORKDIR /data/mdtemp

COPY docker ./docker
COPY nginx ./nginx
COPY modules ./modules
COPY build.sh .

RUN cp docker/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo \
    && yum clean all \
    && yum makecache fast \
        --setopt=timeout=60 \
        --setopt=retries=5 \
    && yum install -y \
        --setopt=timeout=60 \
        --setopt=retries=5 \
        gcc \
        gcc-c++ \
        make \
        wget \
        patch \
        tar \
        perl \
    && chmod +x build.sh

ENTRYPOINT ["./build.sh"]