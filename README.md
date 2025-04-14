# Bash Disk I/O Test Script

A simple bash script to measure disk read and write performance using the `dd` command.

## Description

This script performs sequential read and write tests on a specified storage path using `dd`. It runs the tests multiple times, calculates the speed in MB/s for each run, and saves the results to a CSV file. It aims to provide a basic benchmark of disk I/O performance, attempting to bypass system caches for more accurate results using flags like `oflag=dsync` and `iflag=direct`.

## Prerequisites

The following command-line utilities must be installed and available in your system's PATH:

* `bash`
* `dd`
* `awk`
* `grep`
* `numfmt` (usually part of GNU coreutils)
* `sync`
* `rm`
* `id`
* `tail`

## Usage

1.  **Save the script:** Save the script content to a file, e.g., `disk_test.sh`.
2.  **Make it executable:**
    ```bash
    chmod +x disk_test.sh
    ```
3.  **Run the script:**
    ```bash
    ./disk_test.sh <test_path> <num_runs> <output_file>
    ```

    **Arguments:**

    * `<test_path>`: The directory where the temporary test file will be created and tested (e.g., `/mnt/data`, `/tmp`). The script needs write permissions in this directory.
    * `<num_runs>`: The number of times to repeat the read/write test cycle (e.g., `5`).
    * `<output_file>`: The name of the CSV file where results will be saved (e.g., `results.csv`).

    **Example:**

    ```bash
    ./disk_test.sh /var/tmp 10 disk_performance_results.csv
    ```

## Output File Format

The script generates a CSV file (`<output_file>`) with the following columns:

* **Path**: The directory path provided for testing.
* **Run**: The iteration number of the test.
* **ReadSpeed(MB/s)**: The measured read speed for that run in Megabytes per second.
* **WriteSpeed(MB/s)**: The measured write speed for that run in Megabytes per second.

**Example `results.csv`:**

```csv
Path,Run,ReadSpeed(MB/s),WriteSpeed(MB/s)
/var/tmp/,1,450.50,380.25
/var/tmp/,2,455.10,375.80
/var/tmp/,3,449.90,381.10
```

NotesRoot Privileges: For the most accurate read speed measurements that bypass the system's buffer cache, the script attempts to drop caches using echo 3 > /proc/sys/vm/drop_caches. This command requires root privileges. If run as a regular user, a warning will be displayed, and read speeds might be inflated due to caching. Running the script with sudo ./disk_test.sh ... is recommended for cache clearing.dd Flags:oflag=dsync is used for writes to request synchronous I/O, attempting to bypass the write cache.iflag=direct is used for reads to request direct I/O, attempting to bypass the read cache.Support and behavior of these flags can vary between systems and filesystems. If you encounter errors, you might need to remove these flags, but results will be more heavily influenced by caching.Test File Size: The default test size is 1GB (1M block size * 1024 count). You can modify the BLOCK_SIZE and COUNT variables within the script if needed.System Load: Run the script on a system with minimal background I/O activity for the most reliable results.SSD Wear: Be mindful that intensive write tests can
