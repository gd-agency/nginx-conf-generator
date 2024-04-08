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

# Чтение файла и добавление сайтов
yq e '.websites[]' $YAML_FILE -o=json | while IFS= read -r website; do
    DOMAIN=$(echo $website | jq -r '.domain')
    PORT=$(echo $website | jq -r '.port')
    MAIL=$(echo $website | jq -r '.mail')

    echo "Креды для сайта"
    echo "Домен $DOMAIN"
    echo "Порт для прослушивания $PORT"
    echo "Почта для сертификата $MAIL"

    # Проверка, был ли сайт уже добавлен
    if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
        echo "Сайт для $DOMAIN уже настроен."
        continue
    fi

    WEB_ROOT="/apps/web/$DOMAIN"
    CONFIG="/etc/nginx/sites-available/$DOMAIN"

    # Создание директории для сайта
    echo "Создание директории $WEB_ROOT для $DOMAIN..."
    sudo mkdir -p "$WEB_ROOT"
    echo "<html><head><title>Welcome to $DOMAIN</title></head><body><h1>$DOMAIN is working!</h1></body></html>" | sudo tee "$WEB_ROOT/index.html"

    # Создание конфигурации Nginx
    echo "Создание конфигурации Nginx для $DOMAIN на порту $PORT..."
    echo "server {
        listen $PORT;
        listen [::]:$PORT;

        server_name $DOMAIN;

        root $WEB_ROOT;
        index index.html;

        location / {
            try_files \$uri \$uri/ =404;
        }
    }" | sudo tee "$CONFIG"

    # Активация конфигурации и перезапуск Nginx
    sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
    sudo nginx -t && sudo systemctl reload nginx

    # Получение сертификата Let's Encrypt (опционально, убрать комментарий для включения)
    if [ -n "$MAIL" ]; then
        echo "Получение сертификата Let's Encrypt для $DOMAIN..."
        sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$MAIL" --redirect
    else
        echo "Электронная почта для $DOMAIN не указана. Пропуск получения сертификата."
    fi

    echo "Сайт $DOMAIN настроен."
done

echo "Скрипт завершил работу."