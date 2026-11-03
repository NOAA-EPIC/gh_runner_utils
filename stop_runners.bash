#!/usr/bin/env bash

set -eu

runners=("$@")

runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
cd "${runner_root}"
source "runner_functions.bash"
ensure_host "$@"

# List all the descendants of a process
function list_descendants() {
	local children
	children=$(ps -o pid= --ppid "${1}")

	for pid in ${children}; do
		list_descendants "${pid}"
	done

	echo "${children}"
}

# Determine which machine we are on
source "detect_machine.bash"

# If the first argument is 'all', create a list of all runners (and ignore any other args)
if [[ "${runners[0]:-}" == "all" ]]; then
	mapfile -t runners < <(list_existing_runners "${runner_root}")
fi

lock_file="lock"
stop_file="stop"
for runner in "${runners[@]}"; do
	if [[ ! ${runner} =~ ^${MACHINE_ID}_ ]] && [[ ${runner} =~ ^[0-9]+$ ]]; then
		# Convert number to full runner name
		runner_num_padded=$(printf '%03d' "${runner}")
		runner="${MACHINE_ID}_${runner_num_padded}"
	fi

	if [[ ! -d "${runner}" ]]; then
		echo "${runner} is not a valid GitHub runner directory"
		exit 2
	fi
	
	cd "${runner}"

	# Create file to let watchdog know to keep this runner down
	touch "${stop_file}"

	# Check if the runner process is already running via a lock file
	if [[ -f "${lock_file}" ]]; then
		pid="$(cat "${lock_file}")"
		echo "Stopping runner ${runner} with PID ${pid}..."
		set +e
		# shellcheck disable=SC2046
		kill -- "${pid}" $(list_descendants "${pid}")
		set -e
		# Remove the lock file with the PID now that it is done
		rm -f "${lock_file}"
		echo "Runner ${runner} stopped."
	fi

	cd ..
done
