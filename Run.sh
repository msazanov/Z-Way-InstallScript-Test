#!/bin/bash




# Подключаем скрипт checkbox.sh
source "$(dirname "$0")/checkbox.sh"

# Запускаем интерфейс выбора
distSelector_run

# Получаем выбранные дистрибутивы и архитектуры
selected_distributions=($(distSelector_get_selected_distributions))
selected_architectures=($(distSelector_get_selected_architectures))

# Проверяем выбор
if [[ ${#selected_distributions[@]} -eq 0 || ${#selected_architectures[@]} -eq 0 ]]; then
    echo "Не выбраны дистрибутивы или архитектуры. Программа завершена."
    exit 1
fi

# Используем выбранные дистрибутивы и архитектуры
DISTROS=("${selected_distributions[@]}")
ARCHITECTURES=("${selected_architectures[@]}")

# Спрашиваем количество параллельных сборок
read -p "Сколько сборок можно запускать параллельно? (по умолчанию 4) " MAX_PARALLEL

# Проверяем и устанавливаем MAX_PARALLEL
if [[ -z "$MAX_PARALLEL" ]]; then
    MAX_PARALLEL=4
fi
if ! [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL" -lt 1 ]]; then
    echo "Некорректное значение, устанавливаем MAX_PARALLEL=4"
    MAX_PARALLEL=4
fi

# Создаём директории и файлы логов
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="install_test_results/$TIMESTAMP"
FULL_LOG_FILE="$LOG_DIR/Full.log"
mkdir -p "$LOG_DIR"
echo "Полные логи выполнения" > "$FULL_LOG_FILE"

# Инициализируем массивы
declare -A statuses
declare -A start_times
declare -A end_times
declare -A TASK_ROW
declare -A running_tasks_pids

TASKS=()

# Заполняем TASKS и инициализируем статусы
for arch in "${ARCHITECTURES[@]}"; do
    for distro in "${DISTROS[@]}"; do
        TASKS+=("$distro|$arch")
        statuses["$distro-$arch"]="QUEUE"
    done
done

# Функция для очистки текущей строки в терминале
clear_line() {
    tput el      # Очищаем от курсора до конца строки
    tput el1     # Очищаем от начала строки до курсора
}


# Функция для форматирования времени
format_time() {
    local start_time=$1
    local end_time=$2
    if [[ -z "$start_time" ]]; then
        echo "00:00:00"
        return
    fi
    if [[ -z "$end_time" ]]; then
        end_time=$(date +%s)
    fi
    local elapsed=$((end_time - start_time))
    printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed/60)%60)) $((elapsed%60))
}

# Функция для получения прошедшего времени для задачи
get_elapsed_time() {
    local distro=$1
    local arch=$2
    local status=${statuses["$distro-$arch"]}
    local start_time=${start_times["$distro-$arch"]}
    local end_time=${end_times["$distro-$arch"]}

    if [[ "$status" == "QUEUE" || -z "$start_time" ]]; then
        echo "00:00:00"
    elif [[ "$status" == "TESTING" ]]; then
        format_time "$start_time"
    elif [[ "$status" == "PASS" || "$status" == "FAIL" || "$status" == "WARNING" ]]; then
        format_time "$start_time" "$end_time"
    else
        echo "00:00:00"
    fi
}

# Функция для обновления строки в таблице
update_row() {
    local row=$1
    local distro=$2
    local arch=$3
    local status=$4

    # Получаем прошедшее время
    local elapsed_time=$(get_elapsed_time "$distro" "$arch")

    # Определяем цвет в зависимости от статуса
    local color_reset="\e[0m"
    local color
    case "$status" in
        "PASS")
            color="\e[32m"  # Зеленый
            ;;
        "FAIL")
            color="\e[31m"  # Красный
            ;;
        "TESTING")
            color="\e[33m"  # Желтый
            ;;
        "QUEUE")
            color="\e[34m"  # Синий
            ;;
        *)
            color="\e[0m"   # Сброс цвета
            ;;
    esac

    # Перемещаем курсор в нужную строку, очищаем строку и выводим обновленные данные
    tput cup $row 0
    clear_line
    printf "%-20s | %-12s | ${color}%-10s${color_reset} | %-8s\n" "$distro" "$arch" "$status" "$elapsed_time"
}

update_running_tasks() {
    for task in "${!running_tasks_pids[@]}"; do
        pid=${running_tasks_pids["$task"]}
        if ! kill -0 $pid 2>/dev/null; then
            # Процесс завершился, удаляем его из массива
            unset running_tasks_pids["$task"]
        fi
    done
}


# Функция для инициализации таблицы
init_table() {
    tput clear
    tput cup 0 0
    echo "Дистрибутив         | Архитектура  | Статус     | Время"
    echo "-------------------------------------------------------"
    local line=2
    for TASK in "${TASKS[@]}"; do
        distro=$(echo $TASK | cut -d'|' -f1)
        arch=$(echo $TASK | cut -d'|' -f2)
        update_row $line "$distro" "$arch" "QUEUE"
        TASK_ROW["$distro-$arch"]=$line  # Store row number for later updates
        line=$((line + 1))
    done
}

# Функция для обновления времени задач в состоянии TESTING
update_testing_time() {
    for TASK in "${TASKS[@]}"; do
        distro=$(echo $TASK | cut -d'|' -f1)
        arch=$(echo $TASK | cut -d'|' -f2)
        # Обновляем время только для задач в статусе TESTING
        if [[ "${statuses["$distro-$arch"]}" == "TESTING" ]]; then
            update_row ${TASK_ROW["$distro-$arch"]} "$distro" "$arch" "TESTING"
        fi
    done
}

# Функция для чтения статуса из файла .progress
get_status_from_progress() {
    local distro=$1
    local arch=$2
    local progress_file="$LOG_DIR/$distro-$arch/.progress"

    if [[ ! -f "$progress_file" ]]; then
        echo "QUEUE"
    else
        local status=$(jq -r '.status' "$progress_file")
        echo "$status"
    fi
}

# Функция для получения времени из .progress
get_times_from_progress() {
    local distro=$1
    local arch=$2
    local progress_file="$LOG_DIR/$distro-$arch/.progress"

    if [[ -f "$progress_file" ]]; then
        local start_time=$(jq -r '.start_time' "$progress_file")
        local end_time=$(jq -r '.end_time' "$progress_file")

        # Обновляем массивы
        if [[ "$start_time" != "null" ]]; then
            start_times["$distro-$arch"]=$start_time
        fi
        if [[ "$end_time" != "null" ]]; then
            end_times["$distro-$arch"]=$end_time
        fi
    fi
}

# Функция для обновления статуса в файле .progress
update_progress_status() {
    local distro=$1
    local arch=$2
    local status=$3
    local progress_file="$LOG_DIR/$distro-$arch/.progress"
    local log_dir="$LOG_DIR/$distro-$arch"

    # Создаем директорию, если она не существует
    mkdir -p "$log_dir" 2>> "$FULL_LOG_FILE"

    # Получаем текущее время
    local current_time=$(date +%s)

    # Если статус TESTING, записываем время начала
    if [[ "$status" == "TESTING" ]]; then
        # Записываем статус и время начала
        echo "{\"status\":\"$status\",\"start_time\":$current_time,\"end_time\":null}" > "$progress_file"
    elif [[ "$status" == "PASS" || "$status" == "FAIL" || "$status" == "WARNING" ]]; then
        # Читаем предыдущие данные
        if [[ -f "$progress_file" ]]; then
            local start_time=$(jq '.start_time' "$progress_file")
        else
            local start_time=$current_time
        fi
        # Записываем статус, время начала и окончания
        echo "{\"status\":\"$status\",\"start_time\":$start_time,\"end_time\":$current_time}" > "$progress_file"
    else
        # Для других статусов
        echo "{\"status\":\"$status\",\"start_time\":null,\"end_time\":null}" > "$progress_file"
    fi
}

# Функция для проверки и обновления статуса задачи
check_and_update_status() {
    local distro=$1
    local arch=$2
    local row=$3

    local current_status=$(get_status_from_progress "$distro" "$arch")

    if [[ "$current_status" != "${statuses["$distro-$arch"]}" ]]; then
        statuses["$distro-$arch"]="$current_status"
        # Получаем времена из .progress
        get_times_from_progress "$distro" "$arch"

        update_row $row "$distro" "$arch" "$current_status"
        echo "Обновлён статус для $distro-$arch: $current_status" >> "$FULL_LOG_FILE"
    fi
}

# Функция для запуска контейнера
run_container() {
    local distro=$1
    local arch=$2
    local row=$3

    local current_status=$(get_status_from_progress "$distro" "$arch")

    # Проверяем статус контейнера
    if [[ "$current_status" == "PASS" || "$current_status" == "FAIL" || "$current_status" == "WARNING" ]]; then
        echo "Контейнер $distro-$arch уже завершен со статусом $current_status, не перезапускаем его." >> "$FULL_LOG_FILE"
        return
    elif [[ "$current_status" == "TESTING" ]]; then
        echo "Контейнер $distro-$arch уже в состоянии TESTING, не вмешиваемся." >> "$FULL_LOG_FILE"
        return
    fi

 # Обновляем статус на TESTING
    update_progress_status "$distro" "$arch" "TESTING"
    statuses["$distro-$arch"]="TESTING"
    get_times_from_progress "$distro" "$arch"
    update_row ${TASK_ROW["$distro-$arch"]} "$distro" "$arch" "TESTING"

    # Создаем папку для логов текущего теста
    mkdir -p "$LOG_DIR/$distro-$arch"
    local container_log_file="$LOG_DIR/$distro-$arch/$distro-$arch.log"

    echo "Запуск теста для $distro на $arch" >> "$FULL_LOG_FILE"

    # Запуск контейнера в фоне
    {
        # Ваши команды для запуска контейнера
        docker run --rm --name "${distro//:/-}-$arch" "$distro" bash -c "uname -a && sleep $((RANDOM % 5 + 5))" >> "$container_log_file" 2>&1
        local exit_code=$?

        # Проверяем результат и обновляем статус
        if [[ $exit_code -eq 0 ]]; then
            update_progress_status "$distro" "$arch" "PASS"
        else
            update_progress_status "$distro" "$arch" "FAIL"
        fi

        # Получаем время окончания из .progress
        get_times_from_progress "$distro" "$arch"
        local elapsed_time=$(format_time ${start_times["$distro-$arch"]} ${end_times["$distro-$arch"]})

        echo "Контейнер $distro-$arch завершен со статусом ${statuses["$distro-$arch"]} за $elapsed_time." >> "$FULL_LOG_FILE"
        echo "Контейнер $distro-$arch завершен со статусом ${statuses["$distro-$arch"]} за $elapsed_time." >> "$container_log_file"

        # Обновляем строку таблицы
        update_row $row "$distro" "$arch" "${statuses["$distro-$arch"]}"

        # Фоновый процесс завершается здесь
    } &
    # Сохраняем PID запущенного процесса
    running_tasks_pids["$distro-$arch"]=$!
}




# Основной цикл тестирования
start_next_task() {
    while true; do
        # Обновляем массив запущенных задач
        update_running_tasks

        # Обновляем количество запущенных задач
        running_tasks=${#running_tasks_pids[@]}

        # Выводим в лог текущее количество запущенных задач
        echo "Текущее количество запущенных задач: $running_tasks" >> "$FULL_LOG_FILE"

        if [[ $running_tasks -lt $MAX_PARALLEL ]]; then
            for TASK in "${TASKS[@]}"; do
                distro=$(echo $TASK | cut -d'|' -f1)
                arch=$(echo $TASK | cut -d'|' -f2)

                if [[ "${statuses["$distro-$arch"]}" == "QUEUE" ]]; then
                    echo "Запуск задачи для $distro на $arch" >> "$FULL_LOG_FILE"
                    run_container "$distro" "$arch" ${TASK_ROW["$distro-$arch"]}
                    running_tasks_pids["$distro-$arch"]=$!  # Сохраняем PID
                    running_tasks=$((running_tasks + 1))
                    if [[ $running_tasks -ge $MAX_PARALLEL ]]; then
                        break
                    fi
                fi
            done
        fi

        # Обновление времени для задач в состоянии TESTING
        update_testing_time

        # Проверяем текущий статус каждой задачи и обновляем, если он изменился
        for TASK in "${TASKS[@]}"; do
            distro=$(echo $TASK | cut -d'|' -f1)
            arch=$(echo $TASK | cut -d'|' -f2)
            check_and_update_status "$distro" "$arch" ${TASK_ROW["$distro-$arch"]}
        done

        sleep 1  # Ожидание перед следующим обновлением времени

        # Проверка завершения всех задач
        all_done=true
        for TASK in "${TASKS[@]}"; do
            distro=$(echo $TASK | cut -d'|' -f1)
            arch=$(echo $TASK | cut -d'|' -f2)
            if [[ "${statuses["$distro-$arch"]}" == "QUEUE" || "${statuses["$distro-$arch"]}" == "TESTING" ]]; then
                all_done=false
                break
            fi
        done

        if [[ "$all_done" == true ]]; then
            echo "Все задачи завершены. Тестирование завершено." >> "$FULL_LOG_FILE"
            break
        fi
    done
}




# Инициализируем таблицу
init_table

# Запуск основного цикла
start_next_task
wait
