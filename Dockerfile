ARG TARGETARCH=amd64

# FROM registry.cn-hangzhou.aliyuncs.com/hap-mdy/linux_${TARGETARCH}_centos:7.9.2009
FROM registry.cn-hangzhou.aliyuncs.com/jing-images/linux_${TARGETARCH}_centos_builder:7.9.2009

WORKDIR /data/mdtemp

COPY docker ./docker
COPY nginx ./nginx
COPY modules ./modules
COPY build.sh .

RUN chmod +x build.sh

USER root

ENTRYPOINT ["./build.sh"]