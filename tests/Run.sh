#!/bin/bash

DISTROS=("bookworm" "bullseye" "buster" "focal" "jammy" "noble")
ARCHITECTURES=("linux/arm/v6" "linux/arm/v7" "linux/arm64" "linux/amd64")
LOG_DIR="$(pwd)/install_test_results"
FULL_LOG_FILE="$LOG_DIR/full_log.txt"

# Спрашиваем, сколько параллельно можно запускать
read -p "Сколько сборок можно запускать параллельно? " MAX_PARALLEL

# Очистка экрана при выходе
trap "tput reset; exit" SIGINT SIGTERM

# Создаем папку для логов, если она не существует
mkdir -p "$LOG_DIR"

# Создаем или очищаем файл полных логов
echo "Полные логи выполнения" > "$FULL_LOG_FILE"

# Функция для очистки строки перед обновлением
clear_line() {
    tput el
}

# Функция для обновления таблицы статусов в терминале
update_table() {
    tput cup 0 0
    echo "Дистрибутив | Архитектура | Статус                  | Время"
    echo "-----------------------------------------------------------"
    local line=2
    for TASK in "${TASKS[@]}"; do
        DISTRO=$(echo $TASK | cut -d'|' -f1)
        ARCH=$(echo $TASK | cut -d'|' -f2)
        STATUS=${statuses["$DISTRO-$ARCH"]}
        DURATION=$(format_time ${start_times["$DISTRO-$ARCH"]})

        tput cup $line 0
        clear_line
        echo "$DISTRO | $ARCH | $STATUS | $DURATION"

        ((line++))
        # Ограничиваем вывод только до MAX_PARALLEL строк
        if [[ $line -ge $((MAX_PARALLEL + 2)) ]]; then
            break
        fi
    done
    echo "-----------------------------------------------------------"
}

# Функция для форматирования времени выполнения
format_time() {
    local start_time=$1
    if [[ -z "$start_time" ]]; then
        echo "00:00:00"
        return
    fi
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed/60)%60)) $((elapsed%60))
}

# Инициализация статуса для каждого теста
declare -A statuses
declare -A start_times
declare -A completed_tasks
TASKS=()

# Инициализация интерфейса
tput clear
echo "Начинается тестирование..."

run_container() {
    local DISTRO=$1
    local ARCH=$2

    SAFE_ARCH=$(echo $ARCH | tr '/' '_')
    CONTAINER_NAME="z-way-test-container-$DISTRO-$SAFE_ARCH"

    # Запускаем отсчёт времени
    start_times["$DISTRO-$ARCH"]=$(date +%s)
    statuses["$DISTRO-$ARCH"]="Сборка начата"
    update_table

    # Сборка Docker-образа с указанием архитектуры
    if ! DOCKER_OUTPUT=$(docker buildx build --progress plain --platform $ARCH -f Dockerfile.$DISTRO -t z-way-test-$DISTRO-$SAFE_ARCH --load . 2>&1 | tee -a "$FULL_LOG_FILE"); then
        statuses["$DISTRO-$ARCH"]="Ошибка сборки"
        update_table
        completed_tasks["$DISTRO-$ARCH"]=1
        return
    fi
    statuses["$DISTRO-$ARCH"]="Сборка завершена"
    update_table

    # Запуск контейнера с монтированием директории для логов
    if ! docker run --platform $ARCH --name $CONTAINER_NAME -v "$LOG_DIR:/opt/z-way-server/install_test_results" -d z-way-test-$DISTRO-$SAFE_ARCH tail -f /dev/null >/dev/null 2>&1; then
        statuses["$DISTRO-$ARCH"]="Ошибка запуска контейнера"
        update_table
        completed_tasks["$DISTRO-$ARCH"]=1
        return
    fi
    statuses["$DISTRO-$ARCH"]="Тестирование начато"
    update_table

    # Выполнение всех тестовых скриптов из папки tests
    for test_script in $(ls tests/*.sh | sort); do
        if ! docker exec $CONTAINER_NAME bash -c "/tests/$(basename $test_script) $DISTRO $SAFE_ARCH" >>"$FULL_LOG_FILE" 2>&1; then
            statuses["$DISTRO-$ARCH"]="Ошибка тестирования"
            update_table
            docker stop $CONTAINER_NAME >/dev/null 2>&1
            docker rm $CONTAINER_NAME >/dev/null 2>&1
            completed_tasks["$DISTRO-$ARCH"]=1
            return
        fi
    done

    # Очистка контейнера и образа
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    docker rmi z-way-test-$DISTRO-$SAFE_ARCH >/dev/null 2>&1

    statuses["$DISTRO-$ARCH"]="Тестирование завершено"
    update_table
    completed_tasks["$DISTRO-$ARCH"]=1
}

export -f run_container

# Главный цикл, управляющий параллельными сборками
start_next_task() {
    while true; do
        running_tasks=$(jobs -r | wc -l)
        if [[ $running_tasks -lt $MAX_PARALLEL ]]; then
            for ARCH in "${ARCHITECTURES[@]}"; do
                for DISTRO in "${DISTROS[@]}"; do
                    if [[ -z "${completed_tasks["$DISTRO-$ARCH"]}" ]]; then
                        TASKS+=("$DISTRO|$ARCH")
                        run_container $DISTRO $ARCH &
                        break 2
                    fi
                done
            done
        fi
        sleep 1
        update_table
    done
}

# Запуск первого набора задач
start_next_task
wait
