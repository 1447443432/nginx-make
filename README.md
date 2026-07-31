##### 手动编译 amd 64 

```bash
[[ -d '/usr/local/nginx' ]] && (cp -a /usr/local/nginx /usr/local/nginx-bak$(date +%Y%m%d%H%M%S); echo "注意：当前环境已存在nginx")

centos_image="registry.cn-hangzhou.aliyuncs.com/hap-mdy/linux_amd64_centos:7.9.2009"
docker pull $centos_image

docker run -itd --rm -v /root/jing/build/nginx:/data/mdtemp --name centos7 $centos_image bash

docker exec -it centos7 bash

# amd64 的 yum 源
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
yum makecache fast
sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo

# 安装依赖
yum install -y gcc gcc-c++ make wget git patch

cd /data/mdtemp
tar -zxf nginx-1.30.4.tar.gz

mkdir -p nginx-modules

tar -zxf openssl-1.1.1w.tar.gz -C nginx-modules/
tar -zxf pcre-8.45.tar.gz -C nginx-modules/
tar -zxf zlib-1.3.1.tar.gz -C nginx-modules/
tar -zxf ngx_http_substitutions_filter_module-0.6.4.tar.gz -C nginx-modules/
# 处理正向代理模块
tar -zxf ngx_http_proxy_connect_module-0.0.7.tar.gz -C nginx-modules/
cp -a nginx-modules/ngx_http_proxy_connect_module-0.0.7 \
      nginx-modules/ngx_http_proxy_connect_module-1.30

cp -a nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_102101.patch \
nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

grep -n "ngx_http_validate_host" nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

sed -i \
's/ngx_http_validate_host(\&host, r->pool, 0)/ngx_http_validate_host(\&host, NULL, r->pool, 0)/g' \
nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

grep -n "ngx_http_validate_host" nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch
tar -zxf nginx_upstream_check_module-0.4.0.tar.gz -C nginx-modules/

cd nginx-1.30.4/
#patch -p1 < ../nginx-modules/ngx_http_proxy_connect_module-0.0.7/patch/proxy_connect_rewrite_102101.patch
patch -p1 < ../nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

patch -p1 < ../nginx-modules/nginx_upstream_check_module-0.4.0/check_1.20.1+.patch

./configure \
    --prefix=/usr/local/nginx \
    --add-module=../nginx-modules/ngx_http_substitutions_filter_module-0.6.4 \
    --add-module=../nginx-modules/ngx_http_proxy_connect_module-1.30 \
    --add-module=../nginx-modules/nginx_upstream_check_module-0.4.0 \
    --with-openssl=../nginx-modules/openssl-1.1.1w \
    --with-openssl-opt=no-shared \
    --with-pcre=../nginx-modules/pcre-8.45 \
    --with-zlib=../nginx-modules/zlib-1.3.1 \
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


#make -j$(nproc)
make
make install

echo "Nginx 编译安装完成！"

#ldd --version
#ldd --version | grep ldd | awk '{print $NF}'
cd /usr/local/
tar_name="nginx-$(/usr/local/nginx/sbin/nginx -v 2>&1 | awk -F '/' '{print $2}')-glibc$(ldd --version | grep ldd | awk '{print $NF}')-amd64.tar.gz"
tar czvf $tar_name nginx
ls -l $tar_name
```

##### 手动编译 arm 64 

```bash
[[ -d '/usr/local/nginx' ]] && (cp -a /usr/local/nginx /usr/local/nginx-bak$(date +%Y%m%d%H%M%S); echo "注意：当前环境已存在nginx")

centos_image="registry.cn-hangzhou.aliyuncs.com/hap-mdy/linux_arm64_centos:7.9.2009"
docker pull $centos_image

docker run -itd --rm -v /root/jing/build/nginx:/data/mdtemp --name centos7 $centos_image bash

docker exec -it centos7 bash

# arm64 的 yum 源
cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-7 - Base
baseurl=https://mirrors.aliyun.com/centos-altarch/7/os/aarch64/
enabled=1
gpgcheck=0

[updates]
name=CentOS-7 - Updates
baseurl=https://mirrors.aliyun.com/centos-altarch/7/updates/aarch64/
enabled=1
gpgcheck=0

[extras]
name=CentOS-7 - Extras
baseurl=https://mirrors.aliyun.com/centos-altarch/7/extras/aarch64/
enabled=1
gpgcheck=0
EOF

yum makecache fast

# 安装依赖
yum install -y gcc gcc-c++ make wget git patch

cd /data/mdtemp
tar -zxf nginx-1.30.4.tar.gz

mkdir -p nginx-modules

tar -zxf openssl-1.1.1w.tar.gz -C nginx-modules/
tar -zxf pcre-8.45.tar.gz -C nginx-modules/
tar -zxf zlib-1.3.1.tar.gz -C nginx-modules/
tar -zxf ngx_http_substitutions_filter_module-0.6.4.tar.gz -C nginx-modules/
# 处理正向代理模块
tar -zxf ngx_http_proxy_connect_module-0.0.7.tar.gz -C nginx-modules/
cp -a nginx-modules/ngx_http_proxy_connect_module-0.0.7 \
      nginx-modules/ngx_http_proxy_connect_module-1.30

cp -a nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_102101.patch \
nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

grep -n "ngx_http_validate_host" nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

sed -i \
's/ngx_http_validate_host(\&host, r->pool, 0)/ngx_http_validate_host(\&host, NULL, r->pool, 0)/g' \
nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

grep -n "ngx_http_validate_host" nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch
tar -zxf nginx_upstream_check_module-0.4.0.tar.gz -C nginx-modules/

cd nginx-1.30.4/
#patch -p1 < ../nginx-modules/ngx_http_proxy_connect_module-0.0.7/patch/proxy_connect_rewrite_102101.patch
patch -p1 < ../nginx-modules/ngx_http_proxy_connect_module-1.30/patch/proxy_connect_rewrite_1030.patch

patch -p1 < ../nginx-modules/nginx_upstream_check_module-0.4.0/check_1.20.1+.patch

./configure \
    --prefix=/usr/local/nginx \
    --add-module=../nginx-modules/ngx_http_substitutions_filter_module-0.6.4 \
    --add-module=../nginx-modules/ngx_http_proxy_connect_module-1.30 \
    --add-module=../nginx-modules/nginx_upstream_check_module-0.4.0 \
    --with-openssl=../nginx-modules/openssl-1.1.1w \
    --with-openssl-opt=no-shared \
    --with-pcre=../nginx-modules/pcre-8.45 \
    --with-zlib=../nginx-modules/zlib-1.3.1 \
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


#make -j$(nproc)
make
make install

echo "Nginx 编译安装完成！"

#ldd --version
#ldd --version | grep ldd | awk '{print $NF}'
cd /usr/local/
tar_name="nginx-$(/usr/local/nginx/sbin/nginx -v 2>&1 | awk -F '/' '{print $2}')-glibc$(ldd --version | grep ldd | awk '{print $NF}')-amd64.tar.gz"
tar czvf $tar_name nginx
ls -l $tar_name
```

