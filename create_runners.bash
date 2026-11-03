#!/usr/bin/env bash
#
# Create and register additional GitHub Actions self-hosted runners.
#
# Usage:
#   ./create_runners.bash [num_new [token]]
#
# Examples:
#   ./create_runners.bash 4
#   ./create_runners.bash 2 "$GH_TOKEN"
#
# Creates and registers additional GH runners. Runners will have a label
# corresponding to the machine (e.g. ursa, hercules, etc.). Runner names on each
# machine will be assigned sequentially starting from 0 with three-digit
# padding: ursa_000, ursa_001, etc. If `num_new` is not provided on the command
# line, the user will be prompted.
#
# Create runners will attempt to acquire a GitHub token automatically using the
# GitHub CLI (`gh`). To work, `gh` must be in your current path (usually by
# loading a module), you must be authenticated, and you must have owner
# permissions on the target repository. If this attempt fails, you will be
# prompted to provide a key manually.
#
# Once created, the new runners will be started. To make sure the runners are
# automatically restarted if the processes should be killed, add
# `${runner_root}/runner_watchdog.bash` to your crontab/scron to run at regular
# intervals.
#

set -eu

# Get arguments
num_new=${1:- -1}
token=${2:-"none"}

# Run from the script directory and load functions
runner_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
cd "${runner_root}"
source "runner_functions.bash"

# Make sure the repository is defined and valid
if [[ ! -f ".target_repo" ]]; then
	echo "The repo file (.target_repo) is missing in ${runner_root}, reinitialize directory"
fi
repo=$(cat .target_repo)
validate_repo "${repo}"

# Determine which machine we are on
source "detect_machine.bash"

# Check for existing runners
num_existing=$(
	set -e
	count_existing_runners "${runner_root}"
)
echo "${num_existing} existing runners found in ${runner_root}"
echo

# Prompt for the number of runners to create if not provided as an argument
while [[ ! "${num_new}" =~ ^[0-9]+$ || "${num_new}" -lt 0 ]]; do
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

# Get the GitHub token if not provided as an argument
if [[ "${token}" == "none" ]]; then
	token=$(
		set -e
		get_token "${repo}"
	)
fi

# Make sure we are running on the designated host, otherwise run this script there via SSH
# This ensures we can manage the runner process IDs
ensure_host "${num_new}" "${token}"

# How many runners will there be after we are done?
new_total=$((num_existing + num_new))

# Create the new runners
for ((runner_num = num_existing; runner_num < new_total; runner_num++)); do
	runner_num_padded=$(printf '%03d' "${runner_num}")
	runner_dir="${MACHINE_ID}_${runner_num_padded}"
	echo "Copying clean runner directory to ${runner_dir}"

	# The externals directory takes up most of the space, and can be shared, so symlink it and copy everything else
	rsync -a .clean/ "${runner_dir}" --exclude="externals"
	cd "${runner_dir}"
	ln -s "../.clean/externals" ./

	# Register the new runner with GitHub
	echo "Configuring GitHub runner ${runner_dir}"
	./config.sh --unattended --url "${repo}" --token "${token}" --name "${MACHINE_ID}_${runner_num_padded}" --labels "${MACHINE_ID}"
	cd ..
done

# Run watchdog to start any new runners
./runner_watchdog.bash

echo "Your new runners have been created and started"
echo "Add ${runner_root}/runner_watchdog.bash to your crontab to keep your runners running"
