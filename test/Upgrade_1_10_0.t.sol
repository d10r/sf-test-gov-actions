// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

/*
* Upgrade to 1.10.0
* - fixes pools self-transfer (forbidden)
* - adds batch operations (require token upgrade)
* - adds batch operations using dmzforwarder
* - increase app callback limit
*/

import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import { DMZForwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/DMZForwarder.sol";
import "./lib/UpgradeBase.sol";

using SuperTokenV1Library for ISuperToken;

contract Upgrade_1_10_0 is UpgradeBase {
    function testUpgrade() public {
        int phases = vm.envInt("PHASES");
        //bytes memory govCallData = vm.envOr("GOV_CALLDATA", new bytes(0));
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
        if (phases & 2 != 0) {
            console.log("testing phase 2 - upgrade super tokens");
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase2(TOKEN_UPGRADE_TX_ID, phase2CallData);
        }
    }

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal {
        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        uint256 oldCallbackGasLimit = Superfluid(address(host)).CALLBACK_GAS_LIMIT();
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(frameworkUpdateTxId);
        }
        printBeaconCodeAddress("+++ pool master address after update", address(gda.superfluidPoolBeacon()));

        uint256 newCallbackGasLimit = Superfluid(address(host)).CALLBACK_GAS_LIMIT();
        assertGe(newCallbackGasLimit, oldCallbackGasLimit, "callback gas limit shall not decrease!");

        DMZForwarder dmzFwd = DMZForwarder(Superfluid(address(host)).DMZ_FORWARDER());
        assertEq(dmzFwd.owner(), address(host), "dmzFwd owner shall be host");
        console.log("dmzForwarder address: %s", address(dmzFwd));

        smokeTestNativeTokenWrapper();

        smokeTestGDA();

        console.log("callback gas limit: %s", Superfluid(address(host)).CALLBACK_GAS_LIMIT());
    }

    function _phase2(uint tokenUgradeTxId, bytes memory govCallData) internal {
        console.log("executing token upgrade tx id %s", tokenUgradeTxId);

        printUUPSCodeAddress("--- native token wrapper logic address before update", NATIVE_TOKEN_WRAPPER);
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(tokenUgradeTxId);
        }
        printUUPSCodeAddress("+++ native token wrapper logic address after update", NATIVE_TOKEN_WRAPPER);
        assertEq(UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress(), address(factory.getSuperTokenLogic()));

        smokeTestNativeTokenWrapper();

        smokeTestGDA();
    }
}
