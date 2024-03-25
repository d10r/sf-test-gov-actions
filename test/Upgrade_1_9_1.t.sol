// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

import "./lib/UpgradeBase.sol";

import { SuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/agreements/gdav1/SuperfluidPool.sol";
import { GeneralDistributionAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

import { PureSuperToken } from "@superfluid-finance/ethereum-contracts/contracts/tokens/PureSuperToken.sol";

using SuperTokenV1Library for ISuperToken;

/*
* Upgrade to 1.9.1
* Makes NFT hooks non-optional
*
* Required ENV var:
* - PHASES: bitmask of phases to run. E.g. 3 is phase 1 & phase 2
* This allows to run individual phases or a combination.
*
* For networks not using Safe instad of the legacy multisig wallet,
* an env var GOV_CALLDATA with the payload for the gov contract shall be provided.
*
* Phases:
* 1. Update framework
* 2. Upgrade SuperTokens
*/
contract Upgrade_1_9_1 is UpgradeBase {
    // single entry-point, phases are chosen by env var
    // depending on the selected phases, additional env vars can be required
    function testUpgrade() public {
        int phases = vm.envInt("PHASES");
        bytes memory govCallData = vm.envOr("GOV_CALLDATA", new bytes(0));
        uint lastTxId = (govCallData.length > 0) ? 0xffffffff : getLastMultisigTxId();
        console.log("last multisig tx id: %s", lastTxId);

        if (phases & 1 != 0) {
            console.log("testing phase 1 - upgrade framework");
            uint FRAMEWORK_UPDATE_TX_ID = vm.envOr(
                "FRAMEWORK_UPDATE_TX_ID",
                phases & 2 != 0 ? lastTxId - 1 : lastTxId
            );
            _phase1(FRAMEWORK_UPDATE_TX_ID, govCallData);
        }
        if (phases & 2 != 0) {
            console.log("testing phase 2 - upgrade super tokens");
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase2(TOKEN_UPGRADE_TX_ID, govCallData);
        } else {
            console.log("testing nothing, needs to specify an env var PHSAE");
        }
    }

    // ============================================================
    // internal functions
    // ============================================================

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal {
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(
            ISuperfluid(host).getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));

        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        printUUPSCodeAddress("--- gda address before update", address(gda));
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(frameworkUpdateTxId);
        }
        printUUPSCodeAddress("+++ gda address after update", address(gda));
        printBeaconCodeAddress("+++ pool master address after update", address(gda.superfluidPoolBeacon()));

        smokeTestNativeTokenWrapper();

        _smokeTestGDA();
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

        smokeTestNativeTokenWrapper();

        _smokeTestGDA();
    }

    // make sure update still works in the new gov logic
    function _smokeTestGov() internal {
        SuperfluidGovernanceII newGovLogic = new SuperfluidGovernanceII();

        address govOwner = Ownable(address(gov)).owner();
        vm.startPrank(govOwner);

        UUPSProxiable(address(gov)).updateCode(address(newGovLogic));
        vm.stopPrank();

        assertEq(UUPSProxiable(address(gov)).getCodeAddress(), address(newGovLogic), "gov logic update failed");
    }

    function _smokeTestGDA() internal {
        ISuperToken ethx = ISETH(NATIVE_TOKEN_WRAPPER);
        // give alice plenty of native tokens
        deal(alice, uint256(100e18));

        ISuperfluidPool gdaPool = ethx.createPool(address(this), PoolConfig(true, true));
        console.log("pool address", address(gdaPool));
        console.log("pool admin", gdaPool.admin());
        console.log("pool GDA", address(SuperfluidPool(address(gdaPool)).GDA()));

        uint256 balanceBobBefore = ethx.balanceOf(bob);

        gdaPool.updateMemberUnits(bob, 1);

        assertEq(gdaPool.getTotalUnits(), 1);

        vm.startPrank(alice);
        ISETH(address(ethx)).upgradeByETH{value: 1e18}();
        ethx.distributeToPool(alice, gdaPool, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        ethx.connectPool(gdaPool);
        vm.stopPrank();

        assertEq(ethx.balanceOf(bob), balanceBobBefore + 1 ether, "bob balance wrong after gda distribution");
    }
}