#!/bin/bash

# Define o diretório da aplicação
APP_DIR="/var/www/html"

# Ajusta as permissões para o Laravel poder escrever nas pastas necessárias
# Isso é essencial quando se usa volumes de bind mount,
# pois as permissões do host podem sobrescrever as da imagem.
chown -R www-data:www-data "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"

# Se o .env não existir, copie do .env.example
if [ ! -f "${APP_DIR}/.env" ]; then
    cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
fi

# Gera a chave da aplicação Laravel se ainda não existir
if [ -z "${APP_KEY}" ]; then
    php ${APP_DIR}/artisan key:generate --ansi
fi

# Executa as migrations do banco de dados (opcional, pode ser feito manualmente)
php ${APP_DIR}/artisan migrate --force

# Limpa e otimiza o cache do Laravel
php ${APP_DIR}/artisan cache:clear
php ${APP_DIR}/artisan config:clear
php ${APP_DIR}/artisan view:clear
php ${APP_DIR}/artisan route:clear

# Reotimiza o autoloader para performance em produção (se for o caso)
# php ${APP_DIR}/artisan optimize

# Executa o comando principal do contêiner (neste caso, o Supervisor)
exec "$@"