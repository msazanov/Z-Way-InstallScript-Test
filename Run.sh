#!/bin/bash

# Source the checkbox.sh script to capture user selections
source "$(dirname "$0")/checkbox.sh"

# Ensure the selection process is invoked properly
distSelector_draw_table  # This will display the selection interface

# Capture selected distributions and architectures after selection
selected_distributions=($(distSelector_get_selected_distributions))
selected_architectures=($(distSelector_get_selected_architectures))

# If "All" is selected for architectures, use all available architectures
if [[ " ${selected_architectures[@]} " =~ " All " ]]; then
    selected_architectures=("armv6l" "armv7" "aarch64" "x86")
fi

# Use the selected distributions and architectures
DISTROS=("${selected_distributions[@]}")
ARCHITECTURES=("${selected_architectures[@]}")

# Now ask how many parallel builds can be run
read -p "Сколько сборок можно запускать параллельно? " MAX_PARALLEL

# Create timestamp for log folder
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="install_test_results/$TIMESTAMP"
FULL_LOG_FILE="$LOG_DIR/Full.log"

# Clear screen on exit
trap "tput reset; exit" SIGINT SIGTERM

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Create or clear the full log file
echo "Полные логи выполнения" > "$FULL_LOG_FILE"

# Function to clear the current line in the terminal
clear_line() {
    tput el
}

# Function to move the cursor to a specific line in the table and update it
update_row() {
    local row=$1
    local distro=$2
    local arch=$3
    local status=$4
    local time=$5

    # Перемещаем курсор в нужную строку, очищаем строку и выводим обновленные данные
    tput cup $row 0
    clear_line
    printf "%-20s | %-10s | %-10s | %-8s\n" "$distro" "$arch" "$status" "$time"
}

update_testing_time() {
    for TASK in "${TASKS[@]}"; do
        DISTRO=$(echo $TASK | cut -d'|' -f1)
        ARCH=$(echo $TASK | cut -d'|' -f2)
        # Обновляем время только для задач в статусе TESTING
        if [[ "${statuses["$DISTRO-$ARCH"]}" == "TESTING" ]]; then
            elapsed_time=$(format_time ${start_times["$DISTRO-$ARCH"]})
            update_row ${TASK_ROW["$DISTRO-$ARCH"]} "$DISTRO" "$ARCH" "TESTING" "$elapsed_time"
        fi
    done
}

# Function to clear the current line in the terminal
clear_line() {
    tput el
}

# Function to initialize the table
init_table() {
    tput clear
    tput cup 0 0
    echo "Дистрибутив         | Архитектура | Статус     | Время"
    echo "------------------------------------------------------"
    local line=2
    for TASK in "${TASKS[@]}"; do
        DISTRO=$(echo $TASK | cut -d'|' -f1)
        ARCH=$(echo $TASK | cut -d'|' -f2)
        update_row $line "$DISTRO" "$ARCH" "QUEUE" "00:00:00"
        TASK_ROW["$DISTRO-$ARCH"]=$line  # Store row number for later updates
        line=$((line + 1))
    done
}


check_and_update_status() {
    local distro=$1
    local arch=$2
    local row=$3

    local progress_file="$LOG_DIR/$distro-$arch/.progress"
    local current_status=$(get_status_from_progress "$distro" "$arch")

    # Если статус изменился на PASS, FAIL или WARNING, обновляем массив и строку таблицы
    if [[ "$current_status" != "${statuses["$distro-$arch"]}" ]]; then
        statuses["$distro-$arch"]="$current_status"
        elapsed_time=$(format_time ${start_times["$distro-$arch"]})
        update_row $row "$distro" "$arch" "$current_status" "$elapsed_time"
        echo "Обновлён статус для $distro-$arch: $current_status" >> "$FULL_LOG_FILE"
    fi
}


# Function to format elapsed time
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

# Initialize status for each test
declare -A statuses
declare -A start_times
declare -A completed_tasks
declare -A TASK_ROW  # Store the row number for each task
TASKS=()

# Заполняем массив с заданиями для тестирования
for ARCH in "${ARCHITECTURES[@]}"; do
    for DISTRO in "${DISTROS[@]}"; do
        TASKS+=("$DISTRO|$ARCH")
        statuses["$DISTRO-$ARCH"]="QUEUE"
    done
done

# Function to check if container exists and remove it
remove_existing_container() {
    local container_name=$1

    if [ "$(docker ps -a -q -f name="^/${container_name}$")" ]; then
        echo "Контейнер с именем $container_name уже существует. Удаляем контейнер..." >> "$FULL_LOG_FILE"
        docker rm -f "$container_name" >> "$FULL_LOG_FILE" 2>&1
    fi
}

# Function to update the .progress file with error redirection to log
update_progress_status() {
    local distro=$1
    local arch=$2
    local progress_file="$LOG_DIR/$distro-$arch/.progress"
    local log_dir="$LOG_DIR/$distro-$arch"

    # Создаем директорию, если она не существует
    mkdir -p "$log_dir" 2>> "$FULL_LOG_FILE"

    # Обновляем файл .progress и перенаправляем ошибки в лог
    echo "$3" > "$progress_file" 2>> "$FULL_LOG_FILE"
}

# Function to read the status from .progress file
get_status_from_progress() {
    local distro=$1
    local arch=$2
    local progress_file="$LOG_DIR/$distro-$arch/.progress"

    # Если файл .progress не существует, возвращаем статус QUEUE
    if [[ ! -f "$progress_file" ]]; then
        echo "QUEUE"
    else
        cat "$progress_file" 2>> "$FULL_LOG_FILE"
    fi
}


run_container() {
    local distro=$1
    local arch=$2
    local row=$3

    local progress_file="$LOG_DIR/$distro-$arch/.progress"
    local current_status=$(get_status_from_progress "$distro" "$arch")

    # Проверяем статус контейнера
    if [[ "$current_status" == "PASS" || "$current_status" == "FAIL" || "$current_status" == "WARNING" ]]; then
        echo "Контейнер $distro-$arch уже завершен со статусом $current_status, не перезапускаем его." >> "$FULL_LOG_FILE"
        return
    elif [[ "$current_status" == "TESTING" ]]; then
        echo "Контейнер $distro-$arch уже в состоянии TESTING, не вмешиваемся." >> "$FULL_LOG_FILE"
        return
    fi

    # Если статус QUEUE, проверяем количество запущенных задач
    running_tasks=$(jobs -r | wc -l)
    if [[ $running_tasks -ge $MAX_PARALLEL ]]; then
        echo "Максимальное количество задач запущено, откладываем запуск $distro-$arch." >> "$FULL_LOG_FILE"
        return
    fi

    # Обновляем статус на TESTING
    update_progress_status "$distro" "$arch" "TESTING"
    statuses["$distro-$arch"]="TESTING"
    start_times["$distro-$arch"]=$(date +%s)

    # Замена двоеточия на дефис в имени контейнера
    local safe_container_name="${distro//:/-}-$arch"

    # Обновляем строку таблицы сразу после смены статуса
    update_row ${TASK_ROW["$distro-$arch"]} "$distro" "$arch" "TESTING" "00:00:00"

    # Создаем папку для логов текущего теста
    mkdir -p "$LOG_DIR/$distro-$arch"
    local container_log_file="$LOG_DIR/$distro-$arch/$distro-$arch.log"

    echo "Запуск теста для $distro на $arch" >> "$FULL_LOG_FILE"
    echo "Команда: docker run --rm --name \"$safe_container_name\" \"$distro\"" >> "$container_log_file"

    # Запуск контейнера с командой, которая генерирует вывод (например, uname -a)
    docker run --rm --name "$safe_container_name" "$distro" bash -c "uname -a && sleep $((RANDOM % 5 + 5))" >> "$container_log_file" 2>&1
    
    # Проверяем результат и обновляем статус
    if [[ $? -eq 0 ]]; then
        update_progress_status "$distro" "$arch" "PASS"
        statuses["$distro-$arch"]="PASS"
        echo "Контейнер $distro-$arch успешно завершен." >> "$FULL_LOG_FILE"
        echo "Контейнер $distro-$arch успешно завершен." >> "$container_log_file"
    else
        update_progress_status "$distro" "$arch" "FAIL"
        statuses["$distro-$arch"]="FAIL"
        echo "Контейнер $distro-$arch завершился с ошибкой." >> "$FULL_LOG_FILE"
        echo "Контейнер $distro-$arch завершился с ошибкой." >> "$container_log_file"
    fi

    # Обновляем строку таблицы
    elapsed_time=$(format_time ${start_times["$distro-$arch"]})
    update_row $row "$distro" "$arch" "${statuses["$distro-$arch"]}" "$elapsed_time"
}





# Function to check the status from the .progress file and update the status if necessary
check_and_update_status() {
    local distro=$1
    local arch=$2
    local row=$3

    local progress_file="$LOG_DIR/$distro-$arch/.progress"
    local current_status=$(get_status_from_progress "$distro" "$arch")

    # Если статус изменился на PASS, FAIL или WARNING, обновляем массив и строку таблицы
    if [[ "$current_status" != "${statuses["$distro-$arch"]}" ]]; then
        statuses["$distro-$arch"]="$current_status"
        elapsed_time=$(format_time ${start_times["$distro-$arch"]})
        update_row $row "$distro" "$arch" "$current_status" "$elapsed_time"
        echo "Обновлён статус для $distro-$arch: $current_status" >> "$FULL_LOG_FILE"
    fi
}

# Main testing loop: управляющий параллельными сборками
start_next_task() {
    local line=2  # Строки начинаются после заголовка

    while true; do
        running_tasks=$(jobs -r | wc -l)

        # Выводим в лог текущее количество запущенных задач
        echo "Текущее количество запущенных задач: $running_tasks" >> "$FULL_LOG_FILE"
        
        if [[ $running_tasks -lt $MAX_PARALLEL ]]; then
            for TASK in "${TASKS[@]}"; do
                DISTRO=$(echo $TASK | cut -d'|' -f1)
                ARCH=$(echo $TASK | cut -d'|' -f2)

                # Проверяем, был ли контейнер уже завершён со статусом PASS, FAIL, или WARNING
                if [[ "${statuses["$DISTRO-$ARCH"]}" == "PASS" || "${statuses["$DISTRO-$ARCH"]}" == "FAIL" || "${statuses["$DISTRO-$ARCH"]}" == "WARNING" ]]; then
                    continue  # Переходим к следующей задаче, если контейнер завершен
                fi

                # Проверяем, чтобы контейнеры с статусом QUEUE были запущены
                if [[ "${statuses["$DISTRO-$ARCH"]}" == "QUEUE" ]]; then
                    echo "Запуск задачи для $DISTRO на $ARCH" >> "$FULL_LOG_FILE"
                    run_container "$DISTRO" "$ARCH" ${TASK_ROW["$DISTRO-$ARCH"]} &
                    running_tasks=$(jobs -r | wc -l)
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
            DISTRO=$(echo $TASK | cut -d'|' -f1)
            ARCH=$(echo $TASK | cut -d'|' -f2)
            check_and_update_status "$DISTRO" "$ARCH" ${TASK_ROW["$DISTRO-$ARCH"]}
        done

        sleep 1  # Ожидание перед следующим обновлением времени

        # Проверка завершения всех задач: если все в статусе PASS, FAIL, или WARNING
        all_done=true
        for TASK in "${TASKS[@]}"; do
            DISTRO=$(echo $TASK | cut -d'|' -f1)
            ARCH=$(echo $TASK | cut -d'|' -f2)

            # Если есть хотя бы одна задача в статусе QUEUE или TESTING, продолжаем тест
            if [[ "${statuses["$DISTRO-$ARCH"]}" == "QUEUE" || "${statuses["$DISTRO-$ARCH"]}" == "TESTING" ]]; then
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

# Запуск первого набора задач
start_next_task
wait
