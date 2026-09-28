# Домашнее задание: Сборка RPM-пакета и создание репозитория

## Название и формулировка задания

**Сборка RPM-пакета и создание собственного репозитория.**

Цель: научиться собирать RPM-пакеты и создавать собственный RPM-репозиторий.

Что нужно сделать:

1. создать свой RPM-пакет (своё приложение **или**, например, собрать nginx/apache с определёнными опциями);
2. создать свой репозиторий и разместить в нём ранее собранный RPM;
3. реализовать это либо в Vagrant, либо развернуть локально через **Nginx** и дать ссылку на репозиторий.

Критерии приёмки: собран и установлен RPM-пакет; сформирован репозиторий с этим пакетом.

---

## Окружение

Выбран вариант **локального развёртывания через Nginx** (без Vagrant).

| Параметр                  | Значение                                              |
| ------------------------- | ----------------------------------------------------- |
| Хост сборки и репозитория | Rocky Linux VM                                        |
| ОС                        | **Rocky Linux 10.0** (Red Quartz), kernel 6.12        |
| Инструменты               | `rpmbuild` 4.19.1.1, `createrepo_c` 1.1.2, `dnf` 4.20 |
| Собираемый пакет          | **nginx 1.26.3** со сторонним модулем **ngx_brotli**  |
| Публикация                | Nginx 1.26.3, статика `/usr/share/nginx/html/repo`    |

---

## Описание процесса сборки RPM

### 1. Установка инструментария

```bash
dnf install -y rpmdevtools rpm-build createrepo_c yum-utils gcc make wget git cmake nginx
```

### 2. Загрузка и распаковка SRPM nginx

```bash
dnf download --source nginx
rpm -Uvh nginx-1.26.3-6.el10_2.7.src.rpm
dnf builddep -y /root/rpmbuild/SPECS/nginx.spec
```

Команда `rpm -Uvh` распаковывает исходный пакет и создаёт структуру:

```text
/root/rpmbuild/
├── BUILD/
├── BUILDROOT/
├── RPMS/
├── SOURCES/
├── SPECS/
└── SRPMS/
```

### 3. Подготовка модуля `ngx_brotli`

Репозиторий `ngx_brotli` клонируется вместе с необходимым подмодулем `brotli`:

```bash
git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli
```

Сборка библиотеки brotli:

```bash
cd ngx_brotli/deps/brotli
mkdir out && cd out

cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_INSTALL_PREFIX=./installed ..

cmake --build . --config Release -j2 --target brotlienc
```

### 4. Изменение spec-файла

В секцию `configure` файла `nginx.spec` добавляется:

```text
    --add-module=/root/ngx_brotli \
```

Модуль подключается непосредственно при сборке nginx.

### 5. Сборка RPM

```bash
cd /root/rpmbuild/SPECS
rpmbuild -ba nginx.spec \
  -D 'debug_package %{nil}' \
  -D "_topdir /root/rpmbuild"
```

В результате создаются RPM-пакеты в:

```text
/root/rpmbuild/RPMS/x86_64/
/root/rpmbuild/RPMS/noarch/
```

Пример результатов:

```text
nginx-1.26.3-6.el10.7.x86_64.rpm
nginx-core-1.26.3-6.el10.7.x86_64.rpm
nginx-all-modules-...noarch.rpm
nginx-filesystem-...noarch.rpm
nginx-mod-devel-...
nginx-mod-http-image-filter-...
nginx-mod-http-perl-...
nginx-mod-http-xslt-filter-...
nginx-mod-mail-...
nginx-mod-stream-...
```

### 6. Установка собранного пакета

```bash
cd /root/rpmbuild/RPMS/x86_64
cp ../noarch/*.rpm .

dnf -y localinstall *.rpm

systemctl enable --now nginx
```

Проверка параметров сборки:

```bash
nginx -V 2>&1 | tr ' ' '\n' | grep add-module
```

Ожидаемый результат:

```text
--add-module=/root/ngx_brotli
```

### 7. Проверка работы Brotli

В конфигурацию nginx добавлены:

```nginx
brotli on;
brotli_comp_level 6;
```

Проверка:

```bash
curl -sI -H 'Accept-Encoding: br' http://localhost/
```

Результат:

```text
HTTP/1.1 200 OK
Content-Encoding: br
```

Таким образом, проверено не только наличие модуля в собранном nginx, но и фактическая работа Brotli при обработке HTTP-запроса.

---

## Описание репозитория и способа публикации

Для RPM-репозитория используется каталог:

```text
/usr/share/nginx/html/repo
```

В него копируются собранные RPM-пакеты:

```bash
mkdir -p /usr/share/nginx/html/repo
cp /root/rpmbuild/RPMS/x86_64/*.rpm /usr/share/nginx/html/repo/
```

После этого создаются метаданные репозитория:

```bash
createrepo_c /usr/share/nginx/html/repo/
```

В результате создаётся каталог `.repodata` с метаданными, включая `repomd.xml`.

Для публикации репозитория используется Nginx. В конфигурации включён листинг каталога:

```nginx
autoindex on;
```

После изменения конфигурация проверяется и перечитывается:

```bash
nginx -t
nginx -s reload
```

### Ссылка на RPM-репозиторий

Репозиторий доступен внутри локальной сети VM по адресу:

**http://192.168.1.184/repo/**

Также он доступен непосредственно внутри VM:

**http://localhost/repo/**

Адрес `192.168.1.184` является локальным адресом виртуальной машины и предназначен для доступа из соответствующей локальной сети.

---

## Воспроизведение репозитория

Поскольку репозиторий развёрнут локально внутри VM, его можно полностью воспроизвести на другой машине из предоставленных скриптов.

Для воспроизведения необходимо:

1. развернуть Rocky Linux 10;
2. скопировать или клонировать содержимое данного проекта;
3. выполнить `build_rpm.sh`;
4. выполнить `create_repo.sh`;
5. определить IP-адрес VM:

```bash
ip -br a
```

После выполнения скриптов RPM-репозиторий будет доступен по адресу:

```text
http://<VM_IP>/repo/
```

Например:

```text
http://192.168.1.184/repo/
```

### Подключение репозитория на клиенте

Создать файл:

```bash
cat > /etc/yum.repos.d/otus.repo <<'EOF'
[otus]
name=otus-linux
baseurl=http://<VM_IP>/repo
gpgcheck=0
enabled=1
EOF
```

Затем обновить метаданные:

```bash
dnf makecache
```

Проверить подключённый репозиторий:

```bash
dnf repolist enabled | grep -i otus
```

Проверить содержимое:

```bash
dnf repoquery --repo=otus -a
```

Для проверки установки именно из собственного репозитория:

```bash
dnf -y --disablerepo='*' --enablerepo=otus reinstall nginx-core
```

---

## Проверка репозитория

После создания репозитория выполняется:

```bash
dnf repoquery --repo=otus -a
```

Пример результата:

```text
nginx-2:1.26.3-6.el10.7.x86_64
nginx-core-2:1.26.3-6.el10.7.x86_64
...
```

Затем выполняется переустановка пакета только из собственного репозитория:

```bash
dnf -y --disablerepo='*' --enablerepo=otus reinstall nginx-core
```

Успешное выполнение команды подтверждает, что клиент DNF получает пакет через созданный RPM-репозиторий.

---

## Особенности проектирования и реализации

* Реализован вариант из методички: **nginx + модуль ngx_brotli**, сборка из SRPM с изменением spec-файла.
* Модуль `ngx_brotli` подключён как статический через `--add-module=`, поэтому директивы `brotli on;` доступны непосредственно после установки собранного nginx.
* Все необходимые RPM-пакеты nginx сложены в один каталог репозитория, что позволяет DNF разрешать зависимости между пакетами.
* `createrepo_c` формирует метаданные RPM-репозитория.
* В отличие от окружения из методички (AlmaLinux 9.3), используется **Rocky Linux 10** и nginx **1.26.3**.
* Структура `nginx.conf` в используемой версии отличается от структуры из методички: в серверном блоке по умолчанию отсутствует отдельная секция `location /`, поэтому `autoindex on;` добавлен непосредственно в соответствующий `server`-блок.
* Репозиторий публикуется тем же Nginx, который был собран в рамках задания.
* В Rocky Linux используется `firewalld`, поэтому для доступа к HTTP-сервису открыт порт 80:

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
```

---

## Файлы проекта

```text
README.md          — этот отчёт
build_rpm.sh       — сборка nginx RPM со сторонним модулем ngx_brotli
create_repo.sh     — создание RPM-репозитория и публикация через Nginx
logs/              — логи выполнения (утилита script)
  ├── install.log            — установка инструментов
  ├── srpm.log / srpm2.log   — установка SRPM, builddep, клон ngx_brotli
  ├── patch_spec.log         — сборка brotli и правка spec
  ├── rpmbuild.log           — полный лог сборки RPM
  ├── install_rpm.log        — установка собранного пакета, проверка модуля
  ├── repo_setup.log         — копирование RPM, createrepo_c, autoindex, curl
  ├── nginx_autoindex.log    — включение листинга каталога
  ├── repo_use.log           — подключение otus.repo, makecache
  ├── repo_proof.log         — список пакетов и установка из собственного репозитория
  └── brotli_test.log        — проверка модуля brotli (Content-Encoding: br)
```

## Итог

В рамках работы:

* собран собственный RPM-пакет nginx 1.26.3;
* в nginx добавлен сторонний модуль `ngx_brotli`;
* проверена фактическая работа Brotli;
* собран локальный RPM-репозиторий с помощью `createrepo_c`;
* репозиторий опубликован через Nginx;
* репозиторий подключён к DNF;
* выполнена установка/переустановка пакета непосредственно из собственного репозитория;
* подготовлены скрипты для воспроизведения процесса на другой Rocky Linux 10 VM.
