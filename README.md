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
```

Available options:

- `--silent` - run non-interactively;
- `--dir PATH` - install directory, default `/data`;
- `--base-domain DOMAIN` - base fake-site domain, for example `site.com`;
- `--3x-domain DOMAIN_OR_SUBDOMAIN` - 3x-ui/VLESS domain or subdomain;
- `--telemt-domain DOMAIN_OR_SUBDOMAIN` - TeleMT domain or subdomain;
- `--le-email EMAIL` - Let's Encrypt email, default `admin@<base-domain>`;
- `--admin-login USER` - admin username;
- `--admin-pass PASS` - admin password;
- `--secret-path PATH` - hidden control path or control host/path;
- `--fake-site-image IMAGE` - custom fake-site Docker image;
- `--fake-site-port PORT` - internal HTTP port for the custom fake-site image;
- `--tz TIMEZONE` - IANA timezone, for example `Europe/Moscow`, default `UTC`;
- `--portainer` - install Portainer CE and deploy the generated compose as a Portainer stack;
- `-h`, `--help` - show help.

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
```

Доступные ключи:

- `--silent` - запуск без вопросов;
- `--dir PATH` - папка установки, по умолчанию `/data`;
- `--base-domain DOMAIN` - основной домен fake-site, например `site.com`;
- `--3x-domain DOMAIN_OR_SUBDOMAIN` - домен или поддомен 3x-ui/VLESS;
- `--telemt-domain DOMAIN_OR_SUBDOMAIN` - домен или поддомен TeleMT;
- `--le-email EMAIL` - email Let's Encrypt, по умолчанию `admin@<base-domain>`;
- `--admin-login USER` - логин администратора;
- `--admin-pass PASS` - пароль администратора;
- `--secret-path PATH` - скрытый путь управления или домен/путь управления;
- `--fake-site-image IMAGE` - кастомный Docker image fake-site;
- `--fake-site-port PORT` - внутренний HTTP-порт кастомного fake-site image;
- `--tz TIMEZONE` - timezone в формате IANA, например `Europe/Moscow`, по умолчанию `UTC`;
- `--portainer` - поставить Portainer CE и развернуть сгенерированный compose как stack;
- `-h`, `--help` - показать справку.
