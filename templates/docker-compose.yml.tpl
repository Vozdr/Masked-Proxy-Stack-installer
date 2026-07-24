version: "3.8"

services:
  edge:
    image: nginx:1.27-alpine
    container_name: masked-edge
    restart: unless-stopped
    environment:
      TZ: "__TZ__"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - __DATA_DIR__/edge/nginx.conf:/etc/nginx/nginx.conf:ro
      - __DATA_DIR__/certbot/www:/var/www/certbot:ro
    networks:
      - masked_net

  fake-gate:
    image: nginx:1.27-alpine
    container_name: masked-fake-gate
    restart: unless-stopped
    environment:
      TZ: "__TZ__"
    expose:
      - "443"
    volumes:
      - __DATA_DIR__/fake-gate/nginx.conf:/etc/nginx/nginx.conf:ro
      - __DATA_DIR__/certs:/etc/letsencrypt:ro
    depends_on:
      - fake-site
    networks:
      - masked_net

__FAKE_SITE_SERVICE__

  panel-gate:
    image: nginx:1.27-alpine
    container_name: masked-panel-gate
    restart: unless-stopped
    environment:
      TZ: "__TZ__"
    expose:
      - "8081"
      - "443"
    volumes:
      - __DATA_DIR__/panel-gate/nginx.conf:/etc/nginx/nginx.conf:ro
__BASIC_AUTH_VOLUME__
      - __DATA_DIR__/certs:/etc/letsencrypt:ro
    depends_on:
      - 3x-ui
      - telemt-admin
    networks:
      - masked_net

  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3xui_app
    hostname: 3x-ui
    restart: unless-stopped
    tty: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      TZ: "__TZ__"
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      XUI_INIT_WEB_BASE_PATH: __CONTROL_PREFIX__/3x-ui/
    expose:
      - "443"
      - "2053"
    ports:
      - "127.0.0.1:2053:2053"
    volumes:
      - __DATA_DIR__/3x-ui/db:/etc/x-ui:rw
      - __DATA_DIR__/certs:/root/cert:ro
    networks:
      - masked_net

  telemt:
    image: ghcr.io/telemt/telemt:latest
    container_name: telemt
    restart: unless-stopped
    working_dir: /run/telemt
    command:
      - /etc/telemt/config.toml
    cap_add:
      - NET_BIND_SERVICE
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    environment:
      TZ: "__TZ__"
      RUST_LOG: info
    expose:
      - "443"
      - "9090"
      - "9091"
    volumes:
      - __DATA_DIR__/telemt/config:/etc/telemt:rw
      - __DATA_DIR__/telemt/runtime:/run/telemt:rw
    networks:
      - masked_net

  telemt-admin:
    image: w03zd8rc/telemt-admin:latest
    container_name: masked-telemt-admin
    restart: unless-stopped
    depends_on:
      - telemt
    network_mode: "container:telemt"
    environment:
      ENABLE_WEB_AUTH: "yes"
      ENABLE_BASIC_AUTH: "__BASIC_AUTH_ENABLED__"
      WEB_ADMIN_USER: __ADMIN_USER__
      WEB_ADMIN_PASS: __ADMIN_PASS__
      BASIC_ADMIN_USER: __ADMIN_USER__
      BASIC_ADMIN_PASS: __ADMIN_PASS__
      SESSION_SECRET: __SESSION_SECRET__
      TELEMT_CONFIG: /data/telemt/config/config.toml
      TELEMT_BACKUP_DIR: /data/backups
      TELEMT_MAX_BACKUPS: "20"
      TELEMT_METRICS_URL: http://127.0.0.1:9090/metrics
      TELEMT_METRICS_LISTEN: 0.0.0.0:9090
      AUTO_FIX_METRICS_LISTEN: "yes"
      ENABLE_METRICS: "yes"
      DEFAULT_THEME: dark
      DEFAULT_LANG: en
      LOG_LEVEL: ERROR
      TZ: "__TZ__"
    volumes:
      - __DATA_DIR__/telemt/config:/data/telemt/config:rw
      - __DATA_DIR__/telemt-admin/backups:/data/backups:rw

  cert-renewer:
    image: docker:27-cli
    container_name: masked-cert-renewer
    restart: unless-stopped
    command:
      - /bin/sh
      - -c
      - "while true; do /renew-certs.sh || true; sleep 12h; done"
    environment:
      TZ: "__TZ__"
      DATA_DIR: __DATA_DIR__
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - __DATA_DIR__/scripts/renew-certs.sh:/renew-certs.sh:ro
    networks:
      - masked_net

networks:
  masked_net:
    name: masked_net
