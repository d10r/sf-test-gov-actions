## How to run

* install foundry
* `ln -sf /path/to/your/protocol-monorepo sf` 
* `ln -sf /path/to/your/cft-nft-contracts cfanft`
* `forge test`

In order to upgrade foundry, checkout https://github.com/foundry-rs/forge-std and place it in lib

In `scripts` there's helper scripts for running the tests.

Example invocation:
```sh
# arguments: network_name, test_contract
scripts/run_test.sh celo-mainnet Upgrade_1_8
```

## Tests

### CFAHookTest
Deploys an instance of FlowNFT.
Forks Polygon, deploys a new instance of `ConstantFlowAgreementV1` and upgrades to it using `Superfluid.updateAgreementClass`, setting the FlowNFT contract up as `IConstantFlowAgreementHook` receiver.

Run specific test contract:
forge test --match-contract UpgradeGovAction

examples
```
RPC=https://celo-mainnet... HOST_ADDR=0xA4Ff07cF81C02CFD356184879D953970cA957585 NATIVE_TOKEN_WRAPPER=0x671425Ae1f272Bc6F79beC3ed5C4b00e9c628240 TXID=3 forge test --match-contract Upgrade_1_7 -vvv
```

### UpgradeTokens

smoke tests (start and stop stream) SuperTokens before and after upgrading.

### UpgradeContracts

Simulates the upgrade to a given set of logic contracts (host logic, agreement logics, supertoken factory logic).  
Directly impersonates gov, ignoring an eventual multisig setup

### Upgrade_x_y

Upgrade to a specific release, simluates execution of the gov action(s), may contain additional tests specific for that upgrade.