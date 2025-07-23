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
