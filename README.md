# Практические работы по DevOps

Исаев Иса Абдулмуслимович, ЭФБО-02-24.

## Практическая работа 5

Ubuntu Server 24.04 ARM64 в UTM: SSH по ключу, sudo, UFW и локальное имя devops.local.

- [Конфигурация сервера и порядок восстановления](docs/server-setup.md)
- [Скрипт аудита](scripts/audit.sh)
- [Настройки SSH](configs/99-hardening.conf)

Запуск проверки на сервере:

```bash
bash scripts/audit.sh
echo $?
```

В версии ПР № 5 было шесть проверок; после ПР № 6 их десять, после ПР № 7 — четырнадцать. Код 0 означает, что все проверки пройдены. Код 1 означает ошибку проверки или невозможность получить данные. Для sudo нужен пароль пользователя Ubuntu.


## Практическая работа 6

Nginx, HTTPS с самоподписанным сертификатом, доставка сайта через rsync и проверка прав.

- [Сайт](site/index.html) и [страница 404](site/404.html)
- [Конфигурация Nginx](configs/devops-site.conf)
- [Скрипт деплоя](scripts/deploy.sh)
- [Настройка сервера](docs/server-setup.md#8-веб-сервер)

Сайт в локальной сети UTM: https://devops.local. Это не публичный адрес в интернете.

На Mac нужен rsync 3 (`brew install rsync`), доступ `ssh devops` и открытый сертификат в `~/devops.crt`. Закрытый ключ сервера в репозиторий не добавляется.

```bash
scripts/deploy.sh --dry-run
scripts/deploy.sh
```

Перед публикацией изменения должны быть закоммичены. Скрипт проверяет доступность сайта с проверкой сертификата; при ошибке возвращает 1. Подробности и результаты опытов записаны в документе настройки сервера.

## Практическая работа 7

Flask и PostgreSQL в Docker Compose, счётчик посещений и обратный прокси Nginx.

- [Приложение и Dockerfile](app/)
- [Docker Compose](app/docker-compose.yml)
- [Пример переменных без пароля](app/.env.example)
- [Настройка и восстановление](docs/server-setup.md#9-контейнеризация)

На VM в ~/app:

```bash
docker compose up -d --build --wait
docker compose ps
curl --retry 5 --retry-all-errors --retry-delay 1 -fsS http://127.0.0.1:5000/health
```

С Mac: https://devops.local/app/ — счётчик, https://devops.local/app/health — проверка Flask. Статический сайт на / сохранён.

Приложение опубликовано только на 127.0.0.1:5000, PostgreSQL доступен внутри сети Compose. Файл .env хранится только на VM с правами 600. При доставке app/ всегда используется --exclude=.env. docker compose down сохраняет данные, down -v удаляет том базы.

Аудит выполняется от devops на VM: bash ~/devops-course-2026/scripts/audit.sh; ожидаются 14 OK и код 0. Снимок UTM: 05-docker-compose.
