#!/bin/bash
clear
# Максимальная длина названия дистрибутива и архитектуры
MAX_DISTRO_LENGTH=15
MAX_ARCH_LENGTH=7

# Получаем все Dockerfile и извлекаем дистрибутивы
distributions=()
for dockerfile in Dockerfile.*; do
    distro=$(grep -i '^FROM' "$dockerfile" | awk '{print $2}')
    distributions+=("${distro:0:$MAX_DISTRO_LENGTH}")
done

# Архитектуры для тестирования (убрали "All" из списка)
architectures=("armv6l" "armv7" "aarch64" "x86")

# Инициализируем таблицу пустыми значениями
rows=${#distributions[@]}
columns=${#architectures[@]}
declare -A table
for ((i=0; i<$rows; i++)); do
    for ((j=0; j<$columns; j++)); do
        table[$i,$j]=0
    done
done

# Начальная позиция курсора
cursor_x=-1  # -1 соответствует глобальной строке "All"
cursor_y=0   # 0 соответствует глобальному столбцу "All"

# Функция для отрисовки ячейки
distSelector_draw_cell() {
    local state=$1
    local has_cursor=$2
    local content="       "

    case $state in
        "checked") content="   X   " ;;
        "tilde")   content="   ~   " ;;
    esac

    [[ $has_cursor -eq 1 ]] && printf "[%s]" "${content:1:5}" || printf "%s" "$content"
}

# Функция для получения выбранных дистрибутивов
distSelector_get_selected_distributions() {
    selected_distributions=()
    for ((i=0; i<$rows; i++)); do
        selected=false
        for ((j=0; j<$columns; j++)); do
            if [[ ${table[$i,$j]} -eq 1 ]]; then
                selected=true
                break
            fi
        done
        if $selected; then
            selected_distributions+=("${distributions[$i]}")
        fi
    done
    echo "${selected_distributions[@]}"
}

# Функция для получения выбранных архитектур
distSelector_get_selected_architectures() {
    selected_architectures=()
    for ((j=0; j<$columns; j++)); do
        selected=false
        for ((i=0; i<$rows; i++)); do
            if [[ ${table[$i,$j]} -eq 1 ]]; then
                selected=true
                break
            fi
        done
        if $selected; then
            selected_architectures+=("${architectures[$j]}")
        fi
    done
    echo "${selected_architectures[@]}"
}

# Функция для запуска интерфейса выбора
distSelector_run() {
    clear
    distSelector_draw_table
    while true; do
        IFS= read -rsn1 key
        if [[ $key == " " ]]; then
            distSelector_toggle_selection
        elif [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key_rest
            key+="$key_rest"
            case "$key" in
                $'\x1b[A') cursor_x=$((cursor_x == -1 ? rows - 1 : cursor_x - 1)) ;;
                $'\x1b[B') cursor_x=$((cursor_x == rows - 1 ? -1 : cursor_x + 1)) ;;
                $'\x1b[D') cursor_y=$((cursor_y == 0 ? columns : cursor_y - 1)) ;;
                $'\x1b[C') cursor_y=$((cursor_y == columns ? 0 : cursor_y + 1)) ;;
            esac
        elif [[ -z $key ]]; then
            break
        fi
        distSelector_draw_table
    done
    clear
}

# Функция для переключения состояния всей таблицы
distSelector_toggle_entire_table() {
    local new_state=1
    [[ $(distSelector_get_global_toggle_state) == "checked" ]] && new_state=0

    for ((i=0; i<$rows; i++)); do
        for ((j=0; j<$columns; j++)); do
            table[$i,$j]=$new_state
        done
    done
}

# Функция для получения состояния строки или столбца
distSelector_get_toggle_state() {
    local index=$1
    local type=$2
    local sum=0
    local count
    if [[ $type == "row" ]]; then
        count=$columns
    else
        count=$rows
    fi

    # Проверяем состояние глобальной строки/столбца
    if [[ $type == "row" && $index -eq -1 ]] || [[ $type == "column" && $index -eq -1 ]]; then
        echo "$(distSelector_get_global_toggle_state)"
        return
    fi

    if [[ $type == "row" ]]; then
        for ((j=0; j<$columns; j++)); do
            sum=$((sum + table[$index,$j]))
        done
    else
        for ((i=0; i<$rows; i++)); do
            sum=$((sum + table[$i,$index]))
        done
    fi

    if [[ $sum -eq 0 ]]; then
        echo "empty"
    elif [[ $sum -eq $count ]]; then
        echo "checked"
    else
        echo "tilde"
    fi
}

distSelector_get_global_toggle_state() {
    local sum=0
    local total_cells=$((rows * columns))

    # Проверка всех ячеек в таблице
    for ((i=0; i<$rows; i++)); do
        for ((j=0; j<$columns; j++)); do
            sum=$((sum + table[$i,$j]))
        done
    done

    # Если все ячейки равны 0, то возвращаем состояние "empty"
    if [[ $sum -eq 0 ]]; then
        echo "empty"
        return
    fi

    # Если все ячейки выбраны (равны 1), то возвращаем состояние "checked"
    if [[ $sum -eq $total_cells ]]; then
        echo "checked"
        return
    fi

    # Если есть смешанные состояния, возвращаем "tilde"
    echo "tilde"
}


# Функция для переключения состояния строки или столбца
distSelector_toggle_row_or_column() {
    local index=$1
    local type=$2
    local new_state=0
    [[ $(distSelector_get_toggle_state $index $type) == "empty" ]] && new_state=1

    if [[ $type == "row" ]]; then
        for ((j=0; j<$columns; j++)); do
            table[$index,$j]=$new_state
        done
    else
        for ((i=0; i<$rows; i++)); do
            table[$i,$index]=$new_state
        done
    fi
}

# Функция для отрисовки заголовка
distSelector_draw_header() {
    tput cup 0 0
    tput el  # Очистка строки
    echo "Use arrow keys to move, Space to select, Enter to proceed"
    tput cup 1 0
    tput el  # Очистка строки
    printf "%-${MAX_DISTRO_LENGTH}s |" " "  # Добавляем пустую колонку перед архитектурами
    printf "%-7s|" "All"  # Добавляем "All" в заголовок
    for arch in "${architectures[@]}"; do
        printf "%-7s|" "${arch:0:$MAX_ARCH_LENGTH}"
    done
}

# Функция для отрисовки глобальной строки чекбоксов
distSelector_draw_global_checkboxes() {
    tput cup 2 0
    tput el  # Очистка строки
    printf "%-${MAX_DISTRO_LENGTH}s |" "All"
    distSelector_draw_cell "$(distSelector_get_global_toggle_state)" $((cursor_x == -1 && cursor_y == 0))
    printf "|"
    for ((j=0; j<$columns; j++)); do
        distSelector_draw_cell "$(distSelector_get_toggle_state $j column)" $((cursor_x == -1 && cursor_y == j+1))
        printf "|"
    done
    echo
}

# Функция для отрисовки таблицы
distSelector_draw_table() {
    distSelector_draw_header
    distSelector_draw_global_checkboxes
    for ((i=0; i<$rows; i++)); do
        tput cup $((i+3)) 0
        tput el
        printf "%-${MAX_DISTRO_LENGTH}s |" "${distributions[$i]}"
        distSelector_draw_cell "$(distSelector_get_toggle_state $i row)" $((cursor_x == i && cursor_y == 0))
        printf "|"
        for ((j=0; j<$columns; j++)); do
            if [[ ${table[$i,$j]} -eq 1 ]]; then
                distSelector_draw_cell "checked" $((cursor_x == i && cursor_y == j+1))
            else
                distSelector_draw_cell "empty" $((cursor_x == i && cursor_y == j+1))
            fi
            printf "|"
        done
        echo
    done
}

# Функция для получения глобального состояния таблицы
distSelector_get_global_toggle_state() {
    local sum=0
    local total_cells=$((rows * columns))

    for ((i=0; i<$rows; i++)); do
        for ((j=0; j<$columns; j++)); do
            sum=$((sum + table[$i,$j]))
        done
    done

    if [[ $sum -eq 0 ]]; then
        echo "empty"
    elif [[ $sum -eq $total_cells ]]; then
        echo "checked"
    else
        echo "tilde"
    fi
}

# Функция для обработки выбора
distSelector_toggle_selection() {
    if [[ $cursor_x -eq -1 && $cursor_y -eq 0 ]]; then
        distSelector_toggle_entire_table
    elif [[ $cursor_x -eq -1 ]]; then
        distSelector_toggle_row_or_column $((cursor_y - 1)) column
    elif [[ $cursor_y -eq 0 ]]; then
        distSelector_toggle_row_or_column $cursor_x row
    else
        table[$cursor_x,$((cursor_y - 1))]=$((1 - ${table[$cursor_x,$((cursor_y - 1))]}))
    fi

    distSelector_draw_global_checkboxes
}



clear
# Если скрипт запускается напрямую, запускаем интерфейс выбора
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    distSelector_run
fi