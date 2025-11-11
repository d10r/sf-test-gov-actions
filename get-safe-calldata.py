#!/usr/bin/env python3

# prerequisites: pip install requests eth_account eth_utils

# returns the calldata of the last pending tx for a given safe
# usage: ./get-calldata.py <NETWORK_NAME>

import sys
import requests
from eth_account import Account
from eth_utils import keccak

GOV_SAFES = {
    'base-mainnet': {
        'baseUrl': 'https://safe-transaction-base.safe.global',
        'safe': '0xD8A05F504b5Ce16183D3e1e16FD6A365a8db53da',
    },
    'polygon-mainnet': {
        'baseUrl': 'https://safe-transaction-polygon.safe.global',
        'safe': '0xf0aCd3efFd0ca4c84239eFcD664723C6feab403F',
    },
}

NETWORK = sys.argv[1] if len(sys.argv) > 1 else None
offset_arg = sys.argv[2] if len(sys.argv) > 2 else None
try:
    OFFSET = int(offset_arg) if offset_arg is not None else 0
except (ValueError, IndexError):
    print("Offset must be an integer")
    exit(1)
if OFFSET < 0:
    print("Offset must be non-negative")
    exit(1)
if not NETWORK or NETWORK not in GOV_SAFES:
    print("No config available for this network: %s" % NETWORK)
    exit(1)

baseUrl = GOV_SAFES[NETWORK]['baseUrl']
safe = GOV_SAFES[NETWORK]['safe']

# get the next_nonce of the last executed tx
# example url for getting the last executed tx: /api/v1/safes/0xD8A05F504b5Ce16183D3e1e16FD6A365a8db53da/multisig-transactions/?executed=true&limit=1
last_executed_txs = requests.get(f'{baseUrl}/api/v1/safes/{safe}/multisig-transactions?executed=true&limit=1')
last_executed_tx = last_executed_txs.json()['results'][0] if last_executed_txs.json()['results'] else None
next_nonce = last_executed_tx['nonce'] + 1 if last_executed_tx else 0

pending_txs = requests.get(f'{baseUrl}/api/v1/safes/{safe}/multisig-transactions?executed=false')
pending_results = pending_txs.json()['results']
if not pending_results:
    print("No pending transactions found")
    exit(1)

if OFFSET >= len(pending_results):
    print("Requested offset %s but only %s pending transactions available" % (OFFSET, len(pending_results)))
    exit(1)

selected_pending_tx = pending_results[OFFSET]
nonce_of_selected_pending_tx = selected_pending_tx['nonce']

if offset_arg is None and OFFSET == 0 and nonce_of_selected_pending_tx != next_nonce:
    print("nonce of last pending tx (%s) not equal to next nonce (%s)" % (nonce_of_selected_pending_tx, next_nonce))
    exit(1)

calldata = selected_pending_tx['data']

print(calldata)

