#!/bin/bash

# usage: run_test.sh <network>|mainnets <test_contract> [forge args...]
#
# Defaults to the gov Safe: detects pending updateContracts /
# batchUpdateSuperTokenLogic and sets PHASES + PHASE*_CALLDATA.
# Override by exporting PHASES and/or PHASE1_CALLDATA / PHASE2_CALLDATA.

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GET_SAFE="$REPO_ROOT/get-safe-calldata.py"

networkOrNetworkClass=${1:?usage: scripts/run_test.sh <network>|mainnets <test_contract> [forge args...]}
testContract=${2:?usage: scripts/run_test.sh <network>|mainnets <test_contract> [forge args...]}
shift 2
extraArgs=("$@")

user_phases=${PHASES-}
user_p1=${PHASE1_CALLDATA-}
user_p2=${PHASE2_CALLDATA-}

metadata=$(curl -s "https://raw.githubusercontent.com/superfluid-finance/protocol-monorepo/dev/packages/metadata/networks.json")

function require_phases_calldata() {
	local phases=$1
	if [[ ! "$phases" =~ ^[0-9]+$ ]] || (( phases == 0 )); then
		echo "PHASES must be a positive bitmask, got: '$phases'" >&2
		exit 1
	fi
	if (( phases & 1 )) && [[ -z "${PHASE1_CALLDATA:-}" ]]; then
		echo "PHASES=$phases requires PHASE1_CALLDATA (framework updateContracts)" >&2
		exit 1
	fi
	if (( phases & 2 )) && [[ -z "${PHASE2_CALLDATA:-}" ]]; then
		echo "PHASES=$phases requires PHASE2_CALLDATA (batchUpdateSuperTokenLogic)" >&2
		exit 1
	fi
}

# takes the network name as argument
function test_network() {
	local network=$1

	local rpc=${RPC:-"https://${network}.rpc.x.superfluid.dev"}

	echo "=============== Testing $network... ==================="

	local host seth
	host=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").contractsV1.host')
	seth=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").nativeTokenWrapper')

	echo "Host: $host"
	echo "Native Token Wrapper: $seth"

	local PHASES="" PHASE1_CALLDATA="" PHASE2_CALLDATA=""
	PHASES=${user_phases-}
	PHASE1_CALLDATA=${user_p1-}
	PHASE2_CALLDATA=${user_p2-}

	if [[ -z "$PHASE1_CALLDATA" && -z "$PHASE2_CALLDATA" ]]; then
		local detected
		detected=$("$GET_SAFE" --detect "$network")
		eval "$detected"
		if [[ -n "$user_phases" ]]; then
			PHASES=$user_phases
		fi
	elif [[ -z "$PHASES" ]]; then
		echo "PHASE1_CALLDATA/PHASE2_CALLDATA set but PHASES is missing" >&2
		exit 1
	fi

	require_phases_calldata "$PHASES"
	echo "PHASES=$PHASES"

	RPC=$rpc HOST_ADDR=$host NATIVE_TOKEN_WRAPPER=$seth \
		PHASES="$PHASES" \
		PHASE1_CALLDATA="${PHASE1_CALLDATA-}" \
		PHASE2_CALLDATA="${PHASE2_CALLDATA-}" \
		forge test --match-contract "^${testContract}$" "${extraArgs[@]}"
}

if [[ $networkOrNetworkClass == "mainnets" ]]; then
	echo "looping over all mainnets"
	names=$(echo "$metadata" | jq -r '.[] | select(.isTestnet == false).name')
	for name in $names; do
		test_network $name
	done
else
	test_network $networkOrNetworkClass
fi
