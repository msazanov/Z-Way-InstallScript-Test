#!/bin/bash

# Maximum length of distribution and architecture names
MAX_DISTRO_LENGTH=15
MAX_ARCH_LENGTH=7

# Get all Dockerfiles and extract distributions
distributions=()
for dockerfile in Dockerfile.*; do
    distro=$(grep -i '^FROM' "$dockerfile" | awk '{print $2}')
    distributions+=("${distro:0:$MAX_DISTRO_LENGTH}")
done

# Architectures for testing
architectures=("All" "armv6l" "armv7" "aarch64" "x86")

# Initialize table with empty values
rows=${#distributions[@]}
columns=${#architectures[@]}
declare -A table
for ((i=0; i<$rows; i++)); do
    for ((j=1; j<$columns; j++)); do
        table[$i,$j]=0
    done
done

# Initial cursor position
cursor_x=-1  # Start with the global row
cursor_y=1   # Start with the first non-global column

# Function to draw a cell
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

# Function to toggle the entire table state
distSelector_toggle_entire_table() {
    local new_state=1
    [[ $(distSelector_get_global_toggle_state) == "checked" ]] && new_state=0

    for ((i=0; i<$rows; i++)); do
        for ((j=1; j<$columns; j++)); do
            table[$i,$j]=$new_state
        done
    done
}

# Function to check the state of a row or column
distSelector_get_toggle_state() {
    local index=$1
    local type=$2
    local sum=0
    local count=$((type == "row" ? columns - 1 : rows))

    for ((j=1; j<$columns; j++)); do
        if [[ $type == "row" ]]; then
            sum=$((sum + table[$index,$j]))
        else
            sum=$((sum + table[$j,$index]))
        fi
    done

    if [[ $sum -eq 0 ]]; then
        echo "empty"
    elif [[ $sum -eq $count ]]; then
        echo "checked"
    else
        echo "tilde"
    fi
}

# Function to toggle the state of a row or column
distSelector_toggle_row_or_column() {
    local index=$1
    local type=$2
    local new_state=0
    [[ $(distSelector_get_toggle_state $index $type) == "empty" ]] && new_state=1

    if [[ $type == "row" ]]; then
        for ((j=1; j<$columns; j++)); do
            table[$index,$j]=$new_state
        done
    else
        for ((i=0; i<$rows; i++)); do
            table[$i,$index]=$new_state
        done
    fi
}

# Function to draw the header
distSelector_draw_header() {
    tput cup 0 0
    tput el  # Clear the line
    echo "Use arrow keys to move, Space to select, Enter to proceed"
    tput cup 1 0
    tput el  # Clear the line
    printf "%-${MAX_DISTRO_LENGTH}s |" " "
    for arch in "${architectures[@]}"; do
        printf "%-7s|" "${arch:0:$MAX_ARCH_LENGTH}"
    done
}

# Function to draw the global checkboxes row
distSelector_draw_global_checkboxes() {
    tput cup 2 0
    tput el  # Clear the line
    printf "%-${MAX_DISTRO_LENGTH}s |" "All"
    distSelector_draw_cell "$(distSelector_get_global_toggle_state)" $((cursor_x == -1 && cursor_y == 0))
    printf "|"
    for ((j=1; j<$columns; j++)); do
        distSelector_draw_cell "$(distSelector_get_toggle_state $j column)" $((cursor_x == -1 && cursor_y == j))
        printf "|"
    done
    echo
}

# Function to draw the table
distSelector_draw_table() {
    distSelector_draw_header
    distSelector_draw_global_checkboxes
    for ((i=0; i<$rows; i++)); do
        tput cup $((i+3)) 0
        tput el
        printf "%-${MAX_DISTRO_LENGTH}s |" "${distributions[$i]}"
        distSelector_draw_cell "$(distSelector_get_toggle_state $i row)" $((cursor_x == i && cursor_y == 0))
        printf "|"
        for ((j=1; j<$columns; j++)); do
            if [[ ${table[$i,$j]} -eq 1 ]]; then
                distSelector_draw_cell "checked" $((cursor_x == i && cursor_y == j))
            else
                distSelector_draw_cell "empty" $((cursor_x == i && cursor_y == j))
            fi
            printf "|"
        done
        echo
    done
}

# Function to check the state of the entire table
distSelector_get_global_toggle_state() {
    local sum=0
    local total_cells=$((rows * (columns - 1)))

    for ((i=0; i<$rows; i++)); do
        for ((j=1; j<$columns; j++)); do
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

# Function to handle selection
distSelector_toggle_selection() {
    if [[ $cursor_x -eq -1 && $cursor_y -eq 0 ]]; then
        distSelector_toggle_entire_table
    elif [[ $cursor_x -eq -1 ]]; then
        distSelector_toggle_row_or_column $cursor_y column
    elif [[ $cursor_y -eq 0 ]]; then
        distSelector_toggle_row_or_column $cursor_x row
    else
        table[$cursor_x,$cursor_y]=$((1 - ${table[$cursor_x,$cursor_y]}))
    fi
}

# Main loop
distSelector_draw_table
while true; do
    IFS= read -rsn1 key
    if [[ $key == " " ]]; then
        distSelector_toggle_selection
    elif [[ $key == $'\x1b' ]]; then
        read -rsn2 key
        case "$key" in
            "[A") cursor_x=$((cursor_x == -1 ? rows - 1 : cursor_x - 1)) ;;
            "[B") cursor_x=$((cursor_x == rows - 1 ? -1 : cursor_x + 1)) ;;
            "[D") cursor_y=$((cursor_y == 0 ? columns - 1 : cursor_y - 1)) ;;
            "[C") cursor_y=$((cursor_y == columns - 1 ? 0 : cursor_y + 1)) ;;
        esac
    elif [[ -z $key ]]; then
        break
    fi
    distSelector_draw_table
done

# Final output
clear
echo "Selected options:"
for ((i=0; i<$rows; i++)); do
    for ((j=1; j<$columns; j++)); do
        [[ ${table[$i,$j]} -eq 1 ]] && echo "Test on ${distributions[$i]} for ${architectures[$j]}"
    done
done
