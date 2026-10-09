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

Эта последовательность записана по выполненным действиям. Полный откат и восстановление с секундомером в данной работе не проводились.

## Проверка аудита

На рабочей конфигурации: 6 OK, exit=0. Для отрицательной проверки в файле SSH временно установлено MaxAuthTries 10: 5 OK, 1 FAIL, exit=1. Затем исходный файл восстановлен, `sshd -t` прошёл, повторный аудит вернул 0. Служба при временном изменении не перезапускалась: скрипт проверяет конфигурацию на диске через sshd -T.

Аудит не заменяет отдельную проверку слушающего сокета, нового соединения, правил LIMIT и доступности DNS. Эти проверки выполнены отдельно.
