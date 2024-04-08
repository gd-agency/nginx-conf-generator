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

    echo "Настройка сайта: $DOMAIN"
    echo "Внутренний порт: $PORT"
    echo "Email для Let's Encrypt: $MAIL"
    echo "--------"

    # Создание конфигурации Nginx
    CONFIG="/etc/nginx/sites-available/$DOMAIN"
    if [ ! -f "$CONFIG" ]; then
        echo "Создание конфигурации Nginx для $DOMAIN..."
        echo "server {
            listen 80;
            server_name $DOMAIN;

            location / {
                proxy_pass http://localhost:$PORT;
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
            }

            location ~ /.well-known/acme-challenge {
                allow all;
                root /var/www/letsencrypt;
            }
        }" | sudo tee "$CONFIG"
        sudo ln -sf "$CONFIG" "/etc/nginx/sites-enabled/$DOMAIN"
    else
        echo "Конфигурация для $DOMAIN уже существует."
    fi

    sudo nginx -t && sudo systemctl reload nginx

    # Получение сертификата Let's Encrypt
    if [ -n "$MAIL" ]; then
        echo "Получение сертификата Let's Encrypt для $DOMAIN..."
        sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$MAIL" --redirect --keep-until-expiring
    else
        echo "Электронная почта для $DOMAIN не указана. Пропуск получения сертификата."
    fi

    echo "Сайт $DOMAIN настроен."
    echo "--------"
done

echo "Скрипт завершил работу."
