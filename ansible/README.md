# Практическая работа 11

Ansible на Mac настраивает Ubuntu в UTM. В роли `base` устанавливается Docker, в `ssh` — пользователь и ключ, в `nginx` — прокси, в `app` — контейнер из GHCR.

Для этой работы сделан клон `devops-ansible`. Он восстановлен из снимка `01-clean-install`. Старая машина `devops-vm` с работами 5–8 сохранена отдельно.

| Машина | Адрес | Вход с Mac | Сайт |
|---|---|---|---|
| devops-vm | 192.168.56.101 | `ssh devops` — порт Mac 2222 | `https://devops.local` |
| devops-ansible | 192.168.56.102 | `ssh devops-ansible` — порт Mac 2223 | `http://192.168.56.102` или `http://127.0.0.1:8081` |

Запускать машины можно кнопкой Play в UTM или командами на Mac:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl start devops-ansible
/Applications/UTM.app/Contents/MacOS/utmctl start devops-vm
```

У машин разные диски, UUID, MAC и адреса. Проброс `2223 → 22` относится к новой VM, `2222 → 2222` — к старой. Ansible использует прямое подключение к `192.168.56.102:22`. Смену порта SSH на новой VM не делал: в задании оставлен порт 22.

## Подготовка Mac

Для новой установки нужен Python 3.11–3.13. Из каталога `ansible`:

```bash
python3.13 -m venv .venv
source .venv/bin/activate
pip install ansible-core==2.18.12
brew install sshpass
export LC_ALL=en_US.UTF-8
ansible-galaxy collection install -r requirements.yml
```

Нужны ключи `~/.ssh/devops_vm` и `~/.ssh/devops_vm.pub`. Закрытый ключ в репозиторий не входит. На этом Mac окружение уже подготовлено: достаточно `source .venv/bin/activate` и `export LC_ALL=en_US.UTF-8`. Переустановка для каждого запуска не нужна.

## Первый запуск

Эти команды нужны для чистой VM с пользователем `student`. На уже настроенной машине сразу используется следующий раздел.

```bash
ansible-inventory -i inventory/bootstrap.ini --graph
ansible-playbook -i inventory/bootstrap.ini site.yml --syntax-check
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
```

Первый пароль нужен SSH, второй — sudo. Плейбук создаёт `devops`, устанавливает открытый ключ, разрешает sudo без пароля и отключает вход по паролю. В `prod.ini` уже указан пользователь `devops`.

## Повторный запуск и проверка

```bash
ansible all -m ping
ansible-playbook site.yml
ansible-playbook verify.yml
curl --fail http://192.168.56.102/health
```

Если ничего не менять, у `site.yml` и `verify.yml` будет `changed=0`. `verify.yml` только проверяет SSH, состояние контейнера и `/health`.

```bash
ssh devops-ansible
docker ps
sudo ss -tlnp
sudo ufw status verbose
```

Приложение слушает порт 5000 внутри контейнера. На VM этот порт опубликован только на `127.0.0.1`. Nginx принимает HTTP на 80 и передаёт запрос приложению.

## Показ восстановления

На новой VM:

```bash
docker rm -f devops-ci-app
sudo sed -i 's/127.0.0.1:5000/127.0.0.1:5001/' /etc/nginx/sites-available/devops-ci-app
sudo nginx -t
sudo systemctl reload nginx
exit
```

На Mac, из каталога `ansible`:

```bash
curl -i http://192.168.56.102/health
ansible-playbook site.yml
curl --fail http://192.168.56.102/health
ansible-playbook site.yml
```

Сначала будет 502. Плейбук вернёт порт 5000 и запустит контейнер, после чего `/health` ответит 200. Следующий запуск снова ничего не изменит.

Образ и полный SHA хранятся в `group_vars/all.yml`. Загрузка образа выполняется раньше изменения контейнера. Поэтому ошибка загрузки несуществующего тега не удаляет работающую версию.
