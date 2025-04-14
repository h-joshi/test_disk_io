#!/bin/bash

# Script to test disk I/O read and write speed using dd.

# --- Configuration ---
BLOCK_SIZE="1M"      # Block size for dd (e.g., 1M, 4k)
COUNT=1024           # Number of blocks to write/read (e.g., 1024 * 1M = 1GB)
# Note: Total size = BLOCK_SIZE * COUNT. Adjust as needed.
# A larger size gives more realistic results but takes longer.

# --- Functions ---

# Function to print usage instructions
usage() {
  echo "Usage: $0 <test_path> <num_runs> <output_file>"
  echo "  <test_path>:   Directory where the test file will be created."
  echo "  <num_runs>:    Number of times to run the read/write test."
  echo "  <output_file>: File to save the results (CSV format)."
  exit 1
}

# Function to convert dd speed output (KB/s, MB/s, GB/s) to MB/s
# Takes value and unit (e.g., "106", "MB/s") as arguments
convert_to_mbs() {
    local value=$1
    local unit=$2
    local mbs_value

    # Check if value is a number
    if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "NaN"
        return
    fi

    # Perform conversion based on unit
    case "$unit" in
        "kB/s"|"KB/s")
            # awk is used for floating point arithmetic
            mbs_value=$(awk -v val="$value" 'BEGIN { printf "%.2f", val / 1024 }')
            ;;
        "MB/s")
            mbs_value=$(printf "%.2f" "$value")
            ;;
        "GB/s")
            # awk is used for floating point arithmetic
            mbs_value=$(awk -v val="$value" 'BEGIN { printf "%.2f", val * 1024 }')
            ;;
        *)
            # Handle unexpected units
            mbs_value="NaN"
            ;;
    esac
    echo "$mbs_value"
}

# Function to clean up the temporary test file
cleanup() {
  echo "Cleaning up..."
  rm -f "$TEST_FILE"
  echo "Cleanup complete."
}

# --- Argument Parsing and Validation ---

# Check for correct number of arguments
if [ "$#" -ne 3 ]; then
  echo "Error: Incorrect number of arguments."
  usage
fi

TEST_PATH="$1"
NUM_RUNS="$2"
OUTPUT_FILE="$3"

# Validate test path
if [ ! -d "$TEST_PATH" ]; then
  echo "Error: Test path '$TEST_PATH' does not exist or is not a directory."
  exit 1
fi
# Ensure path ends with a slash for consistency
[[ "$TEST_PATH" != */ ]] && TEST_PATH="${TEST_PATH}/"

# Validate number of runs
if ! [[ "$NUM_RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: Number of runs must be a positive integer."
  exit 1
fi

# Define the temporary test file path using Process ID ($$) for uniqueness
TEST_FILE="${TEST_PATH}temp_dd_test_file_$$"

# --- Trap for Cleanup ---
# Ensure cleanup function is called on script exit or interruption (INT, TERM)
trap cleanup EXIT INT TERM

# --- Main Execution ---

echo "Starting Disk I/O Test..."
echo "Test Path: $TEST_PATH"
echo "Number of Runs: $NUM_RUNS"
echo "Output File: $OUTPUT_FILE"
echo "Test File Size: Approximately $(numfmt --from=iec --to=iec ${BLOCK_SIZE%?} * $COUNT)${BLOCK_SIZE: -1}"
echo "Temporary Test File: $TEST_FILE"
echo "---"

# Write header to the output file
echo "Path,Run,ReadSpeed(MB/s),WriteSpeed(MB/s)" > "$OUTPUT_FILE"

# Loop for the specified number of runs
for (( run=1; run<=NUM_RUNS; run++ )); do
  echo "Starting Run $run/$NUM_RUNS..."

  # --- Write Test ---
  echo "  Performing write test..."
  # Use 'sync' before writing to attempt flushing caches, though effectiveness varies.
  sync

  # Execute dd for writing, redirect stderr (where speed info is) to stdout
  # Use 'oflag=dsync' for synchronous I/O to bypass cache for more accurate disk speed.
  # Warning: dsync can be significantly slower. Use 'oflag=direct' if supported and preferred.
  write_output=$(dd if=/dev/zero of="$TEST_FILE" bs="$BLOCK_SIZE" count="$COUNT" oflag=dsync 2>&1)
  write_speed_line=$(echo "$write_output" | grep 'copied')

  # Check if dd command was successful (basic check)
  if [ $? -ne 0 ] || [ -z "$write_speed_line" ]; then
      echo "  Error during write test for run $run. Output:"
      echo "$write_output"
      # Record error in output file
      echo "$TEST_PATH,$run,Error,Error" >> "$OUTPUT_FILE"
      # Skip to the next run
      # Ensure partial file is removed before next potential write attempt
      rm -f "$TEST_FILE"
      continue
  fi

  # Extract write speed value and unit
  write_speed_value=$(echo "$write_speed_line" | awk 'NF{print $(NF-1)}')
  write_speed_unit=$(echo "$write_speed_line" | awk 'NF{print $NF}')
  write_speed_mbs=$(convert_to_mbs "$write_speed_value" "$write_speed_unit")
  echo "    Write Speed: $write_speed_value $write_speed_unit ($write_speed_mbs MB/s)"

  # --- Read Test ---
  echo "  Performing read test..."
  # Use 'sync' and drop caches before reading for a more accurate disk read speed.
  # IMPORTANT: Dropping caches requires root privileges. If not run as root, this will fail silently.
  # The script will still work, but read speeds might be inflated by cache hits.
  sync
  # Check if running as root before attempting to drop caches
  if [ "$(id -u)" -eq 0 ]; then
      echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo "  Warning: Failed to drop caches. Read speed might be affected by cache."
  else
      echo "  Info: Not running as root. Cannot drop caches. Read speed might be affected by cache."
  fi

  # Execute dd for reading, redirect stderr to stdout
  # Use 'iflag=direct' to bypass cache for reading, if supported.
  read_output=$(dd if="$TEST_FILE" of=/dev/null bs="$BLOCK_SIZE" count="$COUNT" iflag=direct 2>&1)
  read_speed_line=$(echo "$read_output" | grep 'copied')

  # Check if dd command was successful
  if [ $? -ne 0 ] || [ -z "$read_speed_line" ]; then
      echo "  Error during read test for run $run. Output:"
      echo "$read_output"
      # Record error in output file (write speed was already recorded or marked as Error)
      # Need to retrieve the previously determined write speed or 'Error'
      last_line=$(tail -n 1 "$OUTPUT_FILE")
      current_write_speed=$(echo "$last_line" | awk -F, '{print $4}')
      if [[ "$current_write_speed" == "WriteSpeed(MB/s)" ]]; then # Handle first run error case
          echo "$TEST_PATH,$run,Error,$write_speed_mbs" >> "$OUTPUT_FILE" # Write speed might be valid
      else
          # If write speed was already Error, keep it Error, otherwise use write speed
          echo "$TEST_PATH,$run,Error,$write_speed_mbs" >> "$OUTPUT_FILE"
      fi
      # Skip to the next run
      rm -f "$TEST_FILE" # Clean up the file after failed read
      continue
  fi

  # Extract read speed value and unit
  read_speed_value=$(echo "$read_speed_line" | awk 'NF{print $(NF-1)}')
  read_speed_unit=$(echo "$read_speed_line" | awk 'NF{print $NF}')
  read_speed_mbs=$(convert_to_mbs "$read_speed_value" "$read_speed_unit")
  echo "    Read Speed: $read_speed_value $read_speed_unit ($read_speed_mbs MB/s)"

  # --- Record Results ---
  echo "$TEST_PATH,$run,$read_speed_mbs,$write_speed_mbs" >> "$OUTPUT_FILE"

  # --- Intermediate Cleanup ---
  # Remove the test file after each run to ensure a clean state for the next write
  rm -f "$TEST_FILE"
  sync # Sync after removal

  echo "  Run $run complete."
  echo "---"

done

echo "Disk I/O test finished."
echo "Results saved to: $OUTPUT_FILE"

# Explicitly exit with success code (trap will still run)
exit 0

