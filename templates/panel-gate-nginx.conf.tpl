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
        server_name __BASE_DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__BASE_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__BASE_DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location = /__SECRET_PATH__/3x-ui {
            return 301 /__SECRET_PATH__/3x-ui/;
        }

        location /__SECRET_PATH__/3x-ui/ {
            auth_basic "Control";
            auth_basic_user_file /etc/nginx/htpasswd;
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

        location = /__SECRET_PATH__/telemt {
            return 301 /__SECRET_PATH__/telemt/;
        }

        location /__SECRET_PATH__/telemt/ {
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Prefix /__SECRET_PATH__/telemt;
            rewrite ^/__SECRET_PATH__/telemt/?(.*)$ /$1 break;
            proxy_pass http://telemt-admin:8080;
        }

__PORTAINER_LOCATION__

        location / {
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_pass http://fake_site_backend;
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
