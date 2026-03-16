// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";

import "./lib/UpgradeBase.sol";

using SuperTokenV1Library for ISuperToken;
using SuperTokenV1Library for ISETH;

/*
v1.15.0:
2 actions: framework upgrade + token upgrade

Added:
- SuperToken.VERSION() returns version string of logic
- SuperToken: admin can enable/disable Yield Backend for yield on underlying

Changed:
- EVM target: shanghai -> cancun

Test that the upgrade works and v1.15.0 features are present.
*/
contract Upgrade_1_15_0 is UpgradeBase {

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
        ISuperToken newERC20Wrapper = _testDeployNewERC20Wrapper();
        console.log("--- passed new ERC20 wrapper SuperToken deployment");

        console.log("+++ testing SuperToken VERSION and getYieldBackend (v1.15.0)...");
        _testVersionAndYieldBackend(ISuperToken(NATIVE_TOKEN_WRAPPER), newERC20Wrapper);
        console.log("--- passed VERSION and getYieldBackend checks");

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

    function _testVersionAndYieldBackend(ISuperToken nativeWrapper, ISuperToken erc20Wrapper) internal view {
        address expectedLogic = address(factory.getSuperTokenLogic());

        // Only run v1.15.0 checks on tokens that have been upgraded (logic matches factory).
        // After phase 1 the native wrapper may still point to old logic; after phase 2 it's upgraded.
        if (UUPSProxiable(address(nativeWrapper)).getCodeAddress() == expectedLogic) {
            assertEq(nativeWrapper.VERSION(), "1.0.0", "native wrapper version mismatch");
            assertEq(nativeWrapper.getYieldBackend(), address(0), "existing tokens should have no yield backend");
        }

        // New ERC20 wrapper always uses factory logic; check it has v1.15.0 features
        assertEq(UUPSProxiable(address(erc20Wrapper)).getCodeAddress(), expectedLogic, "new wrapper logic mismatch");
        assertEq(erc20Wrapper.VERSION(), "1.0.0", "ERC20 wrapper version mismatch");
        assertEq(erc20Wrapper.getYieldBackend(), address(0), "new wrapper should have no yield backend");
    }
}
