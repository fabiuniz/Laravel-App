#!/bin/bash

echo "🚀 Configurando Projeto Laravel Completo com Docker"
echo "=================================================="

# Verificar se está no diretório correto
if [ ! -f "$(basename "$0")" ]; then
    echo "⚠️  Execute este script no diretório onde deseja criar o projeto"
fi

SERVER_NAME="vmlinuxd" # 127.0.0.1
PROJECT_NAME="laravel-docker-app"
echo "📁 Criando projeto: $PROJECT_NAME"

# Criar diretório do projeto se não existir
mkdir -p $PROJECT_NAME
chmod -R 777 $PROJECT_NAME
cd $PROJECT_NAME

echo "🔽 Baixando Laravel via Composer..."
# Criar projeto Laravel usando imagem Docker temporária
docker run --rm -v "$(pwd):/app" composer:latest create-project --prefer-dist laravel/laravel . "8.*"

# Aguardar download completar
sleep 5

echo "📁 Criando estrutura Docker..."
# Criar diretórios Docker
mkdir -p docker/{nginx,php,mysql,supervisor}

echo "🐋 Criando Dockerfile..."
cat > Dockerfile << 'EOF'
FROM php:8.3-fpm

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libjpeg-dev \
    libwebp-dev \
    libfreetype6-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    zip \
    unzip \
    libzip-dev \
    nginx \
    supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configurar e instalar extensões PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) pdo_mysql mbstring exif pcntl bcmath gd sockets zip intl

# Instalar Composer
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Definir diretório de trabalho
WORKDIR /var/www/html

# Copiar arquivos do projeto (agora o composer.json existe!)
COPY . .

# Instalar dependências do Composer
RUN composer install --optimize-autoloader --no-dev --no-interaction

# Configurar permissões
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && chmod -R 775 storage bootstrap/cache

# Copiar configurações
COPY docker/nginx/default.conf /etc/nginx/sites-available/default
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF

echo "🐳 Criando .gitignore..." # Corrected description
cat > .gitignore << 'EOF'

/node_modules
/public/hot
/public/storage
/storage/*.key
/storage/app/public/uploads # Exemplo, ajuste conforme seus diretórios de upload
/storage/framework/cache/*
/storage/framework/sessions/*
/storage/framework/views/*
/storage/framework/testing/*
/storage/logs/*.log
/vendor

.env
.env.backup
.env.*.local
.phpunit.result.cache
.vscode/
.idea/
.DS_Store
*.log
npm-debug.log
yarn-error.log
.composer
.history

# Docker
docker-compose.override.yml # Se você usar um arquivo override local
/dbdata # Volume do MySQL local
/.docker/ # Se você tiver um diretório .docker com dados sensíveis ou de cache

# GCP Service Account Key (MUITO IMPORTANTE!)
sa-key.json

EOF

echo "🐳 Criando estrutura de workflows para GCP..."
# FIX: Ensure .github/workflows directory exists before creating the file
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml << 'EOF'

name: Deploy to GCP

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
  GAR_LOCATION: us-central1 # Certifique-se de que esta é a região do seu Artifact Registry
  REPOSITORY: laravel-app
  SERVICE: laravel-docker-app
  REGION: us-central1 # Certifique-se de que esta é a região do seu Cloud Run e Cloud SQL

jobs:
  test:
    runs-on: ubuntu-latest
    name: Run Tests
    
    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root_password
          MYSQL_DATABASE: laravel_test
        ports:
          - 3306:3306
        options: --health-cmd="mysqladmin ping" --health-interval=10s --health-timeout=5s --health-retries=3

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.3'
          extensions: mbstring, dom, fileinfo, mysql, gd, zip, bcmath

      - name: Copy .env
        run: php -r "file_exists('.env') || copy('.env.example', '.env');"

      - name: Install Dependencies
        run: composer install -q --no-ansi --no-interaction --no-scripts --no-progress --prefer-dist

      - name: Generate key
        run: php artisan key:generate

      - name: Directory Permissions
        run: chmod -R 777 storage bootstrap/cache

      - name: Create Database
        run: |
          mysql --host 127.0.0.1 --port 3306 -uroot -proot_password -e 'CREATE DATABASE IF NOT EXISTS laravel_test;'

      - name: Execute tests (Unit and Feature tests) via PHPUnit
        env:
          DB_CONNECTION: mysql
          DB_HOST: 127.0.0.1
          DB_PORT: 3306
          DB_DATABASE: laravel_test
          DB_USERNAME: root
          DB_PASSWORD: root_password
        run: vendor/bin/phpunit

  build-and-deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    permissions:
      contents: read
      id-token: write # Necessário para autenticação no GCP

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Google Auth
        id: auth
        uses: 'google-github-actions/auth@v2'
        with:
          credentials_json: '${{ secrets.GCP_SA_KEY }}'

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker ${{ env.GAR_LOCATION }}-docker.pkg.dev

      - name: Build and Push Container
        run: |-
          docker build -t "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}" ./
          docker push "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}"

      - name: Deploy to Cloud Run
        id: deploy
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: ${{ env.SERVICE }}
          region: ${{ env.REGION }}
          image: ${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}
          env_vars: |
            APP_ENV=production
            APP_DEBUG=false
            APP_KEY=${{ secrets.LARAVEL_APP_KEY }}
            APP_URL=${{ steps.deploy.outputs.url }} # Pega a URL gerada pelo Cloud Run
            DB_CONNECTION=mysql
            DB_HOST=/cloudsql/${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_PROD # <--- AJUSTAR AQUI
            DB_PORT=3306
            DB_DATABASE=${{ secrets.DB_DATABASE }}
            DB_USERNAME=${{ secrets.DB_USERNAME }}
            DB_PASSWORD=${{ secrets.DB_PASSWORD }}
          cloud_sql_instances: ${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_PROD # <--- AJUSTAR AQUI
          # Adicione o tempo limite, se necessário (padrão é 5min)
          timeout: 900s # Aumentado para 15 minutos para deploy grande ou lento

      - name: Run Laravel Migrations
        # Executa as migrações usando um Cloud Run Job temporário
        run: |
          MIGRATION_JOB_NAME="${{ env.SERVICE }}-migrate-${{ github.sha }}"
          
          echo "Criando e executando Cloud Run Job para migrações: ${MIGRATION_JOB_NAME}"
          gcloud run jobs create "${MIGRATION_JOB_NAME}" \
            --image="${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}" \
            --command="/usr/local/bin/php" --args="artisan","migrate","--force" \
            --region="${{ env.REGION }}" \
            --project="${{ env.PROJECT_ID }}" \
            --no-cpu-throttling \
            --service-account="${{ secrets.GCP_SA_EMAIL }}" \ # Use o e-mail completo da sua SA
            --set-env-vars="DB_CONNECTION=mysql,DB_HOST=/cloudsql/${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_PROD,DB_PORT=3306,DB_DATABASE=${{ secrets.DB_DATABASE }},DB_USERNAME=${{ secrets.DB_USERNAME }},DB_PASSWORD=${{ secrets.DB_PASSWORD }}" \
            --cloud-sql-instances="${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_PROD" \
            --wait # Espera o job terminar
          
          echo "Migrações concluídas para o serviço ${{ env.SERVICE }}"
          
          # Opcional: Para evitar jobs acumulados, você pode apagar o job após a execução
          # gcloud run jobs delete "${MIGRATION_JOB_NAME}" --region="${{ env.REGION }}" --project="${{ env.PROJECT_ID }}" --quiet

      - name: Show Production URL
        run: echo "🚀 Aplicação de Produção disponível em: ${{ steps.deploy.outputs.url }}"

  staging-deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    
    permissions:
      contents: read
      id-token: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Google Auth
        id: auth
        uses: 'google-github-actions/auth@v2'
        with:
          credentials_json: '${{ secrets.GCP_SA_KEY }}'

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker ${{ env.GAR_LOCATION }}-docker.pkg.dev

      - name: Build and Push Container (Staging)
        run: |-
          docker build -t "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}-staging:${{ github.sha }}" ./
          docker push "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}-staging:${{ github.sha }}"

      - name: Deploy to Cloud Run (Staging)
        id: deploy_staging
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: ${{ env.SERVICE }}-staging
          region: ${{ env.REGION }}
          image: ${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}-staging:${{ github.sha }}
          env_vars: |
            APP_ENV=staging
            APP_DEBUG=true
            APP_KEY=${{ secrets.LARAVEL_APP_KEY }} # Pode usar a mesma chave ou uma específica para staging
            APP_URL=${{ steps.deploy_staging.outputs.url }}
            DB_CONNECTION=mysql
            DB_HOST=/cloudsql/${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_STAGING # <--- AJUSTAR AQUI
            DB_PORT=3306
            DB_DATABASE=${{ secrets.DB_DATABASE_STAGING }}
            DB_USERNAME=${{ secrets.DB_USERNAME_STAGING }}
            DB_PASSWORD=${{ secrets.DB_PASSWORD_STAGING }}
          cloud_sql_instances: ${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_STAGING # <--- AJUSTAR AQUI
          timeout: 900s

      - name: Run Laravel Migrations (Staging)
        run: |
          MIGRATION_JOB_NAME="${{ env.SERVICE }}-staging-migrate-$(date +%s)"
          
          echo "Criando e executando Cloud Run Job para migrações de staging: ${MIGRATION_JOB_NAME}"
          gcloud run jobs create "${MIGRATION_JOB_NAME}" \
            --image="${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}-staging:${{ github.sha }}" \
            --command="/usr/local/bin/php" --args="artisan","migrate","--force" \
            --region="${{ env.REGION }}" \
            --project="${{ env.PROJECT_ID }}" \
            --no-cpu-throttling \
            --service-account="${{ secrets.GCP_SA_EMAIL }}" \
            --set-env-vars="DB_CONNECTION=mysql,DB_HOST=/cloudsql/${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_STAGING,DB_PORT=3306,DB_DATABASE=${{ secrets.DB_DATABASE_STAGING }},DB_USERNAME=${{ secrets.DB_USERNAME_STAGING }},DB_PASSWORD=${{ secrets.DB_PASSWORD_STAGING }}" \
            --cloud-sql-instances="${{ env.PROJECT_ID }}:${{ env.REGION }}:YOUR_CLOUD_SQL_INSTANCE_NAME_STAGING" \
            --wait
          
          echo "Migrações concluídas para o serviço ${{ env.SERVICE }}-staging"

      - name: Show Staging URL
        run: echo "🧪 Aplicação de Staging disponível em: ${{ steps.deploy_staging.outputs.url }}"

EOF

echo "🐳 Criando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: laravel_app
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ./:/var/www/html
      - ./docker/php/local.ini:/usr/local/etc/php/conf.d/local.ini
    ports:
      - "8000:80"
    networks:
      - app-network
    depends_on:
      - db
    environment:
      - APP_ENV=local
      - APP_DEBUG=true

  db:
    image: mysql:8.0
    container_name: mysql_db
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_DATABASE: laravel_db
      MYSQL_ROOT_PASSWORD: root_password
      MYSQL_PASSWORD: laravel_password
      MYSQL_USER: laravel_user
    volumes:
      - dbdata:/var/lib/mysql
      - ./docker/mysql/my.cnf:/etc/mysql/conf.d/my.cnf
    networks:
      - app-network
    command: --default-authentication-plugin=mysql_native_password

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: phpmyadmin
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PMA_HOST: db
      MYSQL_ROOT_PASSWORD: root_password
      PMA_ARBITRARY: 1
    networks:
      - app-network
    depends_on:
      - db

networks:
  app-network:
    driver: bridge

volumes:
  dbdata:
    driver: local
EOF

echo "⚙️ Criando configurações Docker..."

# Nginx config
cat > docker/nginx/default.conf << 'EOF'
server {
    listen 80;
    server_name $SERVER_NAME;
    index index.php index.html;
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
    root /var/www/html/public;

    # Configurações de segurança
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_read_timeout 300;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
        gzip_static on;
    }

    # Cache para assets estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Negar acesso a arquivos sensíveis
    location ~ /\. {
        deny all;
    }
}
EOF

# PHP config
cat > docker/php/local.ini << 'EOF'
upload_max_filesize=100M
post_max_size=100M
max_execution_time=600
memory_limit=512M
max_input_vars=3000
date.timezone=America/Sao_Paulo

; Configurações de desenvolvimento
display_errors=On
error_reporting=E_ALL
log_errors=On

; Configurações de performance
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
EOF

# MySQL config
mkdir -p docker/mysql
cat > docker/mysql/my.cnf << 'EOF'
[mysqld]
general_log = 1
general_log_file = /var/lib/mysql/general.log
default-authentication-plugin=mysql_native_password

# Performance
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
max_connections = 100

# Charset
collation-server = utf8mb4_unicode_ci
init-connect = 'SET NAMES utf8mb4'
character-set-server = utf8mb4
EOF

# Supervisor config
cat > docker/supervisor/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:php-fpm]
command=php-fpm -F
autostart=true
autorestart=true
priority=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/html/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/supervisor/worker.log
stopwaitsecs=3600
EOF

echo "🎨 Criando Controller e View..."

# Criar HelloController
mkdir -p app/Http/Controllers
cat > app/Http/Controllers/HelloController.php << 'EOF'
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class HelloController extends Controller
{
    public function index()
    {
        return view('hello', [
            'message' => 'Hello World from Laravel!',
            'version' => app()->version(),
            'php_version' => phpversion(),
            'environment' => config('app.env'),
            'database' => $this->checkDatabase(),
            'server_info' => $this->getServerInfo()
        ]);
    }

    public function api()
    {
        return response()->json([
            'message' => 'Hello World from Laravel API!',
            'timestamp' => now(),
            'version' => app()->version(),
            'php_version' => phpversion(),
            'status' => 'success',
            'database' => $this->checkDatabase(),
            'memory_usage' => $this->getMemoryUsage()
        ]);
    }

    private function checkDatabase()
    {
        try {
            DB::connection()->getPdo();
            $result = DB::select('SELECT VERSION() as version')[0];
            return '✅ MySQL ' . $result->version;
        } catch (\Exception $e) {
            return '❌ Erro: ' . $e->getMessage();
        }
    }

    private function getServerInfo()
    {
        return [
            'os' => php_uname('s'),
            'architecture' => php_uname('m'),
            'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'
        ];
    }

    private function getMemoryUsage()
    {
        return [
            'current' => round(memory_get_usage(true) / 1024 / 1024, 2) . ' MB',
            'peak' => round(memory_get_peak_usage(true) / 1024 / 1024, 2) . ' MB'
        ];
    }
}
EOF

# Criar view
mkdir -p resources/views
cat > resources/views/hello.blade.php << 'EOF'
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ config('app.name') }} - Hello World</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            padding: 3rem;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 800px;
            width: 100%;
            animation: fadeIn 1s ease-in;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(30px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        h1 {
            color: #333;
            margin-bottom: 1rem;
            font-size: 2.5rem;
            font-weight: 700;
        }
        
        .info {
            background: #f8f9fa;
            padding: 2rem;
            border-radius: 12px;
            margin: 2rem 0;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .info-item {
            background: white;
            padding: 1rem;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .info-item strong {
            display: block;
            color: #666;
            font-size: 0.9rem;
            margin-bottom: 0.5rem;
        }
        
        .badge {
            background: #28a745;
            color: white;
            padding: 0.5rem 1rem;
            border-radius: 25px;
            font-size: 0.9rem;
            font-weight: 600;
            display: inline-block;
        }
        
        .badge.warning {
            background: #ffc107;
            color: #333;
        }
        
        .badge.error {
            background: #dc3545;
        }
        
        .features {
            display: flex;
            justify-content: space-around;
            flex-wrap: wrap;
            gap: 1rem;
            margin-top: 2rem;
        }
        
        .feature {
            flex: 1;
            min-width: 150px;
            padding: 1rem;
            background: linear-gradient(45deg, #f093fb 0%, #f5576c 100%);
            color: white;
            border-radius: 10px;
            font-weight: 600;
        }
        
        .links {
            margin-top: 2rem;
            display: flex;
            gap: 1rem;
            justify-content: center;
            flex-wrap: wrap;
        }
        
        .link {
            background: #007bff;
            color: white;
            padding: 0.8rem 1.5rem;
            text-decoration: none;
            border-radius: 25px;
            font-weight: 600;
            transition: transform 0.2s;
        }
        
        .link:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        
        .server-info {
            background: #e9ecef;
            padding: 1rem;
            border-radius: 8px;
            margin-top: 1rem;
            font-size: 0.9rem;
        }
        
        @media (max-width: 768px) {
            .container { padding: 2rem; }
            h1 { font-size: 2rem; }
            .features { flex-direction: column; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 {{ $message }}</h1>
        
        <div class="info">
            <h3>📊 Informações do Sistema</h3>
            <div class="info-grid">
                <div class="info-item">
                    <strong>🚀 Laravel Version</strong>
                    <span class="badge">{{ $version }}</span>
                </div>
                <div class="info-item">
                    <strong>🐘 PHP Version</strong>
                    <span class="badge">{{ $php_version }}</span>
                </div>
                <div class="info-item">
                    <strong>🌍 Environment</strong>
                    <span class="badge {{ $environment === 'production' ? '' : 'warning' }}">
                        {{ strtoupper($environment) }}
                    </span>
                </div>
                <div class="info-item">
                    <strong>🗄️ Database</strong>
                    <span class="badge {{ str_contains($database, '✅') ? '' : 'error' }}">
                        {{ $database }}
                    </span>
                </div>
            </div>

            <div class="server-info">
                <strong>🖥️ Server Info:</strong> 
                {{ $server_info['os'] }} ({{ $server_info['architecture'] }})
                | {{ $server_info['server_software'] ?? 'Nginx' }}
            </div>
        </div>

        <div class="features">
            <div class="feature">
                🐳 Docker
            </div>
            <div class="feature">
                🗄️ MySQL 8.0
            </div>
            <div class="feature">
                🔧 phpMyAdmin
            </div>
            <div class="feature">
                ⚡ PHP 8.3
            </div>
        </div>

        <div class="links">
            <a href="/api/hello" class="link">📡 API Test</a>
            <a href="/info" class="link">ℹ️ System Info</a>
            <a href="http://$SERVER_NAME:8080" target="_blank" class="link">🗄️ phpMyAdmin</a>
        </div>
    </div>
</body>
</html>
EOF

# Atualizar routes
cat > routes/web.php << 'EOF'
<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\HelloController;

Route::get('/', [HelloController::class, 'index']);
Route::get('/api/hello', [HelloController::class, 'api']);

Route::get('/info', function () {
    return response()->json([
        'app' => config('app.name'),
        'version' => app()->version(),
        'php' => phpversion(),
        'laravel' => \Illuminate\Foundation\Application::VERSION,
        'environment' => config('app.env'),
        'timestamp' => now(),
        'server' => [
            'os' => php_uname('s'),
            'architecture' => php_uname('m'),
            'software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'
        ],
        'memory' => [
            'current' => round(memory_get_usage(true) / 1024 / 1024, 2) . ' MB',
            'peak' => round(memory_get_peak_usage(true) / 1024 / 1024, 2) . ' MB',
            'limit' => ini_get('memory_limit')
        ]
    ]);
});
EOF

echo "⚙️ Configurando .env..."
# Atualizar .env
cat > .env << 'EOF'
APP_NAME="Laravel Docker App"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://$SERVER_NAME:8000

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=laravel_db
DB_USERNAME=laravel_user
DB_PASSWORD=laravel_password

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"
EOF

echo "🚀 Criando scripts de gerenciamento..."
cat > start.sh << 'EOF'
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
echo "🌐 Aplicação: http://$SERVER_NAME:8000"
echo "🗄️ phpMyAdmin: http://$SERVER_NAME:8080"
echo "📡 API Test: http://$SERVER_NAME:8000/api/hello"
echo "ℹ️ System Info: http://$SERVER_NAME:8000/info"
echo ""
echo "📊 Status dos containers:"
docker-compose ps
EOF

# Script para desenvolvimento
cat > dev.sh << 'EOF'
#!/bin/bash

echo "🔧 Modo Desenvolvimento - Laravel Docker"

case "$1" in
    "logs")
        docker-compose logs -f
        ;;
    "bash")
        docker-compose exec app bash
        ;;
    "artisan")
        shift
        docker-compose exec app php artisan "$@"
        ;;
    "composer")
        shift
        docker-compose exec app composer "$@"
        ;;
    "test")
        docker-compose exec app php artisan test
        ;;
    "migrate")
        docker-compose exec app php artisan migrate
        ;;
    "fresh")
        docker-compose exec app php artisan migrate:fresh --seed
        ;;
    "restart")
        docker-compose restart
        ;;
    "stop")
        docker-compose down
        ;;
    "rebuild")
        docker-compose down
        docker-compose build --no-cache
        docker-compose up -d
        ;;
    *)
        echo "🚀 Comandos disponíveis:"
        echo "  ./dev.sh logs     - Ver logs em tempo real"
        echo "  ./dev.sh bash     - Acessar container"
        echo "  ./dev.sh artisan  - Executar comando artisan"
        echo "  ./dev.sh composer - Executar comando composer"
        echo "  ./dev.sh test     - Executar testes"
        echo "  ./dev.sh migrate  - Executar migrations"
        echo "  ./dev.sh fresh    - Reset database com seeds"
        echo "  ./dev.sh restart  - Reiniciar containers"
        echo "  ./dev.sh stop     - Parar containers"
        echo "  ./dev.sh rebuild  - Rebuild containers"
        ;;
esac
EOF

chmod +x start.sh dev.sh

echo ""
echo "✅ Setup completo! Configurações:"
echo "🔧 Docker Compose v3"
echo "🐘 PHP 8.0-fmp"
echo "🗄️ MySQL 8.0 com configurações otimizadas"
echo "⚡ Configurações de performance PHP"
echo "🔒 Configurações de segurança Nginx"
echo "📊 Informações detalhadas do sistema"
echo "🛠️ Scripts de desenvolvimento (dev.sh)"
echo ""
echo "📁 Projeto criado em: $(pwd)"
echo ""
echo "🚀 Para iniciar:"
echo "    ./start.sh"
echo ""
echo "🔧 Comandos úteis:"
echo "    docker-compose logs -f    # Ver logs"
echo "    docker-compose exec app bash  # Acessar container"
echo "    docker-compose down       # Parar containers"
echo ""

#nano /etc/docker/daemon.json
#{
#  "dns": ["8.8.8.8", "8.8.4.4"]
#}
#lsof -i :3306
#phpmyadmin / Mysql
#$SERVER_NAME
#root
#root_password