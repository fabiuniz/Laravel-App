#!/bin/bash

echo "🚀 Iniciando Laravel Docker App..."

# Parar containers existentes
echo "🛑 Parando containers existentes..."
docker-compose down

# Build e start
echo "🐳 Construindo containers..."
docker-compose build --no-cache

echo "▶️ Iniciando containers..."
docker-compose up -d

echo "⏳ Aguardando containers ficarem prontos..."
sleep 30

# Verificar se containers estão rodando
if ! docker-compose ps | grep -q "Up"; then
    echo "❌ Erro: Containers não iniciaram corretamente"
    docker-compose logs
    exit 1
fi

# Comandos Laravel
echo "🔑 Gerando chave da aplicação..."
docker-compose exec -T app php artisan key:generate

echo "🗄️ Rodando migrations..."
docker-compose exec -T app php artisan migrate --force

echo "🧹 Limpando cache..."
docker-compose exec -T app php artisan config:clear
docker-compose exec -T app php artisan cache:clear
docker-compose exec -T app php artisan route:clear

echo "🔧 Otimizando aplicação..."
docker-compose exec -T app php artisan config:cache
docker-compose exec -T app php artisan route:cache

echo ""
echo "✅ Projeto iniciado com sucesso!"
echo "🌐 Aplicação: http://vmlinuxd:8000"
echo "🗄️ phpMyAdmin: http://vmlinuxd:8080"
echo "📡 API Test: http://vmlinuxd:8000/api/hello"
echo "ℹ️ System Info: http://vmlinuxd:8000/info"
echo ""
echo "📊 Status dos containers:"
docker-compose ps
