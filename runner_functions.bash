#!/usr/bin/env bash
#
# Common helper functions for GitHub runner lifecycle management.
#
# Usage:
#   source ./runner_functions.bash
#
# This file provides shared logic for validating repositories, ensuring the
# target host, listing runners, fetching registration tokens, and interacting
# with SSH.
#

function ensure_host() {
	# Ensure the script is running on the configured target host.
	#
	# Usage:
	#   ensure_host [args...]
	#
	# If the current machine does not match .target_host, SSH into the target host
	# and re-execute the current script with the same arguments.
	#
	local target_host script_dir absolute_path
	script_dir="$(cd -- "$(dirname -- "${BASH_ARGV0}")" &> /dev/null && pwd)"
	target_host="$(cat "${script_dir}/.target_host")"

	if [[ "${HOSTNAME}" != "${target_host}" ]]; then
		absolute_path="${script_dir}/$(basename -- "${BASH_ARGV0}")"
		echo "Not on ${target_host}; connecting via SSH and re-running ${absolute_path}"
		ssh "${target_host}" -- bash "${absolute_path}" "$@"
		exit $?
	fi
}

function is_valid_repo() {
	# Check whether a repository URL is reachable over HTTPS.
	#
	# Usage:
	#   is_valid_repo "https://github.com/owner/repo"
	#
	# Returns success if the repo's .git URL is accessible; failure otherwise.
	#
	local repo=$1
	if wget -q "${repo}.git" -O /dev/null; then
		return 0
	else
		return 1
	fi
}

function validate_repo() {
	# Validate that a GitHub repository can be reached and exit on failure.
	#
	# Usage:
	#   validate_repo "https://github.com/owner/repo"
	#
	# Prints a helpful message and exits with status 1 if the repository is not
	# reachable.
	#
	local repo=$1

	if ! is_valid_repo "${repo}"; then
		echo "Could not contact ${repo}.git"
		echo "If this is the wrong repo, reinitialize directory"
		echo "Otherwise, this could be a temporary connectivity problem"
		exit 1
	fi
}

function get_short_repo() {
	# Convert a full GitHub repo URL to the owner/repo format.
	#
	# Usage:
	#   get_short_repo "https://github.com/owner/repo"
	#
	# Outputs: owner/repo
	#
	local repo=$1
	echo "$(basename "$(dirname "${repo}")")/$(basename "${repo}")"
}

function get_token() {
	# Fetch a GitHub Actions registration token for the repository.
	#
	# Usage:
	#   get_token "https://github.com/owner/repo"
	#
	# Attempts to use gh first. If that fails, it prompts the user to enter a
	# token manually.
	#
	local repo repo_short token
	repo=$1
	repo_short=$(get_short_repo "${repo}")

	if ! token=$(gh api --method POST -H "Accept: application/vnd.github+json" "/repos/${repo_short}/actions/runners/registration-token" --jq .token 2> /dev/null); then
		cat <<- EOF >&2
			Could not get token automatically from GitHub CLI
			- Is gh in your path? (you may need to load a module)
			- Are you authenticated?
			- Are you an owner of ${repo_short}?

			Please enter the token manually or leave blank to exit:
			(Token can be found in code shown at ${repo}/settings/actions/runners/new?arch=x64&os=linux)
		EOF
		read -r token
		if [[ "${token}" == "" ]]; then
			echo "No token provided, exiting"
			exit 1
		fi
	fi
	echo "${token}"
}

function list_existing_runners() {
	# List the runner directories for the current machine in sorted order.
	#
	# Usage:
	#   list_existing_runners "$runner_root"
	#
	# Output is one directory name per line, matching <machine>_###.
	#
	local runner_root=$1
	# shellcheck disable=SC2154
	find "${runner_root}" -maxdepth 1 -type d -regextype posix-extended -regex "${runner_root}/${MACHINE_ID}_[0-9]{3}" -printf '%f\n' | sort
}

function count_existing_runners() {
	# Count the number of runner directories for the current machine.
	#
	# Usage:
	#   count_existing_runners "$runner_root"
	#
	# Returns the count via stdout.
	#
	local runner_root=$1
	list_existing_runners "${runner_root}" | wc -l
}
