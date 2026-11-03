#!/usr/bin/env bash
#
# Initialize a GitHub Actions runner root directory for a repository and target
# host.
#
# Usage: ./init_runner_dir.bash [runner_root [repo [hostname]]]
#
# Examples: ./init_runner_dir.bash /scratch/gh_runners owner/repo
#   ./init_runner_dir.bash /scratch/gh_runners https://github.com/owner/repo
#   hercules
#
# This will initialize `$runner_root` to hold self-hosted runners for `$repo`.
#
# If arguments are not provided, the user will be prompted for them.
# Additionally, if `$runner_root` already exists, the user will be prompted
# whether to `delete` the existing directory, `use` the existing directory, or
# `abort`.
# - If `delete` is selected, any runners that already exist will first be
#   stopped and destroyed, to avoid orphaned runners
# - If `use` is selected, the assigned repo and hostname, as well as any
#   runners, will be preserved. All of the utility scripts will be updated with
#   the versions from the current directory.
#
# Once initialized, all of the other scripts are run from that directory, not
# from the source directory. All of these scripts will only run on the assigned
# host; if you run them on any other host, the script will collect the necessary
# information, then SSH into the correct host and execute the script there. This
# ensures the process IDs of the runners stays consistent so they can be
# managed.
#

set -eu

runner_root=${1:-""}
repo=${2:-"none"}
target_host=${3:-""}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source "${script_dir}/runner_functions.bash"

# Source and validation hash for Linux x64 GH runner tarball
# https://github.com/actions/runner/releases
# Update these two as necessary (runners should auto-update anyway)
runner_source_url='https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz'
runner_tarball_hash='baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40'

runner_tarball=$(basename "${runner_source_url}")

# Determine which machine we are on
source "${script_dir}/detect_machine.bash"

# Prompt for a path if none was provided as an argument
if [[ "${runner_root}" == "" ]]; then
	echo "Where would you like to initalize to host GitHub runners?"
	read -r runner_root
fi

# Check if directory exists and handle
if [[ -d "${runner_root}" ]]; then
	echo "${runner_root} already exists, do you want to (d)elete, (u)se, or (a)bort (default: abort)?"
	choice=""
	while [[ "${choice}" == "" ]]; do
		read -r choice
		case "${choice,,}" in
			d | delete )
				# Stop and destroy any runners that exist, then delete the directory
				if [[ -f "${runner_root}/destroy_runners.bash" && -d "${runner_root}/${MACHINE_ID}_000" ]]; then
					echo "Existing runners detected, making sure all runners are destroyed first"
					# Respond no to deleting the directory after destroying all runners, since we will be doing that anyway
					no | "${runner_root}/destroy_runners.bash" all > /dev/null || true
				fi
				echo "Deleting ${runner_root}..."
				rm -Rf "${runner_root}"
				echo
				;;
			u | use )
				# Use the existing directory without changing the settings or disturbing runners
				echo "Using existing ${runner_root} without destroying any existing runners"

				repo=$(cat "${runner_root}/.target_repo")
				echo "Target repo is set up for ${repo}"
				num_existing=$(find "${runner_root}" -maxdepth 1 -type d -regextype posix-extended -regex "${runner_root}/${MACHINE_ID}_[0-9]{3}" -printf '.' | wc -c)
				echo "The ${num_existing} existing runners found in ${runner_root} will be left unchanged"
				target_host=$(cat "${runner_root}/.target_host")
				echo "Target host ${target_host} will be left unchanged"
				echo "Runner scripts will still be overwritten"
				echo
				;;
			a | abort )
				echo "Aborting"
				exit 0
				;;
			*)
				echo "Invalid choice, please choose delete, use, or abort"
				echo
				choice=""
				;;
		esac
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

if [[ ! -d .clean/externals ]]; then
	echo "Creating clean runner directory"
	rm -Rf .clean
	mkdir .clean
	cd .clean

	# Get a copy of the GH runner tarball
	curl -o "${runner_tarball}" -L "${runner_source_url}"
	echo
	# Two spaces are required between the hash and the tarball
	echo "${runner_tarball_hash}  ${runner_tarball}" | shasum -a 256 -c
	echo
	echo "Extracting tarball"
	tar -xzf "./${runner_tarball}"
	# Remove the tarball so it doesn't get copied
	rm "${runner_tarball}"
	cd ..
fi

# Copy non-executable scripts to the runner directory (these get sourced by the others)
for script in runner_functions.bash detect_machine.bash; do
	cp "${script_dir}/${script}" ./
done

# Copy executable scripts to the runner directory
for script in create_runners.bash destroy_runners.bash runner_watchdog.bash \
				stop_runners.bash start_runners.bash; do

	cp "${script_dir}/${script}" ./
	chmod 744 "./${script}"
done

echo "GitHub runner directory has been initialized at ${runner_root}"
echo "Run ${runner_root}/create_runners.bash to create new runners"
