server {
    listen 443 ssl;
    server_name app.wasypro.com;

    ssl_certificate     /etc/letsencrypt/live/app.wasypro.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.wasypro.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # ===== ADMINER =====
    location /adminer/ {
        alias /var/www/adminer/;
        index index.php;
        location ~ \.php$ {
            fastcgi_pass unix:/run/php/php8.1-fpm.sock;
            fastcgi_param SCRIPT_FILENAME /var/www/adminer/index.php;
            include fastcgi_params;
        }
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3011;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://127.0.0.1:5175;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    if ($host = app.wasypro.com) {
        return 301 https://$host$request_uri;
    }
    listen 80;
    server_name app.wasypro.com www.app.wasypro.com;
    return 404;
}
