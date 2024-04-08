#!/bin/bash

# Проверка наличия аргументов
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 [путь к YAML файлу]"
    exit 1
fi

YAML_FILE=$1

# Проверка существования файла
if [ ! -f "$YAML_FILE" ]; then
    echo "Файл $YAML_FILE не найден"
    exit 1
fi

# Получаем количество сайтов в файле
count=$(yq e '.websites | length' $YAML_FILE)

# Итерация по каждому сайту
for ((i=0; i<count; i++))
do
    DOMAIN=$(yq e ".websites[$i].domain" $YAML_FILE)
    PORT=$(yq e ".websites[$i].port" $YAML_FILE)
    MAIL=$(yq e ".websites[$i].mail" $YAML_FILE)

    echo "Сайт: $DOMAIN"
    echo "Порт: $PORT"
    echo "Email: $MAIL"
    echo "--------"
    
    # Проверка, был ли сайт уже добавлен
    if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
        echo "Сайт для $DOMAIN уже настроен."
        continue
    fi

    WEB_ROOT="/apps/web/$DOMAIN"
    CONFIG="/etc/nginx/sites-available/$DOMAIN"

    if [ ! -d "$WEB_ROOT" ]; then
        echo "Создание директории $WEB_ROOT для $DOMAIN..."
        sudo mkdir -p "$WEB_ROOT"
        echo "<html><head><title>Welcome to $DOMAIN</title></head><body><h1>$DOMAIN is working!</h1></body></html>" | sudo tee "$WEB_ROOT/index.html"
    else
        echo "Директория $WEB_ROOT для $DOMAIN уже существует. Пропуск создания."
    fi

    # Создание временной конфигурации Nginx для проверки Let's Encrypt для $DOMAIN
    TEMP_CONFIG="/etc/nginx/sites-available/$DOMAIN-temp"
    if [ ! -f "$TEMP_CONFIG" ]; then
        echo "server {
            listen 80;
            server_name $DOMAIN;
    
            location / {
                return 301 https://\$host\$request_uri;
            }
        }" | sudo tee "$TEMP_CONFIG"
    
        sudo ln -sf "$TEMP_CONFIG" "/etc/nginx/sites-enabled/$DOMAIN-temp"
        sudo nginx -t && sudo systemctl reload nginx
    fi

    # Получение сертификата Let's Encrypt
    if [ -n "$MAIL" ]; then
        echo "Получение сертификата Let's Encrypt для $DOMAIN..."
        sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$MAIL" --redirect
        # Удаление временной конфигурации после получения сертификата
        sudo rm "$TEMP_CONFIG"
        sudo rm "/etc/nginx/sites-enabled/$DOMAIN-temp"
    else
        echo "Электронная почта для $DOMAIN не указана. Пропуск получения сертификата."
    fi

    # Создание конечной конфигурации Nginx с SSL для кастомного порта
    echo "Создание конфигурации Nginx для $DOMAIN на порту $PORT с SSL..."
    echo "server {
        listen $PORT ssl;
        listen [::]:$PORT ssl;
        server_name $DOMAIN;
    
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
        root $WEB_ROOT;
        index index.html;
    
        location / {
            try_files \$uri \$uri/ =404;
        }
    }" | sudo tee "$CONFIG"

    sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    sudo nginx -t && sudo systemctl reload nginx

    echo "Сайт $DOMAIN настроен."
done

echo "Скрипт завершил работу."