#!/usr/bin/env bash
#
# runner_watchdog.bash Ensure all registered GitHub Actions runners are running
# on the designated host.
#
# Usage: ./runner_watchdog.bash [args...]
#
# Examples: ./runner_watchdog.bash crontab: */5 * * * *
#   /path/to/runner_root/runner_watchdog.bash
#
# Iterates over all runners checks whether their recorded process ID is still
# running, and start the runner if not. This is called automatically after
# starting of creating runners, and can be added to your cron/scron to act as a
# pseudo-daemon to keep runners up.
#
# ```cron
# */5 * * * * /path/to/runner_root/runner_watchdog.bash >> /path/to/runner_root_runner_watchdog.log 2>&1
# ```

set -eu

# Run from the script directory and load functions
runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
cd "${runner_root}"
source "runner_functions.bash"

# Make sure we are running on the designated host, otherwise run this script
# there via SSH This ensures we can manage the runner process IDs
ensure_host "$@"

# Determine which machine we are on
source "detect_machine.bash"

lock_file="lock"
stop_file="stop"
log_file="run.log"

# Check each runner
while IFS= read -r runner; do
	cd "${runner}"

	if [[ -f "${stop_file}" ]]; then
		# Runner has been marked as STOPPED
		echo "Runner ${runner} marked as stopped, skipping."
	else
		# Check if the runner process is already running via a lock file
		if [[ -f "${lock_file}" ]]; then
			# Optional: check if the PID in the lock file is still valid
			if ps -p "$(cat "${lock_file}")" > /dev/null; then
				echo "Runner is already running with PID $(cat "${lock_file}"), skipping."
				continue
			else
				echo "Stale lock file found. Removing."
				rm "${lock_file}"
			fi
		fi

		# Start the runner in the background and save its PID to the lock file
		echo "Starting runner ${runner}..."
		nohup ./run.sh > "${log_file}" 2>&1 &
		pid=$!
		echo "${pid}" > "${lock_file}"
		echo "Runner started with PID ${pid}."
	fi

	cd ..
done < <(list_existing_runners "${runner_root}")
