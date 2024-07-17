## How to run

* install foundry
* `ln -sf /path/to/your/protocol-monorepo sf`

In `scripts` there's helper scripts for running the tests.

Example invocation:
```sh
# arguments: network_name, test_contract
NETWORK=optimism-mainnet; PHASES=3 scripts/run_test.sh $NETWORK Upgrade_1_9_1 -vv
```
Here, `PHASES=3` stands for 1 & 2 (bitmask).

Invocation for a network using Safe:
```sh
NETWORK=base-mainnet; PHASE1_CALLDATA=$(cat base-mainnet_phase1.calldata) PHASE2_CALLDATA=$(cat base-mainnet_phase2.calldata) PHASES=3 scripts/run_test.sh $NETWORK Upgrade_1_9_1 -vv
```

By default, foundry runs the an evm with `evm-version` set to `paris`.
Some custom Super Tokens are now deployed using `shanghai` feature set, causing tests for fail with [EvmError: NotActivated](https://github.com/foundry-rs/foundry/issues/6228).
Run the test with `--evm-version shanghai` if the underlying chain supports that. In July 2024, all SF chains except celo-mainnet support the Shanghai feature set (incl. PUSH0).

In order to upgrade foundry, checkout https://github.com/foundry-rs/forge-std and place it in lib