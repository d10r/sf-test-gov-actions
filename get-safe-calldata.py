#!/usr/bin/env python3

# prerequisites: pip install requests eth_utils

# usage:
#   ./get-safe-calldata.py <NETWORK_NAME> [OFFSET] [SAFE_ADDRESS]
#     OFFSET: index into pending txs (default 0 = most recent)
#     SAFE_ADDRESS: optional; when set, query this Safe instead of the gov Safe
#     stdout: raw calldata (hex)
#   ./get-safe-calldata.py --detect <NETWORK_NAME> [SAFE_ADDRESS]
#     Classify the executable pending-nonce queue as a protocol upgrade.
#     stdout: bash assignments for PHASES, PHASE1_CALLDATA, PHASE2_CALLDATA

import sys
import os
import re
import time
import requests
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

HEX_CALLDATA = re.compile(r'^0x[0-9a-fA-F]*$')


def sel(sig):
    return '0x' + keccak(text=sig)[:4].hex()


SELECTOR_UPDATE_CONTRACTS = sel('updateContracts(address,address,address[],address,address)')
SELECTOR_BATCH_UPDATE_TOKENS = sel('batchUpdateSuperTokenLogic(address,address[])')
SELECTOR_BATCH_UPDATE_TOKENS_WITH_LOGIC = sel('batchUpdateSuperTokenLogic(address,address[],address[])')

FRAMEWORK_SELECTORS = {SELECTOR_UPDATE_CONTRACTS: 'updateContracts'}
TOKEN_SELECTORS = {
    SELECTOR_BATCH_UPDATE_TOKENS: 'batchUpdateSuperTokenLogic',
    SELECTOR_BATCH_UPDATE_TOKENS_WITH_LOGIC: 'batchUpdateSuperTokenLogic',
}


def err(msg):
    print(msg, file=sys.stderr)
    exit(1)


def log(msg):
    print(msg, file=sys.stderr)


def api_headers():
    api_key = os.environ.get('SAFE_API_KEY')
    headers = {}
    if api_key:
        headers['Authorization'] = 'Bearer %s' % api_key
    return headers


def get_json(url, headers, attempts=5):
    delay = 1.0
    last_status = None
    last_body = ''
    for _ in range(attempts):
        r = requests.get(url, headers=headers, timeout=30)
        last_status = r.status_code
        last_body = r.text[:300]
        if r.status_code == 429:
            log("Safe API rate limited, retrying in %.1fs..." % delay)
            time.sleep(delay)
            delay *= 2
            continue
        if r.status_code != 200:
            err("Safe API %s: HTTP %s %s" % (url, r.status_code, last_body))
        return r.json()
    err("Safe API %s: HTTP %s %s" % (url, last_status, last_body))


def tx_selector(tx):
    data = tx.get('data') or ''
    if not isinstance(data, str) or len(data) < 10:
        return None
    return data[:10].lower()


def tx_kind(tx):
    s = tx_selector(tx)
    if s in FRAMEWORK_SELECTORS:
        return 'framework', FRAMEWORK_SELECTORS[s]
    if s in TOKEN_SELECTORS:
        return 'tokens', TOKEN_SELECTORS[s]
    return 'other', s or 'none'


def describe_tx(tx):
    kind, name = tx_kind(tx)
    return "nonce=%s kind=%s %s to=%s" % (
        tx.get('nonce'), kind, name, tx.get('to'),
    )


def fetch_next_nonce(base_url, safe, headers):
    payload = get_json(
        '%s/api/v2/safes/%s/multisig-transactions?executed=true&limit=1' % (base_url, safe),
        headers,
    )
    results = payload.get('results') or []
    if not results:
        return 0
    return int(results[0]['nonce']) + 1


def fetch_pending(base_url, safe, headers):
    payload = get_json(
        '%s/api/v2/safes/%s/multisig-transactions?executed=false&limit=100' % (base_url, safe),
        headers,
    )
    results = payload.get('results') or []
    count = payload.get('count', len(results))
    if count > len(results):
        log("warning: Safe API returned %s of %s pending txs; using the returned page" % (
            len(results), count
        ))
    return results


def consecutive_prefix(pending, next_nonce):
    by_nonce = sorted(pending, key=lambda tx: int(tx['nonce']))
    executable = [tx for tx in by_nonce if int(tx['nonce']) >= next_nonce]
    if not executable:
        err("No pending transactions at or after next nonce %s" % next_nonce)
    first_nonce = int(executable[0]['nonce'])
    if first_nonce != next_nonce:
        err("nonce gap: next nonce is %s but earliest pending is %s" % (next_nonce, first_nonce))
    prefix = []
    expected = next_nonce
    for tx in executable:
        nonce = int(tx['nonce'])
        if nonce != expected:
            break
        prefix.append(tx)
        expected += 1
    return prefix


def quote_calldata(data):
    if not data:
        return "''"
    if not HEX_CALLDATA.match(data):
        err("refusing to emit non-hex calldata: %s" % data[:66])
    return "'%s'" % data


def emit_env(phases, phase1, phase2):
    print("PHASES=%d" % phases)
    print("PHASE1_CALLDATA=%s" % quote_calldata(phase1))
    print("PHASE2_CALLDATA=%s" % quote_calldata(phase2))


def detect_upgrade(network, safe_arg):
    if not network or network not in NETWORK_TO_SAFE_NAME:
        err("No config available for this network: %s" % network)
    safe = safe_arg if safe_arg else DEFAULT_SAFE_ADDRESS
    headers = api_headers()
    base_url = 'https://api.safe.global/tx-service/%s' % NETWORK_TO_SAFE_NAME[network]
    next_nonce = fetch_next_nonce(base_url, safe, headers)
    pending = fetch_pending(base_url, safe, headers)
    if not pending:
        err("No pending transactions found")
    prefix = consecutive_prefix(pending, next_nonce)

    first = prefix[0]
    first_kind, first_name = tx_kind(first)
    log("get-safe-calldata --detect: Safe=%s next_nonce=%s" % (safe, next_nonce))
    log("  queue[0]: %s safeTxHash=%s" % (describe_tx(first), first.get('safeTxHash', 'N/A')))

    phase1 = None
    phase2 = None
    used = 1
    if first_kind == 'framework':
        phase1 = first.get('data')
        if not phase1:
            err("updateContracts tx has empty data: %s" % describe_tx(first))
        if len(prefix) > 1:
            second_kind, second_name = tx_kind(prefix[1])
            log("  queue[1]: %s safeTxHash=%s" % (
                describe_tx(prefix[1]), prefix[1].get('safeTxHash', 'N/A')
            ))
            if second_kind == 'tokens':
                phase2 = prefix[1].get('data')
                if not phase2:
                    err("batchUpdateSuperTokenLogic tx has empty data: %s" % describe_tx(prefix[1]))
                used = 2
            else:
                log("  ignoring nonce=%s (%s); not batchUpdateSuperTokenLogic" % (
                    prefix[1].get('nonce'), second_name
                ))
        phases = 3 if phase2 else 1
    elif first_kind == 'tokens':
        phase2 = first.get('data')
        if not phase2:
            err("batchUpdateSuperTokenLogic tx has empty data: %s" % describe_tx(first))
        phases = 2
    else:
        err("next pending tx is not a protocol upgrade: %s" % describe_tx(first))

    for tx in prefix[used:]:
        log("  ignored: %s" % describe_tx(tx))

    log("  detected PHASES=%s" % phases)
    emit_env(phases, phase1, phase2)


def print_offset_calldata(network, offset_arg, safe_arg):
    if not network or network not in NETWORK_TO_SAFE_NAME:
        err("No config available for this network: %s" % network)
    try:
        offset = int(offset_arg) if offset_arg is not None else 0
    except (ValueError, IndexError):
        err("Offset must be an integer")
    if offset < 0:
        err("Offset must be non-negative")

    safe = safe_arg if safe_arg else DEFAULT_SAFE_ADDRESS
    headers = api_headers()
    base_url = 'https://api.safe.global/tx-service/%s' % NETWORK_TO_SAFE_NAME[network]
    next_nonce = fetch_next_nonce(base_url, safe, headers)
    pending = fetch_pending(base_url, safe, headers)
    if not pending:
        err("No pending transactions found")
    if offset >= len(pending):
        err("Requested offset %s but only %s pending transactions available" % (offset, len(pending)))

    selected = pending[offset]
    nonce = int(selected['nonce'])
    log("get-safe-calldata: Safe=%s offset=%s nonce=%s safeTxHash=%s" % (
        safe, offset, nonce, selected.get('safeTxHash', 'N/A')
    ))
    if safe == DEFAULT_SAFE_ADDRESS and offset_arg is None and offset == 0 and nonce != next_nonce:
        err("nonce of last pending tx (%s) not equal to next nonce (%s)" % (nonce, next_nonce))
    calldata = selected['data']
    print(calldata)


def usage():
    err(
        "usage:\n"
        "  ./get-safe-calldata.py <NETWORK> [OFFSET] [SAFE_ADDRESS]\n"
        "  ./get-safe-calldata.py --detect <NETWORK> [SAFE_ADDRESS]"
    )


def main(argv):
    args = argv[1:]
    if not args or args[0] in ('-h', '--help'):
        usage()
    if args[0] in ('--detect', '-d'):
        rest = args[1:]
        network = rest[0] if rest else None
        safe_arg = rest[1] if len(rest) > 1 else None
        detect_upgrade(network, safe_arg)
        return
    network = args[0] if args else None
    offset_arg = args[1] if len(args) > 1 else None
    safe_arg = args[2] if len(args) > 2 else None
    print_offset_calldata(network, offset_arg, safe_arg)


if __name__ == '__main__':
    main(sys.argv)
