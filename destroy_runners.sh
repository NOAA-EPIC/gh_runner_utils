#!/usr/bin/env bash

set -eu

num_destroy=${1:- -1}
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
if [[ "${num_existing}" -eq 0 ]]; then
	echo "No runners found in ${runner_root} matching the pattern ${MACHINE_ID}_###:"
	ls "${runner_root}"
	exit 1
else
	echo "${num_existing} existing runners found in ${runner_root}"
fi

while [[ "${num_destroy}" != "all" ]] && [[ ! "${num_destroy}" =~ ^[0-9]+$ || "${num_destroy}" -lt 0 ]]; do
	echo "Please enter a non-negative interger or 'all'"
	echo
	echo "How many runners would you like to destroy?"
	read -r num_destroy
done
echo

if [[ "${num_destroy}" == "all" ]]; then
	num_destroy="${num_existing}"
elif [[ "${num_destroy}" -eq 0 ]]; then
	echo "Zero runners chosen, exiting"
	exit 0
elif [[ "${num_destroy}" -gt "${num_existing}" ]]; then
	echo "Number to destroy larger than the number that exist, will destroy them all"
	num_destroy="${num_existing}"
fi

if [[ "${token}" == "none" ]]; then
	token=$(get_token "${repo}")
fi

ensure_host "${num_destroy}" "${token}"

new_total=$((num_existing - num_destroy))

# Destroy runners starting from the highest number
for ((runner_num = num_existing - 1; runner_num >= new_total; runner_num--)); do
	runner_num_padded=$(printf '%03d' "${runner_num}")
	runner_dir="${MACHINE_ID}_${runner_num_padded}"
	# Stop the runner if is running
	./stop_runners.sh "${runner_dir}"
	cd "${runner_dir}"
	# Unregister the runner from GH
	./config.sh remove --token "${token}"
	cd ..
	# Remove the runner directory
	rm -Rf "${runner_dir}"
done

echo "${num_destroy} runners have been destoyed, ${new_total} remain"

if [[ "${new_total}" -eq 0 ]]; then
	echo "All runners were destroyed, would you like to remove the root directory? [y/N]"
	read -r delete_dir

	if [[ ${delete_dir} =~ ^[Yy](|[Ee][Ss])$ ]]; then
		cd "${runner_root}/.."
		rm -Rf "${runner_root}"
		echo "${runner_root} deleted"
	fi
fi
