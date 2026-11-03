#!/usr/bin/env bash
#
# destroy_runners.bash Stop, unregister, and delete GitHub Actions self-hosted
# runners.
#
# Usage: ./destroy_runners.bash [num_destroy|all [token]]
#
# Examples: ./destroy_runners.bash 2 ./destroy_runners.bash all
#
# Stops, unregisters, and deletes GH runners. Runners will be destroyed in the
# reverse order they were created (i.e. the highest numbered one first). If
# `num_destroy` is not provided, the user will be prompted. `all` is a valid
# value (either on the CLI or in response to a prompt).
#
# If all runners are destroyed, the user will be asked whether they wish to
# delete the entire `runner_root` directory.
#

set -eu

# Get arguments
num_destroy=${1:- -1}
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
num_existing=$(set -e; count_existing_runners "${runner_root}")
if [[ "${num_existing}" -eq 0 ]]; then
	echo "No runners found in ${runner_root} matching the pattern ${MACHINE_ID}_###:"
	ls "${runner_root}"
	exit 1
else
	echo "${num_existing} existing runners found in ${runner_root}"
fi

# Prompt for the number of runners to destroy if not provided as an argument
while [[ "${num_destroy,,}" != "all" ]] && [[ ! "${num_destroy}" =~ ^[0-9]+$ || "${num_destroy}" -lt 0 ]]; do
	echo "Please enter a non-negative interger or 'all'"
	echo
	echo "How many runners would you like to destroy?"
	read -r num_destroy
done
echo

# Resolve 'all' & do bounds checking
if [[ "${num_destroy,,}" == "all" ]]; then
	num_destroy="${num_existing}"
elif [[ "${num_destroy}" -eq 0 ]]; then
	echo "Zero runners chosen, exiting"
	exit 0
elif [[ "${num_destroy}" -gt "${num_existing}" ]]; then
	echo "Number to destroy larger than the number that exist, will destroy them all"
	num_destroy="${num_existing}"
fi

# Get the GitHub token if not provided as an argument
if [[ "${token}" == "none" ]]; then
	token=$(set -e; get_token "${repo}")
fi

# Make sure we are running on the designated host, otherwise run this script there via SSH
# This ensures we can manage the runner process IDs
ensure_host "${num_destroy}" "${token}"

# How many runners will there be after we are done?
new_total=$((num_existing - num_destroy))

# Destroy runners starting from the highest number
for ((runner_num = num_existing - 1; runner_num >= new_total; runner_num--)); do
	runner_num_padded=$(printf '%03d' "${runner_num}")
	runner_dir="${MACHINE_ID}_${runner_num_padded}"

	# Stop the runner if is running
	./stop_runners.bash "${runner_dir}"

	# Unregister the runner from GH
	cd "${runner_dir}"
	./config.sh remove --token "${token}"
	cd ..

	# Remove the runner directory
	rm -Rf "${runner_dir}"
done

echo "${num_destroy} runners have been destoyed, ${new_total} remain"

# If no runners remain, ask user if they want to remove the whole directory
if [[ "${new_total}" -eq 0 ]]; then
	echo "All runners were destroyed, would you like to remove the root directory? [y/N]"
	read -r delete_dir

	if [[ ${delete_dir,,} =~ ^y(es)$ ]]; then
		cd "${runner_root}/.."
		rm -Rf "${runner_root}"
		echo "${runner_root} deleted"
	fi
fi
