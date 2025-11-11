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

Example for how to run with a Safe multisig:
```sh
NETWORK=base-mainnet; PHASES=3 PHASE1_CALLDATA=$(./get-safe-calldata.py $NETWORK 1) PHASE2_CALLDATA=$(./get-safe-calldata.py $NETWORK 0) scripts/run_test.sh $NETWORK Upgrade_1_14_1 --match-test testWithUpgrade -vvv
```
