#!/usr/bin/env python3

# prerequisites: pip install requests eth_account eth_utils

# returns the calldata of a pending tx for a given safe
# usage: ./get-safe-calldata.py <NETWORK_NAME> [OFFSET] [SAFE_ADDRESS]
#   OFFSET: index into pending txs (default 0 = most recent)
#   SAFE_ADDRESS: optional; when set, query this Safe instead of the gov Safe

import sys
import os
import requests
from eth_account import Account
from eth_utils import keccak

# Mapping from canonical network names (from networks.json "name" field) to Safe network identifiers
# Based on Safe Transaction Service API v2: https://api.safe.global/tx-service/{network}/api/v2/...
# Reference: https://docs.safe.global/advanced/smart-account-supported-networks?service=Transaction+Service
NETWORK_TO_SAFE_NAME = {
    # Mainnets
    'eth-mainnet': 'eth',
    'base-mainnet': 'base',
    'polygon-mainnet': 'pol',
    'avalanche-c': 'avax',
    'optimism-mainnet': 'oeth',
    'arbitrum-one': 'arb1',
    'xdai-mainnet': 'gno',
    'bsc-mainnet': 'bnb',
    'celo-mainnet': 'celo',
    'scroll-mainnet': 'scr',
}

# gov owner Safe address (same across all networks)
DEFAULT_SAFE_ADDRESS = '0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6'

NETWORK = sys.argv[1] if len(sys.argv) > 1 else None
offset_arg = sys.argv[2] if len(sys.argv) > 2 else None
safe_arg = sys.argv[3] if len(sys.argv) > 3 else None
def err(msg):
    print(msg, file=sys.stderr)
    exit(1)

try:
    OFFSET = int(offset_arg) if offset_arg is not None else 0
except (ValueError, IndexError):
    err("Offset must be an integer")
if OFFSET < 0:
    err("Offset must be non-negative")
if not NETWORK or NETWORK not in NETWORK_TO_SAFE_NAME:
    err("No config available for this network: %s" % NETWORK)

safe_network_name = NETWORK_TO_SAFE_NAME[NETWORK]
baseUrl = f'https://api.safe.global/tx-service/{safe_network_name}'
safe = safe_arg if safe_arg else DEFAULT_SAFE_ADDRESS

# Get API key from environment variable
api_key = os.environ.get('SAFE_API_KEY')
headers = {}
if api_key:
    headers['Authorization'] = f'Bearer {api_key}'

# get the next_nonce of the last executed tx (only used for default gov Safe when offset not explicit)
last_executed_txs = requests.get(f'{baseUrl}/api/v2/safes/{safe}/multisig-transactions?executed=true&limit=1', headers=headers)
last_executed_tx = last_executed_txs.json()['results'][0] if last_executed_txs.json()['results'] else None
next_nonce = int(last_executed_tx['nonce']) + 1 if last_executed_tx else 0

pending_txs = requests.get(f'{baseUrl}/api/v2/safes/{safe}/multisig-transactions?executed=false', headers=headers)
pending_results = pending_txs.json()['results']
if not pending_results:
    err("No pending transactions found")

if OFFSET >= len(pending_results):
    err("Requested offset %s but only %s pending transactions available" % (OFFSET, len(pending_results)))

selected_pending_tx = pending_results[OFFSET]
nonce_of_selected_pending_tx = int(selected_pending_tx['nonce'])
safe_tx_hash = selected_pending_tx.get('safeTxHash', 'N/A')

# always log which tx is being fetched (stderr so stdout stays calldata only)
print("get-safe-calldata: Safe=%s offset=%s nonce=%s safeTxHash=%s" % (
    safe, OFFSET, nonce_of_selected_pending_tx, safe_tx_hash
), file=sys.stderr)

# only check next_nonce for default gov Safe when offset was not explicitly passed
if safe == DEFAULT_SAFE_ADDRESS and offset_arg is None and OFFSET == 0 and nonce_of_selected_pending_tx != next_nonce:
    err("nonce of last pending tx (%s) not equal to next nonce (%s)" % (nonce_of_selected_pending_tx, next_nonce))

calldata = selected_pending_tx['data']

print(calldata)
