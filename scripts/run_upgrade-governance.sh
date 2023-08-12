#!/bin/bash

# usage: run-UpgradeTokens.sh <network> | mainnets

set -eu

networkOrNetworkClass=$1

metadata=$(curl -s "https://raw.githubusercontent.com/superfluid-finance/protocol-monorepo/dev/packages/metadata/networks.json")

# takes the network name as argument
function test_network() {
	network=$1

	rpc=${RPC:-"https://${network}.rpc.x.superfluid.dev"}

	echo "=============== Testing $network... ==================="

	# get current metadata

	host=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").contractsV1.host')
	seth=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").nativeTokenWrapper')

	# Print the host address
	echo "Host: $host"
    echo "Native Token Wrapper: $seth"

	RPC=$rpc HOST_ADDR=$host NATIVE_TOKEN_WRAPPER=$seth forge test --match-contract UpgradeGovernance -vvv
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


