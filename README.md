# Masked Proxy Stack installer

Installer for deploying the full 3x-ui+telemt masked stack on a new Debian-like
server.

## What It Deploys

The stack requires a real domain. The domain can be any level, for example
`site.com`, `proxy.site.com` or `edge.proxy.site.com`, but its DNS record must
point to the server where the stack is installed.

The stack includes:

- `edge` - public nginx entry point on ports `80` and `443`;
- `3x-ui` - management panel and VLESS/TLS inbound;
- `telemt` - Telegram MTProxy service;
- `telemt-admin` - web interface for managing TeleMT;
- `fake-site` - fallback site for unmatched or incorrect requests;
- `fake-gate` and `panel-gate` - internal nginx gateways for routing fallback and control paths;
- `cert-renewer` - certificate renewal container;
- optional `Portainer CE` - stack management UI when `--portainer` is used.

Control panels are served from reserved paths on the base domain by default:

- `https://<base-domain>/<secret-path>/3x-ui/`
- `https://<base-domain>/<secret-path>/telemt/`
- `https://<base-domain>/<secret-path>/portainer/` when `--portainer` is used

All other paths on the base domain are passed to the fake site unchanged.

The hidden control path does not need to include the base domain. If the base
domain is entered anyway, the installer strips it and keeps only the path. It
can be entered as `path`, `/path/`, `<base-domain>/path`,
`https://<base-domain>/path`, `sub.<base-domain>` or `sub.<base-domain>/path`.
If a separate control subdomain is used, panels are served from that subdomain
and all other paths on it redirect to the base domain.

## Usage

Copy this folder to a server and run:

```bash
chmod +x install.sh
sudo ./install.sh
```

The script asks for:

- install directory, default `/data`;
- base domain, for example `site.com`;
- 3x-ui domain or subdomain, default `apiv1.<base-domain>`;
- TeleMT domain or subdomain, default `apiv2.<base-domain>`;
- Let's Encrypt email, default `admin@<base-domain>`;
- optional admin username/password;
- optional hidden control path or control host/path;
- optional fake-site Docker image;
- timezone in IANA format, for example `Europe/Moscow`, default `UTC`.

If a custom fake-site image is provided, the script asks for the internal HTTP
port of that container. If no image is provided, the built-in API stub is used
and the port is fixed to `8080`.

Answers are saved to `.install-answers.env` next to `install.sh` and reused as
defaults on the next run. The file contains generated credentials, so keep it
private.

After all questions are answered, the installer checks DNS records for all
required domains. If any domain does not resolve to the server public IPv4, the
installer stops before requesting certificates. Fix DNS and run it again.

If an existing stack is detected in the install directory or known containers
already exist, the installer asks whether to reinstall. When backup is enabled,
it creates `DATA_DIR/backups/reinstall-<timestamp>.tar.gz`, removes known stack
containers and generated stack directories, then deploys from scratch.

## Command-Line Options

Any option can be provided in interactive mode. In that case the installer still
asks the question, but uses the option value as the default. Press Enter to keep
it.

Use `--silent` for non-interactive installation. In silent mode the base domain
must be provided with `--base-domain`; all other values use defaults or provided
options.

```bash
sudo ./install.sh --base-domain site.com --silent
sudo ./install.sh --base-domain site.com --3x-domain gate --telemt-domain door --dir /opt/masked
sudo ./install.sh --base-domain site.com --admin-login admin --admin-pass 'change-me' --secret-path panel
sudo ./install.sh --base-domain site.com --tz Europe/Moscow --portainer
sudo ./install.sh --base-domain site.com --silent --reinstall --no-backup
```

Available options:

| Option | Default | Example | Description |
| --- | --- | --- | --- |
| `--silent` | `false` | `--silent` | Run non-interactively. Requires `--base-domain`. |
| `--dir PATH` | `/data` | `--dir /opt/masked` | Install directory. |
| `--base-domain DOMAIN` | none | `--base-domain site.com` | Base fake-site domain. Required in `--silent` mode. |
| `--3x-domain DOMAIN_OR_SUBDOMAIN` | `apiv1.<base-domain>` | `--3x-domain gate` | 3x-ui/VLESS domain or subdomain. |
| `--telemt-domain DOMAIN_OR_SUBDOMAIN` | `apiv2.<base-domain>` | `--telemt-domain door` | TeleMT domain or subdomain. |
| `--le-email EMAIL` | `admin@<base-domain>` | `--le-email admin@site.com` | Let's Encrypt email. |
| `--admin-login USER` | generated | `--admin-login admin` | Admin username for management interfaces. |
| `--admin-pass PASS` | generated | `--admin-pass 'change-me'` | Admin password for management interfaces. |
| `--secret-path PATH` | generated | `--secret-path panel` | Hidden control path or control host/path. |
| `--fake-site-image IMAGE` | built-in API stub | `--fake-site-image nginx:alpine` | Custom fake-site Docker image. |
| `--fake-site-port PORT` | `8080` | `--fake-site-port 3000` | Internal HTTP port for the custom fake-site image. |
| `--tz TIMEZONE` | `UTC` | `--tz Europe/Moscow` | IANA timezone. |
| `--portainer` | `false` | `--portainer` | Install Portainer CE and deploy the generated compose as a Portainer stack. |
| `--reinstall` | `false` | `--reinstall` | Allow reinstall when an existing stack is detected. Required for reinstall in `--silent` mode. |
| `--no-backup` | backup enabled | `--no-backup` | Skip backup before reinstall. |
| `-h`, `--help` | none | `--help` | Show help. |

---

# Установщик Masked Proxy Stack

Установщик для развёртывания полной маскировочной сборки 3x-ui+telemt на новом
Debian-like сервере.

## Что Разворачивается

Сборке обязательно нужен настоящий домен. Домен может быть любого уровня,
например `site.com`, `proxy.site.com` или `edge.proxy.site.com`, но его DNS-запись
обязательно должна указывать на сервер, где устанавливается сборка.

Состав сборки:

- `edge` - публичная nginx-точка входа на портах `80` и `443`;
- `3x-ui` - панель управления и VLESS/TLS inbound;
- `telemt` - Telegram MTProxy сервис;
- `telemt-admin` - веб-интерфейс для управления TeleMT;
- `fake-site` - fallback-сайт для неподходящих или неправильных запросов;
- `fake-gate` и `panel-gate` - внутренние nginx-gateway для fallback и скрытых путей управления;
- `cert-renewer` - контейнер продления сертификатов;
- опционально `Portainer CE` - интерфейс управления stack при запуске с `--portainer`.

По умолчанию панели управления открываются на основном домене по зарезервированным путям:

- `https://<base-domain>/<secret-path>/3x-ui/`
- `https://<base-domain>/<secret-path>/telemt/`
- `https://<base-domain>/<secret-path>/portainer/` при запуске с `--portainer`

Все остальные пути основного домена передаются в fake-site без изменений.

В скрытом пути управления не нужно указывать основной домен. Если его всё же
указать, установщик уберёт домен и оставит только путь. Значение можно ввести
как `path`, `/path/`, `<base-domain>/path`, `https://<base-domain>/path`,
`sub.<base-domain>` или `sub.<base-domain>/path`. Если указан отдельный поддомен
управления, панели открываются на нём, а все остальные пути этого поддомена
перенаправляются на основной домен.

## Запуск

Скопируйте эту папку на сервер и выполните:

```bash
chmod +x install.sh
sudo ./install.sh
```

Скрипт спросит:

- папку установки, по умолчанию `/data`;
- основной домен, например `site.com`;
- домен или поддомен 3x-ui, по умолчанию `apiv1.<base-domain>`;
- домен или поддомен TeleMT, по умолчанию `apiv2.<base-domain>`;
- email для Let's Encrypt, по умолчанию `admin@<base-domain>`;
- необязательные admin username/password;
- необязательный скрытый путь управления или домен/путь управления;
- необязательный Docker image для fake-site;
- timezone в формате IANA, например `Europe/Moscow`, по умолчанию `UTC`.

Если указан кастомный fake-site image, скрипт дополнительно спросит внутренний
HTTP-порт контейнера. Если image не указан, используется встроенный API stub с
портом `8080`.

Ответы сохраняются в `.install-answers.env` рядом с `install.sh` и используются
как значения по умолчанию при следующем запуске. В файле есть сгенерированные
доступы, поэтому его нужно хранить приватно.

После всех вопросов установщик проверяет DNS-записи всех нужных доменов. Если
хотя бы один домен не указывает на публичный IPv4 сервера, установка
останавливается до запроса сертификатов. После исправления DNS достаточно
запустить скрипт снова.

Если в папке установки уже есть файлы сборки или существуют известные контейнеры,
установщик спросит, нужно ли переустановить сборку. Если включить backup, он
создаст `DATA_DIR/backups/reinstall-<timestamp>.tar.gz`, удалит известные
контейнеры и сгенерированные папки сборки, затем развернёт всё заново.

## Ключи Запуска

Любой ключ можно указать и в интерактивном режиме. Тогда скрипт всё равно задаст
вопрос, но подставит значение из ключа как значение по умолчанию. Чтобы принять
его, достаточно нажать Enter.

Для полностью неинтерактивной установки используйте `--silent`. В silent-режиме
обязательно нужно указать `--base-domain`; остальные значения будут взяты по
умолчанию или из переданных ключей.

```bash
sudo ./install.sh --base-domain site.com --silent
sudo ./install.sh --base-domain site.com --3x-domain gate --telemt-domain door --dir /opt/masked
sudo ./install.sh --base-domain site.com --admin-login admin --admin-pass 'change-me' --secret-path panel
sudo ./install.sh --base-domain site.com --tz Europe/Moscow --portainer
sudo ./install.sh --base-domain site.com --silent --reinstall --no-backup
```

Доступные ключи:

| Ключ | Значение по умолчанию | Пример | Описание |
| --- | --- | --- | --- |
| `--silent` | `false` | `--silent` | Запуск без вопросов. Требует `--base-domain`. |
| `--dir PATH` | `/data` | `--dir /opt/masked` | Папка установки. |
| `--base-domain DOMAIN` | нет | `--base-domain site.com` | Основной домен fake-site. Обязателен в `--silent` режиме. |
| `--3x-domain DOMAIN_OR_SUBDOMAIN` | `apiv1.<base-domain>` | `--3x-domain gate` | Домен или поддомен 3x-ui/VLESS. |
| `--telemt-domain DOMAIN_OR_SUBDOMAIN` | `apiv2.<base-domain>` | `--telemt-domain door` | Домен или поддомен TeleMT. |
| `--le-email EMAIL` | `admin@<base-domain>` | `--le-email admin@site.com` | Email Let's Encrypt. |
| `--admin-login USER` | генерируется | `--admin-login admin` | Логин администратора для интерфейсов управления. |
| `--admin-pass PASS` | генерируется | `--admin-pass 'change-me'` | Пароль администратора для интерфейсов управления. |
| `--secret-path PATH` | генерируется | `--secret-path panel` | Скрытый путь управления или домен/путь управления. |
| `--fake-site-image IMAGE` | встроенный API stub | `--fake-site-image nginx:alpine` | Кастомный Docker image fake-site. |
| `--fake-site-port PORT` | `8080` | `--fake-site-port 3000` | Внутренний HTTP-порт кастомного fake-site image. |
| `--tz TIMEZONE` | `UTC` | `--tz Europe/Moscow` | Timezone в формате IANA. |
| `--portainer` | `false` | `--portainer` | Поставить Portainer CE и развернуть сгенерированный compose как stack. |
| `--reinstall` | `false` | `--reinstall` | Разрешить переустановку, если найдена существующая сборка. Обязателен для переустановки в `--silent` режиме. |
| `--no-backup` | backup включён | `--no-backup` | Не делать backup перед переустановкой. |
| `-h`, `--help` | нет | `--help` | Показать справку. |
