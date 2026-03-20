#!/bin/bash
#
# Fork test for yield backend activation (two Safes: gov + SuperToken admin).
# Usage: scripts/run_yield_backend_test.sh <NETWORK> <SUPER_TOKEN> <YIELD_BACKEND> [optional env overrides]
#
# Required args: NETWORK, SUPER_TOKEN, YIELD_BACKEND.
#
# Native-asset SuperTokens (ETHx, etc.): use the ETHx (ISETH) address as SUPER_TOKEN and an
# AaveETHYieldBackend (or compatible) address as YIELD_BACKEND. Tests use ETH balances and
# upgradeByETH/downgradeToETH automatically when getUnderlyingToken() is zero.
# Optional env:
#   SUPER_TOKEN_ADMIN (default: gov Safe)
#   GOV_CALLDATA_OFFSET (default 0, or 1 when admin Safe == gov Safe) — index of changeSuperTokenAdmin
#   SUPER_TOKEN_ADMIN_CALLDATA_OFFSET (default 0, or 0 when same Safe) — index of enableYieldBackend
# When SuperToken admin is the same Safe as gov owner, that Safe has 2 pending txs (typically
# offset 0 = enableYieldBackend, offset 1 = changeSuperTokenAdmin); the script defaults accordingly.
# If GOV_CALLDATA and SUPER_TOKEN_ADMIN_CALLDATA are already set, skips fetching (for CI/manual).
#
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK="${1:?Usage: scripts/run_yield_backend_test.sh <NETWORK> <SUPER_TOKEN> <YIELD_BACKEND>}"
SUPER_TOKEN="${2:?Usage: scripts/run_yield_backend_test.sh <NETWORK> <SUPER_TOKEN> <YIELD_BACKEND>}"
YIELD_BACKEND="${3:?Usage: scripts/run_yield_backend_test.sh <NETWORK> <SUPER_TOKEN> <YIELD_BACKEND>}"

GOV_SAFE="${GOV_SAFE:-0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6}"
SUPER_TOKEN_ADMIN="${SUPER_TOKEN_ADMIN:-0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6}"
# When admin Safe == gov Safe, there are 2 pending txs: offset 0 = enableYieldBackend, offset 1 = changeSuperTokenAdmin
if [[ "$(echo "$SUPER_TOKEN_ADMIN" | tr '[:upper:]' '[:lower:]')" == "$(echo "$GOV_SAFE" | tr '[:upper:]' '[:lower:]')" ]]; then
    GOV_CALLDATA_OFFSET="${GOV_CALLDATA_OFFSET:-1}"
    SUPER_TOKEN_ADMIN_CALLDATA_OFFSET="${SUPER_TOKEN_ADMIN_CALLDATA_OFFSET:-0}"
else
    GOV_CALLDATA_OFFSET="${GOV_CALLDATA_OFFSET:-0}"
    SUPER_TOKEN_ADMIN_CALLDATA_OFFSET="${SUPER_TOKEN_ADMIN_CALLDATA_OFFSET:-0}"
fi

metadata=$(curl -s "https://raw.githubusercontent.com/superfluid-finance/protocol-monorepo/dev/packages/metadata/networks.json")
rpc="${RPC:-https://${NETWORK}.rpc.x.superfluid.dev}"
host=$(echo "$metadata" | jq -r '.[] | select(.name == "'"$NETWORK"'").contractsV1.host')
seth=$(echo "$metadata" | jq -r '.[] | select(.name == "'"$NETWORK"'").nativeTokenWrapper')

if [[ -z "$host" || "$host" == "null" ]]; then
    echo "Network $NETWORK not found in metadata" >&2
    exit 1
fi

echo "=============== YieldBackendActivation fork test: $NETWORK ==================="
echo "RPC: $rpc"
echo "Host: $host"
echo "SuperToken: $SUPER_TOKEN"
echo "SuperToken Admin: $SUPER_TOKEN_ADMIN"
echo "YieldBackend: $YIELD_BACKEND"

if [[ -z "${GOV_CALLDATA:-}" || -z "${SUPER_TOKEN_ADMIN_CALLDATA:-}" ]]; then
    echo "Fetching calldata from Safe Transaction Service..."
    if [[ -z "${GOV_CALLDATA:-}" ]]; then
        GOV_CALLDATA=$("$REPO_ROOT/get-safe-calldata.py" "$NETWORK" "$GOV_CALLDATA_OFFSET" | tr -d '\n') || true
        [[ -n "$GOV_CALLDATA" ]] || { echo "Failed to fetch gov calldata (check get-safe-calldata output above)" >&2; exit 1; }
        echo "Gov Safe calldata (offset $GOV_CALLDATA_OFFSET) length: ${#GOV_CALLDATA}"
    fi
    if [[ -z "${SUPER_TOKEN_ADMIN_CALLDATA:-}" ]]; then
        SUPER_TOKEN_ADMIN_CALLDATA=$("$REPO_ROOT/get-safe-calldata.py" "$NETWORK" "$SUPER_TOKEN_ADMIN_CALLDATA_OFFSET" "$SUPER_TOKEN_ADMIN" | tr -d '\n') || true
        [[ -n "$SUPER_TOKEN_ADMIN_CALLDATA" ]] || { echo "Failed to fetch SuperToken Admin calldata (check get-safe-calldata output above)" >&2; exit 1; }
        echo "SuperToken Admin Safe calldata (offset $SUPER_TOKEN_ADMIN_CALLDATA_OFFSET) length: ${#SUPER_TOKEN_ADMIN_CALLDATA}"
    fi
else
    echo "Using existing GOV_CALLDATA and SUPER_TOKEN_ADMIN_CALLDATA from env"
fi

cd "$REPO_ROOT"
RPC=$rpc \
HOST_ADDR=$host \
NATIVE_TOKEN_WRAPPER=$seth \
SUPER_TOKEN=$SUPER_TOKEN \
YIELD_BACKEND=$YIELD_BACKEND \
SUPER_TOKEN_ADMIN=$SUPER_TOKEN_ADMIN \
GOV_CALLDATA="$GOV_CALLDATA" \
SUPER_TOKEN_ADMIN_CALLDATA="$SUPER_TOKEN_ADMIN_CALLDATA" \
forge test --match-contract YieldBackendActivation -vvv
