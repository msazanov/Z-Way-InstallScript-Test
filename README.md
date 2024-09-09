
# Test Automation Script

This project is a test automation tool that allows for testing different distributions and architectures using Docker containers. It is designed to run multiple tests in parallel and provides a detailed output in the terminal, showing the progress and status of each test.

## Features

### Completed Features
- **Distribution and Architecture Selection**: You can select which distributions and architectures to test, allowing for flexible configuration.
- **Parallel Testing**: The script allows running tests in multiple threads, making the process faster and more efficient.
- **Real-time Test Progress and Status Display**: Each test's progress and status are displayed in real-time in a terminal table, showing which tests are in queue, testing, or completed.

### Planned Features
- **Accurate Test Timer**: Implementing a second-based timer that will track and display the time taken for each test to complete.
- **Interactive Test Selection**: Implement an interactive interface for selecting which tests to run. Currently, selections are done through command line prompts.
- **Final Test Summary**: At the end of all tests, a summary of the results (PASS/FAIL) should be presented for a quick overview of test outcomes.

## How the Script Works

1. **Test Selection**: At the beginning, the script prompts you to select which distributions and architectures you want to test. If 'All' is selected for architectures, it defaults to all supported architectures.
   
2. **Parallel Execution**: After selecting the number of parallel tests, the script begins running the selected tests in parallel. The number of tests that can run simultaneously is determined by the user input.

3. **Test Execution**: 
    - Each test is a Docker container running the selected distribution and executing a specified command (currently `uname -a` for system information). The test is designed to simulate work through a `sleep` command to introduce random delays.
    - Each test writes logs to a dedicated directory, and both the output and errors from the Docker container are captured in log files for later inspection.

4. **Real-time Updates**: The terminal shows a table where each row represents a test for a specific distribution and architecture. As tests progress, their statuses (QUEUE, TESTING, PASS, FAIL) are updated, and the table reflects the current state of each test.

5. **Completion Check**: The script continuously checks if all tests have completed (i.e., they have reached either `PASS`, `FAIL`, or `WARNING` status). Once all tests are done, the script exits and logs the final status.

### Current Structure of the Script

- **`run_container()`**: This function runs a Docker container with the specified distribution and architecture. It logs the command and output to a file, then updates the test status based on the success or failure of the container.

- **`start_next_task()`**: This is the main loop of the script, which manages the execution of tests in parallel. It monitors the progress of each test and ensures that the terminal table is updated in real-time.

- **Log Directories**: For each distribution and architecture, a dedicated log directory is created. The directory contains the logs of the Docker container run, capturing both stdout and stderr.

## Next Steps

- **Implement Timer**: The script currently does not display an accurate second-by-second timer for tests. This needs to be implemented to provide real-time tracking of how long each test takes.
  
- **Add Interactive Interface**: Instead of manually selecting tests through command line inputs, we should introduce an interactive interface where users can select the tests they want to run using a GUI or text-based interface.

- **Provide Final Summary**: At the end of all tests, a final summary should be displayed, showing how many tests passed, failed, or generated warnings. This would give a clear overview of the test results at a glance.

### Usage Notes

- **Running the Script**: To run the script, ensure you have Docker installed and running on your machine. The script uses Docker containers to run each test, and logs the output in corresponding directories.

- **Configuring Parallel Tests**: You can configure the number of parallel tests at the beginning of the script. The script handles task distribution efficiently, ensuring that no more than the specified number of tests run at once.

This README serves as a guide and a reminder of the current state of the project, as well as the next steps to enhance its functionality.

