## How to run

* install foundry
* `ln -sf /path/to/your/protocol-monorepo sf` 
* `ln -sf /path/to/your/cft-nft-contracts cfanft`
* `forge test`

## Tests

### CFAHookTest
Deploys an instance of FlowNFT.
Forks Polygon, deploys a new instance of `ConstantFlowAgreementV1` and upgrades to it using `Superfluid.updateAgreementClass`, setting the FlowNFT contract up as `IConstantFlowAgreementHook` receiver.
