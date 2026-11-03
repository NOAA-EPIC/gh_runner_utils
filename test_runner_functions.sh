#!/usr/bin/env bash
# shellcheck disable=SC2164

set -u

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${TEST_ROOT}/runner_functions.sh"

pass_count=0
fail_count=0

assert_true() {
	local condition="$1"
	local message="$2"

	if [[ "${condition}" == "true" ]]; then
		pass_count=$((pass_count + 1))
		printf 'PASS: %s\n' "${message}"
	else
		fail_count=$((fail_count + 1))
		printf 'FAIL: %s\n' "${message}"
	fi
}

assert_equals() {
	local expected="$1"
	local actual="$2"
	local message="$3"

	if [[ "${actual}" == "${expected}" ]]; then
		pass_count=$((pass_count + 1))
		printf 'PASS: %s\n' "${message}"
	else
		fail_count=$((fail_count + 1))
		printf 'FAIL: %s\n' "${message}"
		printf '  expected: %s\n' "${expected}"
		printf '  actual:   %s\n' "${actual}"
	fi
}

assert_contains() {
	local haystack="$1"
	local needle="$2"
	local message="$3"

	if [[ "${haystack}" == *"${needle}"* ]]; then
		pass_count=$((pass_count + 1))
		printf 'PASS: %s\n' "${message}"
	else
		fail_count=$((fail_count + 1))
		printf 'FAIL: %s\n' "${message}"
		printf '  needle: %s\n' "${needle}"
		printf '  haystack: %s\n' "${haystack}"
	fi
}

run_test() {
	local name="$1"
	shift
	if "$@"; then
		pass_count=$((pass_count + 1))
		printf 'PASS: %s\n' "${name}"
	else
		fail_count=$((fail_count + 1))
		printf 'FAIL: %s\n' "${name}"
	fi
}

# Create a temporary sandbox for stubbed commands.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

cat > "${WORKDIR}/wget" <<'EOF'
#!/usr/bin/env bash
url=""
while [[ $# -gt 0 ]]; do
	case "$1" in
        -*)
			# Ignore any options
			;;
        *)
            url="$1"
            break
            ;;
    esac
    shift
done

case "${url:-}" in
    https://example.com/ok.git)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "${WORKDIR}/wget"

cat > "${WORKDIR}/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${WORKDIR}/ssh"

cat > "${WORKDIR}/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" ]]; then
	printf '%s\n' 'auto-token'
	exit 0
fi
exit 0
EOF
chmod +x "${WORKDIR}/gh"

PATH="${WORKDIR}:$PATH"

# get_short_repo
assert_equals "owner/repo" "$(get_short_repo "https://github.com/owner/repo")" "get_short_repo formats owner/repo"

# is_valid_repo
if is_valid_repo "https://example.com/ok"; then
	pass_count=$((pass_count + 1))
	printf 'PASS: is_valid_repo returns success for reachable repo\n'
else
	fail_count=$((fail_count + 1))
	printf 'FAIL: is_valid_repo returns success for reachable repo\n'
fi

if is_valid_repo "https://example.com/missing"; then
	fail_count=$((fail_count + 1))
	printf 'FAIL: is_valid_repo rejects unreachable repo\n'
else
	pass_count=$((pass_count + 1))
	printf 'PASS: is_valid_repo rejects unreachable repo\n'
fi

# validate_repo
(
	cd "${WORKDIR}"
	validate_repo "https://example.com/ok"
) >/dev/null 2>&1
status=$?
assert_equals "0" "${status}" "validate_repo succeeds when repo is reachable"

(
	cd "${WORKDIR}"
	validate_repo "https://example.com/missing"
) >/dev/null 2>&1
status=$?
assert_equals "1" "${status}" "validate_repo exits when repo is unreachable"

# ensure_host
mkdir -p "${WORKDIR}/host_ok"
printf 'target-host\n' > "${WORKDIR}/host_ok/.target_host"
(
	cd "${WORKDIR}/host_ok"
	HOSTNAME="target-host"
	source "${TEST_ROOT}/runner_functions.sh"
	ensure_host
)
status=$?
assert_equals "0" "${status}" "ensure_host succeeds on the configured host"

mkdir -p "${WORKDIR}/host_ssh"
printf 'target-host\n' > "${WORKDIR}/host_ssh/.target_host"
(
	cd "${WORKDIR}/host_ssh"
	HOSTNAME="other-host"
	source "${TEST_ROOT}/runner_functions.sh"
	ensure_host
)
status=$?
assert_equals "0" "${status}" "ensure_host reconnects via SSH on a different host"

# get_token success path
output="$(get_token "https://github.com/owner/repo")"
assert_contains "${output}" "auto-token" "get_token returns the token from gh"

# get_token manual-entry fallback path
cat > "${WORKDIR}/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${WORKDIR}/gh"
output=$(printf '%s\n' 'manual-token' | (cd "${WORKDIR}" && source "${TEST_ROOT}/runner_functions.sh" && get_token "https://github.com/owner/repo") 2>&1)
assert_contains "${output}" "Could not get token automatically from GitHub CLI" "get_token warns when gh fails"
assert_contains "${output}" "manual-token" "get_token accepts a manually entered token"

printf '\nSummary: %d passed, %d failed\n' "${pass_count}" "${fail_count}"

if [[ "${fail_count}" -ne 0 ]]; then
	exit 1
fi
