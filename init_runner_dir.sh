#!/usr/bin/env bash

set -eu

runner_root=${1:-""}
repo=${2:-"none"}
target_host=${3:-""}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${script_dir}/runner_functions.sh"

# Source and validation hash for Linux x64 GH runner tarball
# https://github.com/actions/runner/releases
# Update these two as necessary (runners should auto-update anyway)
runner_source_url='https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz'
runner_tarball_hash='baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40'

runner_tarball=$(basename "${runner_source_url}")

# Determine which machine we are on
source "${script_dir}/detect_machine.sh"

if [[ "${runner_root}" == "" ]]; then
	echo "Where would you like to initalize to host GitHub runners?"
	read -r runner_root
fi

# Check if directory exists
if [[ -d "${runner_root}" ]]; then
	echo "${runner_root} already exists, do you want to (d)elete, (u)se, or (a)bort (default: abort)?"
	choice=""
	while [[ "${choice}" == "" ]]; do
		read -r choice
		if [[ ${choice} =~ ^d(|elete)$ ]]; then
			if [[ -f "${runner_root}/destroy_runners.sh" && -d "${runner_root}/${MACHINE_ID}_000" ]]; then
				echo "Existing runners detected, making sure all runners are destroyed first"
				no | "${runner_root}/destroy_runners.sh" all > /dev/null || true
			fi
			echo "Deleting ${runner_root}..."
			rm -Rf "${runner_root}"
			echo
		elif [[ ${choice} =~ ^u(|se)$ ]]; then
			echo "Using existing ${runner_root} without deleting existing"

			repo=$(cat "${runner_root}/.target_repo")
			echo "Target repo is set up for ${repo}"
			num_existing=$(find "${runner_root}" -maxdepth 1 -type d -regextype posix-extended -regex "${runner_root}/${MACHINE_ID}_[0-9]{3}" -printf '.' | wc -c)
			echo "The ${num_existing} existing runners found in ${runner_root} will be left unchanged"
			target_host=$(cat "${runner_root}/.target_host")
			echo "Target host ${target_host} will be left unchanged"
			echo "Runner scripts and clean directory will still be overwritten"
			echo
		elif [[ ${choice} =~ ^a(|bort) || "${choice}" -eq "" ]]; then
			echo "Aborting"
			exit 0
		else
			echo "Invalid choice, please choose delete, use, or abort"
			echo
			choice=""
		fi
	done
fi

# Get repo
if [[ ! ${repo} =~ ^https:// ]]; then
	repo="https://github.com/${repo}"
fi
while ! is_valid_repo "${repo}"; do
	echo "What is the URL of the repository?"
	read -r repo
	echo

	if [[ ! ${repo} =~ ^https:// ]]; then
		repo="https://github.com/${repo}"
	fi

	if ! is_valid_repo "${repo}"; then
		echo "Could not connect to ${repo}, is it correct?"
		echo
	fi
done

# Select target host
if [[ "${target_host}" == "" ]]; then
	echo "What hostname do you want to lock the runners to? [default: current host (${HOSTNAME})]"
	read -r target_host
	if [[ "${target_host}" == "" ]]; then
		target_host="${HOSTNAME}"
	fi
fi

# Make and change to the target directory
mkdir -p "${runner_root}"
cd "${runner_root}"
echo "${repo}" > .target_repo
echo "${target_host}" > .target_host

echo "Creating clean runner directory"
rm -Rf .clean
mkdir .clean
cd .clean

# Get a copy of the GH runner tarball
curl -o "${runner_tarball}" -L "${runner_source_url}"
# Two spaces are required between the hash and the tarball
echo
echo "${runner_tarball_hash}  ${runner_tarball}" | shasum -a 256 -c
echo
echo "Extracting tarball"
tar -xzf "./${runner_tarball}"
# Remove the tarball so it doesn't get copied
rm "${runner_tarball}"
cd ..

# Copy non-executable scripts to the runner directory (these get sourced by the others)
for script in runner_functions.sh detect_machine.sh; do
	cp "${script_dir}/${script}" ./
done

# Copy executable scripts to the runner directory
for script in create_runners.sh destroy_runners.sh runner_watchdog.sh \
				stop_runners.sh start_runners.sh; do

	cp "${script_dir}/${script}" ./
	chmod 744 "./${script}"
done

echo "GitHub runner directory has been initialized at ${runner_root}"
echo "Run ${runner_root}/create_runners.sh to create new runners"
