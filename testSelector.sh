#!/bin/bash

# Clear the terminal screen
clear

# Get all test scripts from the test-scripts directory
testSelector_scripts=()
for script in test-scripts/*; do
    if [[ -f "$script" && -x "$script" ]]; then
        testSelector_scripts+=("$(basename "$script")")
    fi
done

# Check if test scripts were found
if [[ ${#testSelector_scripts[@]} -eq 0 ]]; then
    echo "No executable test scripts found in the test-scripts directory."
    exit 1
fi

# Initialize selection array
testSelector_rows=${#testSelector_scripts[@]}
declare -A testSelector_selection
for ((i=0; i<testSelector_rows; i++)); do
    testSelector_selection[$i]=0
done

# Initial cursor position
testSelector_cursor=0

# Function to draw the list
testSelector_draw_list() {
    clear
    echo "Use arrow keys to move, Space to select, Enter to proceed"
    echo
    echo "[All]"
    for ((i=0; i<testSelector_rows; i++)); do
        local prefix="   "
        if [[ $testSelector_cursor -eq $((i + 1)) ]]; then
            prefix="-> "
        fi
        local state=" "
        if [[ ${testSelector_selection[$i]} -eq 1 ]]; then
            state="X"
        fi
        printf "%s[%s] %s\n" "$prefix" "$state" "${testSelector_scripts[$i]}"
    done
}

# Function to toggle selection
testSelector_toggle_selection() {
    if [[ $testSelector_cursor -eq 0 ]]; then
        # Toggle all
        local new_state=1
        [[ $(testSelector_get_global_state) -eq 1 ]] && new_state=0
        for ((i=0; i<testSelector_rows; i++)); do
            testSelector_selection[$i]=$new_state
        done
    else
        local idx=$((testSelector_cursor - 1))
        testSelector_selection[$idx]=$((1 - ${testSelector_selection[$idx]}))
    fi
}

# Function to get global selection state
testSelector_get_global_state() {
    local sum=0
    for ((i=0; i<testSelector_rows; i++)); do
        sum=$((sum + testSelector_selection[$i]))
    done
    if [[ $sum -eq $testSelector_rows ]]; then
        echo 1
    else
        echo 0
    fi
}

# Function to get selected tests
testSelector_get_selected_tests() {
    local selected_tests=()
    for ((i=0; i<testSelector_rows; i++)); do
        if [[ ${testSelector_selection[$i]} -eq 1 ]]; then
            selected_tests+=("${testSelector_scripts[$i]}")
        fi
    done
    echo "${selected_tests[@]}"
}

# Function to run the selection interface
testSelector_run() {
    testSelector_draw_list
    while true; do
        IFS= read -rsn1 key
        if [[ $key == " " ]]; then
            testSelector_toggle_selection
        elif [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key_rest
            key+="$key_rest"
            case "$key" in
                $'\x1b[A') testSelector_cursor=$((testSelector_cursor == 0 ? testSelector_rows : testSelector_cursor - 1)) ;;  # Up
                $'\x1b[B') testSelector_cursor=$((testSelector_cursor == testSelector_rows ? 0 : testSelector_cursor + 1)) ;;  # Down
            esac
        elif [[ -z $key ]]; then
            break
        fi
        testSelector_draw_list
    done
    clear
}

# If the script is run directly, start the selection interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    testSelector_run
    selected_tests=($(testSelector_get_selected_tests))
    echo "Selected tests: ${selected_tests[@]}"
fi
