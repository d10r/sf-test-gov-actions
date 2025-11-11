// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import "./lib/UpgradeBase.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";
import { IAccessControl } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

using SuperTokenV1Library for ISuperToken;
using SuperTokenV1Library for ISETH;


/*
v1.14.1:
2 actions: framework upgrade + token upgrade
- pool authentication fix (regression test)
- pseudo transfer event

test that the new upgrade script works as expected.
E.g. if the pool logic constructor got gda logic instead of gda proxy, something should fail.
In order to achieve that, do a comprehensive smoke test.
*/
contract Upgrade_1_14_1 is UpgradeBase {

    function testWithUpgrade() public {
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
        if (phases & 2 != 0) {
            console.log("testing phase 2 - upgrade super tokens");
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase2(TOKEN_UPGRADE_TX_ID, phase2CallData);
        }
    }

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal {
        preCheck();
        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        console.log("  host logic before upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(frameworkUpdateTxId);
        }
        console.log("  host logic after upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
        _test();
        postCheck();
    }

    function _phase2(uint tokenUpgradeTxId, bytes memory govCallData) internal {
        console.log("executing token upgrade tx id %s", tokenUpgradeTxId);

        printUUPSCodeAddress("--- native token wrapper logic address before update", NATIVE_TOKEN_WRAPPER);
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(tokenUpgradeTxId);
        }
        printUUPSCodeAddress("+++ native token wrapper logic address after update", NATIVE_TOKEN_WRAPPER);
        assertEq(UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress(), address(factory.getSuperTokenLogic()));

        _test();
    }

    function testWithoutUpgrade() public {
        _test();
    }

    function _test() internal {
        console.log("+++ deploying new ERC20 wrapper SuperToken...");
        _testDeployNewERC20Wrapper();
        console.log("--- passed new ERC20 wrapper SuperToken deployment");

        console.log("+++ smoke testing GDA...");
        smokeTestGDA();
        console.log("--- passed GDA smoke test");

        console.log("+++ smoke testing native token wrapper...");
        smokeTestNativeTokenWrapper();
        console.log("--- passed native token wrapper smoke test");

        console.log("+++ testing regression GDA fake pool...");
        _testRegressionGDAFakePool();
        console.log("--- passed regression GDA fake pool test");
    }
}