Masked proxy stack
Generated: __GENERATED_AT__

Domains:
  Fake site:      https://__BASE_DOMAIN__/
  3x-ui/VLESS:   https://__XUI_DOMAIN__/
  TeleMT:        https://__TELEMT_DOMAIN__/

Control:
  3x-ui panel:   https://__BASE_DOMAIN__/__SECRET_PATH__/3x-ui/
  TeleMT Admin:  https://__BASE_DOMAIN__/__SECRET_PATH__/telemt/
  Portainer:     https://__BASE_DOMAIN__/__SECRET_PATH__/portainer/  (only when installed with --portainer)

Credentials:
  Admin user:    __ADMIN_USER__
  Admin pass:    __ADMIN_PASS__
  Secret path:   __SECRET_PATH__

Fake site:
  Image:         __FAKE_SITE_IMAGE__
  Internal port: __FAKE_SITE_PORT__

Paths:
  Install dir:   __DATA_DIR__
  Compose:       __DATA_DIR__/compose/docker-compose.yml
  Env:           __DATA_DIR__/compose/.env
  Edge nginx:    __DATA_DIR__/edge/nginx.conf
  Panel nginx:   __DATA_DIR__/panel-gate/nginx.conf
  Fake gate:     __DATA_DIR__/fake-gate/nginx.conf
  TeleMT config: __DATA_DIR__/telemt/config/config.toml
  3x-ui DB:      __DATA_DIR__/3x-ui/db/x-ui.db
  Certificates:  __DATA_DIR__/certs

Commands:
  cd __DATA_DIR__/compose
  __COMPOSE_CMD__ ps
  __COMPOSE_CMD__ logs -f edge
  __COMPOSE_CMD__ logs -f 3x-ui
  __COMPOSE_CMD__ logs -f telemt
  __COMPOSE_CMD__ restart edge
  __DATA_DIR__/scripts/renew-certs.sh
  __DATA_DIR__/scripts/post-configure.sh --dir __DATA_DIR__

---

Маскировочная связка
Создано: __GENERATED_AT__

Домены:
  Fake site:      https://__BASE_DOMAIN__/
  3x-ui/VLESS:   https://__XUI_DOMAIN__/
  TeleMT:        https://__TELEMT_DOMAIN__/

Управление:
  Панель 3x-ui:  https://__BASE_DOMAIN__/__SECRET_PATH__/3x-ui/
  TeleMT Admin:  https://__BASE_DOMAIN__/__SECRET_PATH__/telemt/
  Portainer:     https://__BASE_DOMAIN__/__SECRET_PATH__/portainer/  (только при установке с --portainer)

Доступы:
  Admin user:    __ADMIN_USER__
  Admin pass:    __ADMIN_PASS__
  Secret path:   __SECRET_PATH__

Fake site:
  Image:         __FAKE_SITE_IMAGE__
  Внутр. порт:   __FAKE_SITE_PORT__

Пути:
  Папка:         __DATA_DIR__
  Compose:       __DATA_DIR__/compose/docker-compose.yml
  Env:           __DATA_DIR__/compose/.env
  Edge nginx:    __DATA_DIR__/edge/nginx.conf
  Panel nginx:   __DATA_DIR__/panel-gate/nginx.conf
  Fake gate:     __DATA_DIR__/fake-gate/nginx.conf
  TeleMT config: __DATA_DIR__/telemt/config/config.toml
  3x-ui DB:      __DATA_DIR__/3x-ui/db/x-ui.db
  Сертификаты:   __DATA_DIR__/certs

Команды:
  cd __DATA_DIR__/compose
  __COMPOSE_CMD__ ps
  __COMPOSE_CMD__ logs -f edge
  __COMPOSE_CMD__ logs -f 3x-ui
  __COMPOSE_CMD__ logs -f telemt
  __COMPOSE_CMD__ restart edge
  __DATA_DIR__/scripts/renew-certs.sh
  __DATA_DIR__/scripts/post-configure.sh --dir __DATA_DIR__
