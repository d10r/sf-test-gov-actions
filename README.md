## How to run

* install foundry
* `ln -sf /path/to/your/protocol-monorepo sf`

In `scripts` there's helper scripts for running the tests.

Example invocation:
```sh
# arguments: network_name, test_contract
# Fetches pending gov Safe txs and sets PHASES + calldata:
#   updateContracts → phase 1, batchUpdateSuperTokenLogic → phase 2
scripts/run_test.sh xdai-mainnet Upgrade_1_15_0_hotfix --match-test testWithUpgrade -vv
scripts/run_test.sh base-mainnet Upgrade_1_15_0 --match-test testWithUpgrade -vv
```

`PHASES` is a bitmask (1 = framework, 2 = tokens). Override autodetection with `PHASES` and/or `PHASE1_CALLDATA` / `PHASE2_CALLDATA`:
```sh
PHASES=1 scripts/run_test.sh xdai-mainnet Upgrade_1_15_0_hotfix --match-test testWithUpgrade -vv
PHASES=3 PHASE1_CALLDATA=0x... PHASE2_CALLDATA=0x... scripts/run_test.sh base-mainnet Upgrade_1_15_0 --match-test testWithUpgrade -vv
```

### Yield backend activation fork test

Tests the two-step flow (gov Safe: changeSuperTokenAdmin; SuperToken Admin Safe: enableYieldBackend) on a fork. Uses two different Safes; calldata is fetched from the Safe Transaction Service.

```sh
# From repo root: <NETWORK> <SUPER_TOKEN> <YIELD_BACKEND> (required)
scripts/run_yield_backend_test.sh eth-mainnet 0x1BA8603DA702602A8657980e825A6DAa03Dee93a 0x818fbe37EcFee8b981dD1a2Bb2C292EEBE0AB21E

# Native-asset SuperToken (e.g. ETHx) + AaveETHYieldBackend: SUPER_TOKEN is the ETHx (ISETH) proxy;
# YIELD_BACKEND is the deployed AaveETHYieldBackend for that chain.
# scripts/run_yield_backend_test.sh base-mainnet 0x'<ETHx>' 0x'<AaveETHYieldBackend>'
```

With pre-set calldata (e.g. for CI or when Safe API is unavailable):
```sh
GOV_CALLDATA=0x... SUPER_TOKEN_ADMIN_CALLDATA=0x... scripts/run_yield_backend_test.sh eth-mainnet 0x... 0x...
```

Optional env overrides: `SUPER_TOKEN_ADMIN`, `GOV_CALLDATA_OFFSET` (index of the changeSuperTokenAdmin tx in the gov Safe pending list).
