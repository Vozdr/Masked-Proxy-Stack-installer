events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=10s ipv6=off;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    upstream fake_site_backend {
        server fake-site:__FAKE_SITE_PORT__;
    }

    server {
        listen 443 ssl;
        server_name __CONTROL_DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__CONTROL_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__CONTROL_DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location = __CONTROL_PREFIX__/3x-ui {
            return 301 __CONTROL_PREFIX__/3x-ui/;
        }

        location __CONTROL_PREFIX__/3x-ui/ {
__BASIC_AUTH_NGINX_BLOCK__
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            set $xui_upstream http://3x-ui:2053;
            proxy_pass $xui_upstream;
        }

        location = __CONTROL_PREFIX__/telemt {
            return 301 __CONTROL_PREFIX__/telemt/;
        }

        location __CONTROL_PREFIX__/telemt/ {
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Prefix __CONTROL_PREFIX__/telemt;
            rewrite ^__CONTROL_PREFIX__/telemt/?(.*)$ /$1 break;
            proxy_pass http://telemt:8080;
        }

__PORTAINER_LOCATION__

        location / {
__CONTROL_FALLBACK_BLOCK__
        }
    }

    server {
        listen 8081;
        server_name __XUI_DOMAIN__;

        location / {
            return 301 https://__BASE_DOMAIN__;
        }
    }
}
