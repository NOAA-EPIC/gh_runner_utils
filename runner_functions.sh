#!/usr/bin/env bash

function ensure_host() {
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
	local repo=$1
	if wget -q "${repo}.git" -O /dev/null; then
		return 0
	else
		return 1
	fi
}

function validate_repo() {
	local repo=$1

	if ! is_valid_repo "${repo}"; then
		echo "Could not contact ${repo}.git"
		echo "If this is the wrong repo, reinitialize directory"
		echo "Otherwise, this could be a temporary connectivity problem"
		exit 1
	fi
}

function get_short_repo() {
	local repo=$1
	echo "$(basename "$(dirname "${repo}")")/$(basename "${repo}")"
}

function get_token() {
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
	local runner_root=$1
	find "${runner_root}" -maxdepth 1 -type d -regextype posix-extended -regex "${runner_root}/${MACHINE_ID}_[0-9]{3}" -printf '%f\n' | sort
}

function count_existing_runners() {	
	local runner_root=$1
	list_existing_runners "${runner_root}" | wc -l
}
