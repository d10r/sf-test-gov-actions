#!/bin/bash

# usage: run-UpgradeTokens.sh <network> | mainnets

set -eu

networkOrNetworkClass=$1

metadata=$(curl -s "https://raw.githubusercontent.com/superfluid-finance/metadata/master/networks.json")

# takes the network name as argument
function test_network() {
	network=$1

	tokenlistFile=${TOKEN_LIST_FILE:-"input/$network.tokens"}
	[[ -f $tokenlistFile ]] || { echo "token list file $tokenlistFile not found"; exit 1; }

	rpc=${RPC:-"https://${network}.rpc.x.superfluid.dev"}

	echo "=============== Testing $network... ==================="

	# get current metadata

	host=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").contractsV1.host')
	seth=$(echo "$metadata" | jq -r '.[] | select(.name == "'$network'").nativeTokenWrapper')

	# Print the host address
	echo "Host: $host"
	echo "Native Token Wrapper: $seth"

#	tokenList=$(jq -r '.[]' $tokenlistFile | tr '\n' ',' | sed 's/,$//')
#	echo "token list: $tokenList"

	TOKEN_LIST_FILE=$tokenlistFile RPC=$rpc HOST_ADDR=$host NATIVE_TOKEN_WRAPPER=$seth forge test --match-contract UpgradeTokens -vvv
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


