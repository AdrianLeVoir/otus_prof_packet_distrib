#!/usr/bin/env bash
# build_rpm.sh — сборка RPM nginx со сторонним модулем ngx_brotli (Rocky Linux 10).
# Запуск от root:  sudo bash build_rpm.sh
set -euo pipefail

echo "===> Установка инструментов сборки"
dnf install -y rpmdevtools rpm-build createrepo_c yum-utils \
               gcc make wget git cmake nginx

echo "===> Загрузка и установка SRPM nginx"
cd /root
dnf download --source nginx
rpm -Uvh nginx-*.src.rpm

echo "===> Зависимости сборки nginx"
dnf builddep -y /root/rpmbuild/SPECS/nginx.spec

echo "===> Исходники модуля ngx_brotli"
rm -rf /root/ngx_brotli
git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli

echo "===> Сборка библиотеки brotli"
cd /root/ngx_brotli/deps/brotli
mkdir -p out && cd out
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INSTALL_PREFIX=./installed ..
cmake --build . --config Release -j 2 --target brotlienc

echo "===> Добавление модуля в spec-файл"
S=/root/rpmbuild/SPECS/nginx.spec
cp -n "$S" "$S.orig" || true
awk '{ if ($0 ~ /--with-cc-opt/) print "    --add-module=/root/ngx_brotli \\"; print }' \
    "$S" > "$S.new" && mv "$S.new" "$S"
grep -n "add-module" "$S"

echo "===> Сборка RPM"
cd /root/rpmbuild/SPECS
rpmbuild -ba nginx.spec -D 'debug_package %{nil}' -D "_topdir /root/rpmbuild"

echo "===> Готовые пакеты:"
ls -l /root/rpmbuild/RPMS/x86_64/ /root/rpmbuild/RPMS/noarch/
