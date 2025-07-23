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
