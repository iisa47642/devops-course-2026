# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

UTM 4.6.4, QEMU с аппаратной виртуализацией Apple HVF, Ubuntu Server 24.04 ARM64. Два ядра, 2048 МБ RAM, диск QCOW2 25 ГБ. Использован официальный cloud image Ubuntu; пакеты обновлены через apt.

Файл машины на Mac: `/Users/isaevisa/Virtual Machines/devops-vm.utm`. Машину сохраняю для следующих практик.

## 2. Сетевые интерфейсы

| Интерфейс | Режим UTM | IPv4 | Назначение |
| --- | --- | --- | --- |
| enp0s8 | Emulated VLAN (NAT) | 10.0.2.15/24, DHCP | Интернет, установка пакетов |
| enp0s9 | Host Only | 192.168.56.101/24, статический | Прямое соединение с Mac |

Шлюз NAT: 10.0.2.2. Адрес Mac в Host-only: 192.168.56.1.
DNS NAT 10.0.2.3 не отвечал. В `/etc/netplan/60-devops-dns.yaml` отключено получение DNS по DHCP и заданы 1.1.1.1 и 8.8.8.8. После `sudo netplan apply` разрешение имён и apt заработали.

## 3. Правило проброса портов

TCP, адрес Mac 127.0.0.1, порт Mac 2222. Сначала порт гостя был 22, после настройки SSH изменён на 2222. Прямой доступ по Host-only не использует проброс.

На Mac в `/etc/hosts`:

```text
192.168.56.101 devops.local
```

В `~/.ssh/config`:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 4. Учётные записи

`student` — исходный пользователь с sudo для консоли. `devops` — отдельный пользователь, группы devops, sudo, users. По SSH разрешён только devops, вход по Ed25519. sudo по-прежнему требует пароль пользователя Ubuntu.

Закрытый ключ `~/.ssh/devops_vm` хранится только на Mac, публичная часть размещена в `/home/devops/.ssh/authorized_keys`. Права каталога 700, файла 600. Для этого сервера используется отдельный ключ, не ключ GitHub. В репозитории ключей и паролей нет.

Ключ хоста был задан при развёртывании через локальный cloud-init. Его открытая часть сверена с `/etc/ssh/ssh_host_ed25519_key.pub`; в known_hosts сохранён именно этот ключ.

## 5. Служба SSH

Все параметры приведены в `configs/99-hardening.conf`. Основной файл сохранён как `/etc/ssh/sshd_config.backup`. В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована строка `PasswordAuthentication yes`, иначе она имеет приоритет перед 99-hardening.conf.

SSH использует 2222/tcp. Вход root и парольный вход отключены; keyboard-interactive также отключён. Разрешён только devops, MaxAuthTries=3. Сокетная активация ssh.socket отключена; включена ssh.service.

`ClientAliveInterval` и `ClientAliveCountMax` контролируют доступность клиента, а не время бездействия пользователя.

## 6. Правила межсетевого экрана

UFW активен. По умолчанию входящие запрещены, исходящие разрешены. Для 2222/tcp применяется LIMIT, для 80/tcp и 443/tcp — ALLOW. Правила действуют для IPv4 и IPv6. Уровень журнала medium.

Правило LIMIT установлено поверх ALLOW командой `sudo ufw limit 2222/tcp comment 'SSH rate-limited'`; UFW сообщил Rule updated. Это позволило обойтись без промежутка без разрешающего правила.

## 7. Снимки состояния

| Имя | Состояние |
| --- | --- |
| 01-clean-install | Ubuntu, обновления, две сети, исходный student |
| 02-keys-configured | Пользователь devops, ключ, SSH ещё на порту 22 |
| 03-ssh-hardened | SSH на 2222, пароли и root запрещены; UFW ещё не настроен |

Снимки созданы на выключенной машине командой `qemu-img snapshot -c ИМЯ ubuntu.qcow2`. Состояние оперативной памяти в них не включено. Настройки UTM и EFI сохранены рядом: `/Users/isaevisa/Virtual Machines/devops-checkpoints/ИМЯ/`. Это снимки диска QEMU, не снимки VirtualBox.

Перед восстановлением выключить Ubuntu, дождаться статуса stopped и закрыть UTM. Сохранить актуальное состояние отдельной копией. Затем:

```bash
qemu-img snapshot -a ИМЯ "/Users/isaevisa/Virtual Machines/devops-vm.utm/Data/ubuntu.qcow2"
cp "/Users/isaevisa/Virtual Machines/devops-checkpoints/ИМЯ/config.plist" "/Users/isaevisa/Virtual Machines/devops-vm.utm/config.plist"
cp "/Users/isaevisa/Virtual Machines/devops-checkpoints/ИМЯ/efi_vars.fd" "/Users/isaevisa/Virtual Machines/devops-vm.utm/Data/efi_vars.fd"
```

После этого открыть машину в UTM. Настройки Mac (`~/.ssh/config`, `/etc/hosts`) при откате VM не меняются. Для снимка 01 нужен student, для снимков 01 и 02 гостевой SSH-порт равен 22, проброс на Mac остаётся 2222.

## Восстановление настройки после 01-clean-install

Команды на Ubuntu, если явно не написано «Mac». Файлы репозитория должны быть заранее доступны.

1. С Mac: `ssh -i /путь/к/bootstrap -p 2222 student@127.0.0.1` либо вход student из консоли UTM. Для обычного ручного входа можно использовать пароль student. Перед первым подключением сверить отпечаток на консоли: `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
2. `sudo adduser devops`, задать пароль, затем `sudo usermod -aG sudo devops`.
3. С Mac: `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`. Если ключа нет, сначала `ssh-keygen -t ed25519 -f ~/.ssh/devops_vm -C devops-vm-key`.
4. Проверить `ssh devops` и на сервере `stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys`. Не продолжать, пока вход по ключу не заработает.
5. С Mac передать настройки: `scp -P 2222 configs/99-hardening.conf devops@127.0.0.1:~/99-hardening.conf`.
6. На сервере: `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup`; `sudo cp ~/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf`.
7. `sudo sed -i 's/^PasswordAuthentication yes/# PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf`.
8. `sudo sshd -t`; `sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'`.
9. Сохранить текущую SSH-сессию. Выполнить `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh.service`.
10. В отдельном терминале Mac проверить `ssh -i ~/.ssh/devops_vm -p 2222 devops@192.168.56.101`. Этот путь работает напрямую и не зависит от NAT.
11. В UTM изменить гостевой порт проброса с 22 на 2222. Если нужна остановка VM, сначала убедиться в работе прямого SSH. После запуска проверить `ssh devops`.
12. На сервере выполнить команды ниже. Вторую SSH-сессию держать открытой до окончания проверки.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
sudo ufw status verbose
hostname -f
```

13. С Mac проверить `ssh devops.local`. Передать скрипт аудита на сервер и выполнить `bash scripts/audit.sh; echo $?`. Ожидаются шесть успешных проверок и код 0.

Эта последовательность записана по выполненным действиям. В ПР № 5 полный откат с секундомером не проводился. При подготовке ПР № 6 (16.10.2026) выполнен откат на 01-clean-install и повторная настройка по этой последовательности. Команды были заранее собраны в сценарий: от начала отката до итогового входа по SSH прошло 42,9 с; аудит показал 6 OK, exit=0. Это замер автоматизированного выполнения, а не ручного ввода команд. Текущее состояние перед откатом сохранено в before-practice6.

## Проверка аудита

На рабочей конфигурации: 6 OK, exit=0. Для отрицательной проверки в файле SSH временно установлено MaxAuthTries 10: 5 OK, 1 FAIL, exit=1. Затем исходный файл восстановлен, `sshd -t` прошёл, повторный аудит вернул 0. Служба при временном изменении не перезапускалась: скрипт проверяет конфигурацию на диске через sshd -T.

Аудит не заменяет отдельную проверку слушающего сокета, нового соединения, правил LIMIT и доступности DNS. Эти проверки выполнены отдельно.


## 8. Веб-сервер

Установлены nginx 1.24.0 из репозитория Ubuntu и rsync. Сайт доступен с Mac по `https://devops.local` через Host-only 192.168.56.101. Запись в `/etc/hosts` сделана на Mac; в Ubuntu для локальных проверок использован localhost с Host: devops.local.

```bash
sudo apt update
sudo apt install -y nginx rsync
sudo install -d -m 755 -o devops -g devops /var/www/devops-site
```

Каталог `/var/www/devops-site` принадлежит devops:devops (755), HTML-файлы — тому же пользователю (644). www-data читает файлы, но не может их менять. Конфигурация — `/etc/nginx/sites-available/devops-site`; в sites-enabled находится ссылка с тем же именем. Ссылка default удалена; исходный файл default сохранён.

Сертификат `/etc/ssl/certs/devops.crt` имеет владельца root:root и права 644; закрытый ключ `/etc/ssl/private/devops.key` — root:root, 600. Создание:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Срок: 16.10.2026 18:03:04 UTC — 16.10.2027 18:03:04 UTC. Повторный выпуск создаст другой сертификат: его открытую часть потребуется заново скопировать клиенту через проверенный SSH. Закрытый ключ остаётся на Ubuntu.

Конфигурация на этапе ПР № 6 (в актуальном `configs/devops-site.conf` также есть /app/ из раздела 9):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    access_log /var/log/nginx/devops-site.access.log;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;
    location / { try_files $uri $uri/ =404; }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Установка конфигурации после её передачи на VM:

```bash
sudo cp devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

HSTS в учебной конфигурации не включён. Журнал HTTP-редиректов записывается в тот же devops-site.access.log, что и HTTPS, чтобы распределение кодов учитывало 301.

С Mac сертификат получен по проверенному SSH. Проверки без отключения доверия:

```bash
ssh devops 'cat /etc/ssl/certs/devops.crt' > ~/devops.crt
curl -I http://devops.local
curl --cacert ~/devops.crt -I https://devops.local
openssl x509 -in ~/devops.crt -noout -dates -ext subjectAltName
```

Снимок `04-nginx-https` создан на выключенной VM. Вместе с диском сохранены config.plist и EFI в каталоге checkpoints, как описано выше.

### Доставка с Mac

Встроенный rsync 2.6.9 не принял `--chmod=D755,F644`, поэтому установлен rsync 3.5.0 через Homebrew (`brew install rsync`). В PATH первым должен быть `/opt/homebrew/bin`. На Mac используется Bash 3.2; скрипт совместим с ним.

```bash
scripts/deploy.sh --dry-run
scripts/deploy.sh
```

Запуск допустим из любого каталога репозитория. Нужны работающий `ssh devops`, rsync 3 и `~/devops.crt`. Скрипт проверяет index.html и чистое состояние Git, выполняет один rsync через SSH, затем curl с проверкой сертификата. SSH использует BatchMode=yes и ConnectTimeout=5. Для HTTPS connect-timeout=10, max-time=20: разрешение локального имени на этом Mac занимало около 5 секунд. Успех — 0 и короткий хеш коммита; ошибка — 1. При dry-run запрос HTTPS не выполняется.

Пять сценариев проверены: dry-run 0, доставленный коммит 0, незакоммиченный или staged файл 1, остановленный nginx 1, переименованный и закоммиченный index.html 1. После опытов главная страница и Nginx восстановлены.

Обычный rsync сравнивает размер и mtime. Он исправил выполненную в работе подмену, но не гарантирует обнаружение правки с сохранением размера и времени; для такой проверки нужен `--checksum`. Доставка в рабочий каталог не атомарна.

### Аудит и подготовка следующей практики

В scripts/audit.sh добавлены четыре проверки: активность nginx, nginx -t, остаток срока сертификата не менее 30 дней, отсутствие world-writable объектов и права ключа 600. Отрицательные проверки: порог срока 400 дней и права index.html 666. После восстановления ожидаются 10 OK и код 0.

Docker Engine установлен из официального apt-репозитория Docker, пользователь devops добавлен в docker; после нового входа выполнен `docker run --rm hello-world`. Членство в docker фактически даёт полномочия root через демон; это учебная VM. В ПР № 7 добавлены контейнеры и проверка взаимодействия Docker с UFW; актуальные настройки приведены в разделе 9.


## 9. Контейнеризация

### Docker и доступ

Docker Engine 29.9.1 и Compose v5.6.0 установлены из официального apt-репозитория Docker на Ubuntu 24.04 ARM64. В группе docker находится devops. После добавления в группу выполнен новый вход по SSH. Членство в docker даёт административные возможности через демон root.

Для установки на восстановленной Ubuntu (команды выполняются на VM):

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<'SOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: arm64
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker devops
```

Затем выйти и войти снова: `ssh devops`. Проверить `docker version`, `docker compose version`, `docker run --rm hello-world`. Команды apt устанавливают доступную версию; фактически проверенные версии указаны выше. Инструкция рассчитана на нашу Ubuntu noble ARM64.

### Проект и переменные

Исходники находятся на Mac в `/Users/isaevisa/IdeaProjects/devops-course-2026/app`, рабочая копия на VM — `/home/devops/app`. Из корня репозитория на Mac:

```bash
rsync -avz --delete --exclude=.env --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env app/ devops:app/
rsync -avz scripts/ devops:devops-course-2026/scripts/
rsync -avz configs/devops-site.conf devops:devops-site.conf
```

Исключение .env защищает файл на принимающей стороне от --delete. .gitignore исключает его из Git, .dockerignore — из контекста сборки. В репозитории хранится только `.env.example` с заменителем пароля.

Только при первом развёртывании на VM создать `.env` (если файл уже есть, его не заменять):

```bash
cd ~/app
umask 077
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
```

Файл `/home/devops/app/.env`, владелец devops:devops, права 600. DB_HOST=db; POSTGRES_DB=app; POSTGRES_USER=app. Пароль сгенерирован на VM. Содержимое .env не выводится в отчёт. env_file передаёт значения в окружение процессов, не копирует файл внутрь образа. При существующем томе смена POSTGRES_PASSWORD в файле сама по себе не меняет пароль в PostgreSQL.

### Запуск, сеть и данные

На VM:

```bash
cd ~/app
docker compose config --quiet
docker compose up -d --build --wait
docker compose ps
docker compose exec app id
docker compose exec app getent hosts db
curl --retry 5 --retry-all-errors --retry-delay 1 \
  -fsS http://127.0.0.1:5000/health
curl -fsS http://127.0.0.1:5000/
```

Compose создаёт app-app-1 и app-db-1, сеть app_backend и том app_db_data. Gunicorn запускается от app (UID 999), код принадлежит root и имеет права 644. db использует postgres:16-alpine и healthcheck pg_isready; app ждёт service_healthy. У приложения собственного healthcheck нет: /health отдельно проверяется curl. Обе службы используют restart: unless-stopped.

Публикация приложения: `127.0.0.1:5000:5000`. Порт 5432 PostgreSQL не публикуется; соединение app → db:5432 проходит внутри app_backend. EXPOSE 5000 сам по себе не открывает порт хоста. Проверки: `ss -tln`, `docker inspect -f '{{json .NetworkSettings.Ports}}' app-db-1`. У db ожидается {"5432/tcp":null}.

Том app_db_data подключён к /var/lib/postgresql/data. down сохраняет том: в опыте счётчик продолжился с 6 до 7. down -v удалил учебный том, после повторного up счётчик начался с 1. Перед этим сохранён SQL-файл ~/backups/practice7-before-volume-reset.sql на VM. Для обычного перезапуска down -v не используется.

### Nginx и HTTPS

В HTTPS-блок `/etc/nginx/sites-available/devops-site` добавлено:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Конечный слеш у proxy_pass заменяет /app/ на / при передаче запроса: /app/health становится /health. Остальной конфиг и статический сайт сохранены. Установить переданный конфиг: `sudo cp ~/devops-site.conf /etc/nginx/sites-available/devops-site`, затем `sudo nginx -t && sudo systemctl reload nginx`. Предыдущая версия сохранена в /var/backups/devops-site-practice6.conf.

На Mac:

```bash
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health
curl --cacert ~/devops.crt -I https://devops.local/
```

Ожидаются приветствие со счётчиком, ok и 200 OK. TLS завершается на Nginx; до Gunicorn используется HTTP на loopback. Статическая страница / остаётся доступной. Внешние подключения к 5000 и 5432 закрыты. Во временном опыте -p 5001:5000 был доступен с Mac, хотя UFW его не разрешал: Docker создал DNAT и правила пересылки. Тестовый контейнер удалён.

### Аудит и восстановление

`bash ~/devops-course-2026/scripts/audit.sh; echo $?` на VM: 14 OK, код 0. Новый раздел проверяет активность Docker, healthy у app-db-1, отсутствие внешних слушателей 5000/5432 и права .env 600. При временной публикации 5000:5000 получены 13 OK, 1 FAIL, код 1. Затем возвращён 127.0.0.1:5000:5000 и успешная проверка.

При 502 проверить compose ps, локальный /health, compose logs app, ss -tln, proxy_pass и /var/log/nginx/devops-site.error.log. При остановленном app в журнале было Connection refused. `docker compose start app` и ожидание успешного /health восстановили HTTPS. Завершение команды start ещё не гарантирует готовность Gunicorn.

Снимок 05-docker-compose создан после штатного выключения VM; вместе с QCOW2 сохранены config.plist и EFI в devops-checkpoints/05-docker-compose. Снимок 04-nginx-https сохранён. Порядок отката описан выше. После отката к 01-clean-install последовательно выполнить разделы настройки SSH/UFW, раздел 8 и раздел 9; создать новую .env, передать проект, запустить Compose и аудит. Снимок содержит учебную базу и .env, поэтому не предназначен для публичной загрузки.
