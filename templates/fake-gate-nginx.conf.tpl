events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=10s ipv6=off;
    access_log off;
    error_log /var/log/nginx/error.log warn;

    upstream fake_site_backend {
        server fake-site:__FAKE_SITE_PORT__;
    }

    server {
        listen 443 ssl;
        server_name __BASE_DOMAIN__ _;

        ssl_certificate /etc/letsencrypt/live/__BASE_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__BASE_DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

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
        listen 443 ssl;
        server_name __XUI_DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__XUI_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__XUI_DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

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
        listen 443 ssl;
        server_name __TELEMT_DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__TELEMT_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__TELEMT_DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_pass http://fake_site_backend;
        }
    }
}
