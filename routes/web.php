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
