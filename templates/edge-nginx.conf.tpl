worker_processes auto;

events {
    worker_connections 4096;
}

stream {
    resolver 127.0.0.11 valid=10s ipv6=off;

    map $ssl_preread_server_name $tls_upstream {
        __XUI_DOMAIN__ 3x-ui:443;
        __TELEMT_DOMAIN__ telemt:443;
        __BASE_DOMAIN__ __BASE_TLS_UPSTREAM__;
__CONTROL_DOMAIN_MAP__
        "" telemt:443;
        default fake-gate:443;
    }

    server {
        listen 443;
        proxy_pass $tls_upstream;
        ssl_preread on;
        proxy_connect_timeout 10s;
        proxy_timeout 1h;
    }
}

http {
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    server {
        listen 80;
        server_name __BASE_DOMAIN__ __CONTROL_DOMAIN__ __XUI_DOMAIN__ __TELEMT_DOMAIN__;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://__BASE_DOMAIN__$request_uri;
        }
    }
}
