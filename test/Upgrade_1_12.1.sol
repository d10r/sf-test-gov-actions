// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

/*
* Upgrade to 1.12.0
* - fix SimpleForwarder
* - Pool metadata
*
* Actions:
* verify the forwarders have the host as owner
* verify: pool created before upgrade has default metadata after update
* verify: pool created after upgrade has default metadata after update
* verify: pool created with custom metadata has correct metadata after update
*/

import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import "./lib/UpgradeBase.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

using SuperTokenV1Library for ISuperToken;
using SuperTokenV1Library for ISETH;

contract Upgrade_1_12_1 is UpgradeBase {
    function testUpgrade() public {
        int phases = vm.envInt("PHASES");
        bytes memory phase1CallData = vm.envOr("PHASE1_CALLDATA", new bytes(0));
        bytes memory phase2CallData = vm.envOr("PHASE2_CALLDATA", new bytes(0));
        uint lastTxId = (phase1CallData.length > 0 || phase2CallData.length > 0) ? 0xffffffff : getLastMultisigTxId();
        console.log("last multisig tx id: %s", lastTxId);

        if (phases & 1 != 0) {
            console.log("testing phase 1 - upgrade framework");
            uint FRAMEWORK_UPDATE_TX_ID = vm.envOr(
                "FRAMEWORK_UPDATE_TX_ID",
                phases & 2 != 0 ? lastTxId - 1 : lastTxId
            );
            _phase1(FRAMEWORK_UPDATE_TX_ID, phase1CallData);
        }
    }

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal {
        preCheck();

        ISuperfluidPool poolPreUpgrade = ethx.createPool();

        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(frameworkUpdateTxId);
        }
        postCheck();

        ISuperfluidPool poolPostUpgrade = ethx.createPool();

        ISuperfluidPool poolWithCustomMetadata = gda.createPoolWithCustomERC20Metadata(
            ethx,
            address(this),
            PoolConfig(true, true),
            PoolERC20Metadata("My Pool", "MPL", 6)
        );

        assertEq(poolPreUpgrade.name(), "Superfluid Pool", "pre upgrade pool name");
        assertEq(poolPreUpgrade.symbol(), "POOL", "pre upgrade pool symbol");
        assertEq(poolPreUpgrade.decimals(), 0, "pre upgrade pool decimals");

        assertEq(poolPostUpgrade.name(), "Superfluid Pool", "post upgrade pool name");
        assertEq(poolPostUpgrade.symbol(), "POOL", "post upgrade pool symbol");
        assertEq(poolPostUpgrade.decimals(), 0, "post upgrade pool decimals");

        assertEq(poolWithCustomMetadata.name(), "My Pool", "custom metadata pool name");
        assertEq(poolWithCustomMetadata.symbol(), "MPL", "custom metadata pool symbol");
        assertEq(poolWithCustomMetadata.decimals(), 6, "custom metadata pool decimals");

        address simpleForwarder = address(Superfluid(address(host)).SIMPLE_FORWARDER());
        assertFalse(simpleForwarder == address(0), "simple forwarder not set");
        assertEq(Ownable(simpleForwarder).owner(), address(host), "simple forwarder wrong owner");

        smokeTestNativeTokenWrapper();

        smokeTestGDA();

        console.log("callback gas limit: %s", Superfluid(address(host)).CALLBACK_GAS_LIMIT());
    }
}
