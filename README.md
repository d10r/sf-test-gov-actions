## How to run

* install foundry
* `ln -sf /path/to/your/protocol-monorepo sf`

In `scripts` there's helper scripts for running the tests.

Example invocation:
```sh
# arguments: network_name, test_contract
NETWORK=polygon-mainnet; PHASE=3 scripts/run_test.sh $NETWORK Upgrade_1_9 -vv
```

In order to upgrade foundry, checkout https://github.com/foundry-rs/forge-std and place it in lib