#!/usr/bin/env bash
# create_repo.sh — создание RPM-репозитория с собранным пакетом через Nginx.
# Запуск от root:  sudo bash create_repo.sh
set -euo pipefail

echo "===> Установка собранного пакета"
cd /root/rpmbuild/RPMS/x86_64
cp ../noarch/*.rpm .
dnf -y localinstall *.rpm
systemctl enable --now nginx

echo "===> Каталог репозитория и копирование RPM"
mkdir -p /usr/share/nginx/html/repo
cp /root/rpmbuild/RPMS/x86_64/*.rpm /usr/share/nginx/html/repo/

echo "===> Инициализация репозитория (createrepo_c)"
createrepo_c /usr/share/nginx/html/repo/

echo "===> Включение листинга в Nginx"
grep -q 'autoindex on' /etc/nginx/nginx.conf || \
  sed -i '/root         \/usr\/share\/nginx\/html;/a\        autoindex on;' /etc/nginx/nginx.conf
nginx -t
nginx -s reload

echo "===> Проверка"
curl -s http://localhost/repo/ | head

echo "===> Подключение репозитория в dnf"
cat > /etc/yum.repos.d/otus.repo <<'R'
[otus]
name=otus-linux
baseurl=http://localhost/repo
gpgcheck=0
enabled=1
R
dnf makecache
dnf repolist enabled | grep -i otus
