#!/bin/bash

# Include the checkbox and testSelector scripts
source "$(dirname "$0")/checkbox.sh"
source "$(dirname "$0")/testSelector.sh"

# Run the distribution and architecture selection interface
distSelector_run

# Get selected distributions and architectures
selected_distributions=($(distSelector_get_selected_distributions))
selected_architectures=($(distSelector_get_selected_architectures))

# Check selections
if [[ ${#selected_distributions[@]} -eq 0 || ${#selected_architectures[@]} -eq 0 ]]; then
    echo "No distributions or architectures selected. Exiting."
    exit 1
fi

# Run the test selection interface
testSelector_run

# Get selected tests
selected_tests=($(testSelector_get_selected_tests))

# Check if tests are selected
if [[ ${#selected_tests[@]} -eq 0 ]]; then
    echo "No tests selected. Exiting."
    exit 1
fi

# Ask for the number of parallel builds
read -p "How many builds can be run in parallel? (default 4) " MAX_PARALLEL

# Validate and set MAX_PARALLEL
if [[ -z "$MAX_PARALLEL" ]]; then
    MAX_PARALLEL=4
fi
if ! [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL" -lt 1 ]]; then
    echo "Invalid value, setting MAX_PARALLEL=4"
    MAX_PARALLEL=4
fi

# Create log directories and files
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="install_test_results/$TIMESTAMP"
FULL_LOG_FILE="$LOG_DIR/Full.log"
mkdir -p "$LOG_DIR"
echo "Full execution logs" > "$FULL_LOG_FILE"

# Initialize arrays
declare -A statuses
declare -A start_times
declare -A end_times
declare -A TASK_ROW
declare -A running_tasks_pids  # Array to track running tasks
TASKS=()

# Fill TASKS and initialize statuses
for arch in "${selected_architectures[@]}"; do
    for distro in "${selected_distributions[@]}"; do
        TASKS+=("$distro|$arch")
        key="$distro-$arch"
        statuses["$key"]="QUEUE"
    done
done

# Function to clear the current line in the terminal
clear_line() {
    tput el      # Clear from cursor to end of line
    tput el1     # Clear from beginning of line to cursor
}

# Function to format time
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

# Function to get elapsed time for a task
get_elapsed_time() {
    local distro="$1"
    local arch="$2"
    local key="$distro-$arch"
    local status=${statuses["$key"]}
    local start_time=${start_times["$key"]}
    local end_time=${end_times["$key"]}

    if [[ "$status" == "QUEUE" || -z "$start_time" ]]; then
        echo "00:00:00"
    elif [[ "$status" == TESTING* ]]; then
        format_time "$start_time"
    elif [[ "$status" == PASS* || "$status" == FAIL* || "$status" == WARNING* ]]; then
        format_time "$start_time" "$end_time"
    else
        echo "00:00:00"
    fi
}

# Function to update a row in the table
update_row() {
    local row="$1"
    local distro="$2"
    local arch="$3"
    local status="$4"
    local key="$distro-$arch"

    # Get elapsed time
    local elapsed_time=$(get_elapsed_time "$distro" "$arch")

    # Determine color based on status
    local color_reset="\e[0m"
    local color
    if [[ "$status" == PASS* ]]; then
        color="\e[32m"  # Green
    elif [[ "$status" == FAIL* ]]; then
        color="\e[31m"  # Red
    elif [[ "$status" == TESTING* ]]; then
        color="\e[33m"  # Yellow
    elif [[ "$status" == QUEUE* ]]; then
        color="\e[34m"  # Blue
    else
        color="\e[0m"   # Reset color
    fi

    # Move cursor to the correct row, clear the line, and print updated data
    tput cup "$row" 0
    clear_line

    # Calculate terminal width
    local term_width=$(tput cols)

    # Form the line for output
    local line
    line=$(printf "%-20s | %-12s | ${color}%-15s${color_reset} | %-8s" "$distro" "$arch" "$status" "$elapsed_time")

    # Pad the line with spaces to cover any previous output
    printf "%-${term_width}s\n" "$line"
}

# Function to update the array of running tasks
update_running_tasks() {
    for task in "${!running_tasks_pids[@]}"; do
        pid=${running_tasks_pids["$task"]}
        if ! kill -0 "$pid" 2>/dev/null; then
            # Process has finished, remove it from the array
            unset running_tasks_pids["$task"]
        fi
    done
}

# Function to initialize the table
init_table() {
    tput clear
    tput cup 0 0
    echo "Дистрибутив         | Архитектура  | Статус            | Время"
    echo "---------------------------------------------------------------"
    local line=2
    for TASK in "${TASKS[@]}"; do
        distro=$(echo "$TASK" | cut -d'|' -f1)
        arch=$(echo "$TASK" | cut -d'|' -f2)
        update_row "$line" "$distro" "$arch" "QUEUE"
        TASK_ROW["$distro-$arch"]=$line  # Store row number for later updates
        line=$((line + 1))
    done
}

# Function to update testing time for tasks in TESTING state
update_testing_time() {
    for TASK in "${TASKS[@]}"; do
        distro=$(echo "$TASK" | cut -d'|' -f1)
        arch=$(echo "$TASK" | cut -d'|' -f2)
        key="$distro-$arch"
        # Update time only for tasks in status TESTING*
        if [[ "${statuses["$key"]}" == TESTING* ]]; then
            update_row "${TASK_ROW["$key"]}" "$distro" "$arch" "${statuses["$key"]}"
        fi
    done
}

# Function to read status from the .progress file
get_status_from_progress() {
    local distro=$1
    local arch=$2
    local key="$distro-$arch"
    local progress_file="$LOG_DIR/$key/.progress"

    if [[ ! -f "$progress_file" ]]; then
        echo "QUEUE"
    else
        local status
        status=$(jq -r '.status' "$progress_file")
        echo "$status"
    fi
}

# Function to get times from .progress
get_times_from_progress() {
    local distro=$1
    local arch=$2
    local key="$distro-$arch"
    local progress_file="$LOG_DIR/$key/.progress"

    if [[ -f "$progress_file" ]]; then
        local start_time
        local end_time
        start_time=$(jq -r '.start_time' "$progress_file")
        end_time=$(jq -r '.end_time' "$progress_file")

        # Update arrays
        if [[ "$start_time" != "null" ]]; then
            start_times["$key"]=$start_time
        fi
        if [[ "$end_time" != "null" ]]; then
            end_times["$key"]=$end_time
        fi
    fi
}

# Function to update status in the .progress file
update_progress_status() {
    local distro=$1
    local arch=$2
    local status=$3
    local key="$distro-$arch"
    local progress_file="$LOG_DIR/$key/.progress"
    local log_dir="$LOG_DIR/$key"

    # Create directory if it doesn't exist
    mkdir -p "$log_dir" 2>> "$FULL_LOG_FILE"

    # Get current time
    local current_time
    current_time=$(date +%s)

    # If status starts with TESTING, record start time
    if [[ "$status" == TESTING* ]]; then
        # Extract the current test index from the status
        local test_info
        test_info=$(echo "$status" | grep -oP '\((.*?)\)')
        local test_index
        test_index=$(echo "$test_info" | grep -oP '^\(\K[0-9]+(?=/)')
        if [[ -n "$test_index" && -z "${start_times["$key"]}" ]]; then
            echo "{\"status\":\"TESTING\",\"start_time\":$current_time,\"end_time\":null}" > "$progress_file"
        else
            # Update only the status
            jq --arg status "$status" '.status = $status' "$progress_file" > "${progress_file}.tmp" && mv "${progress_file}.tmp" "$progress_file"
        fi
    elif [[ "$status" == PASS* || "$status" == FAIL* || "$status" == WARNING* ]]; then
        # Update end time
        jq --arg status "$status" --argjson end_time "$current_time" '.status = $status | .end_time = $end_time' "$progress_file" > "${progress_file}.tmp" && mv "${progress_file}.tmp" "$progress_file"
    else
        # For other statuses
        jq --arg status "$status" '.status = $status | .start_time = null | .end_time = null' "$progress_file" > "${progress_file}.tmp" && mv "${progress_file}.tmp" "$progress_file"
    fi
}

# Function to check and update task status
check_and_update_status() {
    local distro="$1"
    local arch="$2"
    local row="$3"
    local key="$distro-$arch"

    local current_status
    current_status=$(get_status_from_progress "$distro" "$arch")

    if [[ "$current_status" != "${statuses["$key"]}" ]]; then
        statuses["$key"]="$current_status"
        # Get times from .progress
        get_times_from_progress "$distro" "$arch"

        update_row "$row" "$distro" "$arch" "$current_status"
        echo "Updated status for $distro-$arch: $current_status" >> "$FULL_LOG_FILE"
    fi
}

# Function to run the container and execute tests
run_container() {
    local distro="$1"
    local arch="$2"
    local row="$3"
    local key="$distro-$arch"

    # Check container status
    local current_status
    current_status=$(get_status_from_progress "$distro" "$arch")

    # Update status to TESTING if it's in QUEUE
    if [[ "$current_status" == "QUEUE" ]]; then
        update_progress_status "$distro" "$arch" "TESTING(0/${#selected_tests[@]})"
        statuses["$key"]="TESTING(0/${#selected_tests[@]})"
        get_times_from_progress "$distro" "$arch"
        update_row "$row" "$distro" "$arch" "${statuses["$key"]}"
    else
        echo "Container $distro-$arch is already in status $current_status. Skipping." >> "$FULL_LOG_FILE"
        return
    fi

    # Create log directory for the current test
    mkdir -p "$LOG_DIR/$key"
    local container_log_file="$LOG_DIR/$key/$key.log"

    echo "Starting tests for $distro on $arch" >> "$FULL_LOG_FILE"

    # Run the container in the background
    {
        # Generate a temporary directory for test scripts
        tmp_dir=$(mktemp -d)
        cp "$(dirname "$0")"/test-scripts/* "$tmp_dir/"

        # Initialize variables
        test_index=0
        fail_count=0

        # Loop over selected_tests
        for test_script in "${selected_tests[@]}"; do
            test_index=$((test_index + 1))
            update_progress_status "$distro" "$arch" "TESTING($test_index/${#selected_tests[@]})"
            statuses["$key"]="TESTING($test_index/${#selected_tests[@]})"

            # Log the start of the test with separators
            echo "############################################" >> "$container_log_file"
            echo "### Running test $test_index/${#selected_tests[@]}: $test_script" >> "$container_log_file"
            echo "############################################" >> "$container_log_file"

            # Also log to FULL_LOG_FILE
            echo "############################################" >> "$FULL_LOG_FILE"
            echo "### Running test $test_index/${#selected_tests[@]}: $test_script" >> "$FULL_LOG_FILE"
            echo "############################################" >> "$FULL_LOG_FILE"

            # Execute the test script inside the container
            docker run --rm --name "${distro//:/-}-$arch-$(uuidgen)" -v "$tmp_dir":/tests "$distro" bash -c "/tests/$test_script" >> "$container_log_file" 2>&1
            exit_code=$?

            # Log the end of the test with separators
            echo "### Test $test_index/${#selected_tests[@]} completed with exit code $exit_code" >> "$container_log_file"
            echo "############################################" >> "$container_log_file"
            echo >> "$container_log_file"

            echo "### Test $test_index/${#selected_tests[@]} completed with exit code $exit_code" >> "$FULL_LOG_FILE"
            echo "############################################" >> "$FULL_LOG_FILE"
            echo >> "$FULL_LOG_FILE"

            if [[ $exit_code -ne 0 ]]; then
                fail_count=$((fail_count + 1))
            fi
        done

        # Determine the final status
        if [[ $fail_count -eq 0 ]]; then
            final_status="PASS(${#selected_tests[@]}/${#selected_tests[@]})"
        else
            final_status="FAIL($fail_count/${#selected_tests[@]})"
        fi

        update_progress_status "$distro" "$arch" "$final_status"
        statuses["$key"]="$final_status"

        # Get end times from .progress
        get_times_from_progress "$distro" "$arch"
        local elapsed_time
        elapsed_time=$(format_time "${start_times["$key"]}" "${end_times["$key"]}")

        echo "Container $distro-$arch completed with status ${statuses["$key"]} in $elapsed_time." >> "$FULL_LOG_FILE"
        echo "Container $distro-$arch completed with status ${statuses["$key"]} in $elapsed_time." >> "$container_log_file"

        # Remove temporary directory
        rm -rf "$tmp_dir"

        # Background process ends here
    } &

    # Save the PID of the started process
    running_tasks_pids["$key"]=$!
}

# Function to start the next tasks
start_next_task() {
    while true; do
        # Update the array of running tasks
        update_running_tasks

        # Update the number of running tasks
        running_tasks=${#running_tasks_pids[@]}

        # Log the current number of running tasks
        echo "Current number of running tasks: $running_tasks" >> "$FULL_LOG_FILE"

        if [[ $running_tasks -lt $MAX_PARALLEL ]]; then
            for TASK in "${TASKS[@]}"; do
                distro=$(echo "$TASK" | cut -d'|' -f1)
                arch=$(echo "$TASK" | cut -d'|' -f2)
                key="$distro-$arch"

                if [[ "${statuses["$key"]}" == "QUEUE" ]]; then
                    echo "Starting task for $distro on $arch" >> "$FULL_LOG_FILE"
                    run_container "$distro" "$arch" "${TASK_ROW["$key"]}"
                    running_tasks_pids["$key"]=$!
                    running_tasks=$((running_tasks + 1))
                    if [[ $running_tasks -ge $MAX_PARALLEL ]]; then
                        break
                    fi
                fi
            done
        fi

        # Update testing time and statuses
        update_testing_time

        # Check and update the status of each task
        for TASK in "${TASKS[@]}"; do
            distro=$(echo "$TASK" | cut -d'|' -f1)
            arch=$(echo "$TASK" | cut -d'|' -f2)
            key="$distro-$arch"
            check_and_update_status "$distro" "$arch" "${TASK_ROW["$key"]}"
        done

        sleep 1  # Wait before the next update

        # Check for completion of all tasks
        all_done=true
        for TASK in "${TASKS[@]}"; do
            distro=$(echo "$TASK" | cut -d'|' -f1)
            arch=$(echo "$TASK" | cut -d'|' -f2)
            key="$distro-$arch"
            if [[ "${statuses["$key"]}" == "QUEUE" || "${statuses["$key"]}" == TESTING* ]]; then
                all_done=false
                break
            fi
        done

        if [[ "$all_done" == true ]]; then
            echo "All tasks completed. Testing finished." >> "$FULL_LOG_FILE"
            break
        fi
    done
}

# Initialize the table
init_table

# Start the main loop
start_next_task
wait
