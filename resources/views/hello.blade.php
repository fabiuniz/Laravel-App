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
            <a href="http://vmlinuxd:8080" target="_blank" class="link">🗄️ phpMyAdmin</a>
        </div>
    </div>
</body>
</html>
