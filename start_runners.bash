#!/usr/bin/env bash

set -eu

runners=("$@")

runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
cd "${runner_root}"
source "runner_functions.bash"
ensure_host "$@"

# Determine which machine we are on
source "detect_machine.bash"

# If the first argument is 'all', create a list of all runners (and ignore any other args)
if [[ "${runners[0]:-}" == "all" ]]; then
	mapfile -t runners < <(list_existing_runners "${runner_root}")
fi

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
	
	# Remove the stop file so the watchdog knows this runner is active
	rm -f "${runner}/${stop_file}"
done

# Run the watchdog to start any unstopped runners that are not running
./runner_watchdog.bash
