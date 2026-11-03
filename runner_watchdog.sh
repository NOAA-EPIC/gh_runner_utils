#!/usr/bin/env bash

set -eu

runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
cd "${runner_root}"
source "runner_functions.sh"
ensure_host "$@"

# Determine which machine we are on
source "detect_machine.sh"

list_existing_runners "${runner_root}"

lock_file="lock"
stop_file="stop"
log_file="run.log"
while IFS= read -r runner; do
	cd "${runner}"

	if [[ ! -f "${stop_file}" ]]; then
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
	else
		echo "Runner ${runner} marked as stopped, skipping."
	fi

	cd ..
done < <(list_existing_runners "${runner_root}")
