#!/usr/bin/env bash

set -eu

num_new=${1:- -1}
token=${2:-"none"}

runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
cd "${runner_root}"
source "runner_functions.sh"

if [[ ! -f ".target_repo" ]]; then
	echo "The repo file (.target_repo) is missing in ${runner_root}, reinitialize directory"
fi

repo=$(cat .target_repo)
validate_repo "${repo}"

# Determine which machine we are on
source "detect_machine.sh"

# Check for existing runners
num_existing=$(count_existing_runners "${runner_root}")
echo "${num_existing} existing runners found in ${runner_root}"
echo

while [[ ! "${num_new}" =~ ^[0-9]+$ || ${num_new} -lt 0 ]]; do
	echo "Please enter a non-negative interger"
	echo
	echo "How many runners would you like to add?"
	read -r num_new
done
echo

if [[ "${num_new}" -eq 0 ]]; then
	echo "Zero runners chosen, exiting"
	exit 0
else
	echo "Creating ${num_new} new runners for ${repo}"
fi

if [[ "${token}" == "none" ]]; then
	token=$(get_token "${repo}")
fi

ensure_host "${num_new}" "${token}"

new_total=$((num_existing + num_new))

for ((runner_num = num_existing; runner_num < new_total; runner_num++)); do
	runner_num_padded=$(printf '%03d' "${runner_num}")
	runner_dir="${MACHINE_ID}_${runner_num_padded}"
	echo "Copying clean runner directory to ${runner_dir}"
	rsync -a --stats .clean/ "${runner_dir}" --exclude="externals"
	cd "${runner_dir}"
	ln -s "../.clean/externals" ./

	echo "Configuring GitHub runner ${runner_dir}"
	./config.sh --unattended --url "${repo}" --token "${token}" --name "${MACHINE_ID}_${runner_num_padded}" --labels "${MACHINE_ID}"
	cd ..
done

# Run watchdog to start any new runners
./runner_watchdog.sh

echo "Your new runners have been created and started"
echo "Add ${runner_root}/runner_watchdog.sh to your crontab to keep your runners running"
