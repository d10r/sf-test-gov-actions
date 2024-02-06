// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";

import { SuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/agreements/gdav1/SuperfluidPool.sol";
import { GeneralDistributionAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

import { PureSuperToken } from "@superfluid-finance/ethereum-contracts/contracts/tokens/PureSuperToken.sol";

using SuperTokenV1Library for ISuperToken;

/*
* Upgrade to 1.9 which includes GDA rollout.
*
* The upgrade is done in 3 phases:
* 1. Update gov logic and register GDA.
* 2. Update framework logic.
* 3. Update token logic.
*/
contract Upgrade_1_9 is UpgradeBase {

    // single entry-point, phase is chosen by env var
    // depending on the phase, additional env vars can be required
    function testUpgrade() public {
        int phase = vm.envInt("PHASE");

        uint lastTxId = getLastMultisigTxId();
        console.log("last multisig tx id: %s", lastTxId);

        if (phase == 1) {
            console.log("testing phase 1");
            uint GOV_UPDATE_TX_ID = vm.envUint("GOV_UPDATE_TX_ID");
            uint REGISTER_GDA_TX_ID = vm.envUint("REGISTER_GDA_TX_ID");
            _phase1(GOV_UPDATE_TX_ID, REGISTER_GDA_TX_ID);
        } else if (phase == 2) {
            console.log("testing phase 2");
            uint FRAMEWORK_UPDATE_TX_ID = vm.envUint("FRAMEWORK_UPDATE_TX_ID");
            _phase2(FRAMEWORK_UPDATE_TX_ID);
        } else if (phase == 3) {
            console.log("testing phase 3");
            // here we can default to the last tx id since only one is needed
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase3(TOKEN_UPGRADE_TX_ID);
        } else {
            console.log("testing nothing, needs to specify an env var PHSAE");
        }
    }

    // ============================================================
    // internal functions
    // ============================================================

    // update gov & deploy gda phase 1
    function _phase1(uint govUpdateTxId, uint registerGdaTxId) internal {
        smokeTestNativeTokenWrapper();

        console.log("executing gov update tx id %s", govUpdateTxId);
        printUUPSCodeAddress("--- gov address before update", address(gov));
        execMultisigGovAction(govUpdateTxId);
        printUUPSCodeAddress("+++ gov address after update", address(gov));

        _smokeTestGov();

        console.log("executing gda register tx id %s", registerGdaTxId);
        execMultisigGovAction(registerGdaTxId);

        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(
            ISuperfluid(host).getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));

        console.log("GDA address: %s", address(gda));

        smokeTestNativeTokenWrapper();
    }

    function _phase2(uint frameworkUpdateTxId) internal {
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(
            ISuperfluid(host).getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));

        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        printUUPSCodeAddress("--- gda address before update", address(gda));
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        execMultisigGovAction(frameworkUpdateTxId);
        printUUPSCodeAddress("+++ gda address after update", address(gda));
        printBeaconCodeAddress("+++ pool master address after update", address(gda.superfluidPoolBeacon()));

        smokeTestNativeTokenWrapper();

        _smokeTestGDA();
    }

    function _phase3(uint tokenUgradeTxId) internal {
        console.log("executing token upgrade tx id %s", tokenUgradeTxId);

        printUUPSCodeAddress("--- native token wrapper logic address before update", NATIVE_TOKEN_WRAPPER);
        execMultisigGovAction(tokenUgradeTxId);
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

        gdaPool.updateMemberUnits(bob, 1);

        assertEq(gdaPool.getTotalUnits(), 1);

        vm.startPrank(alice);
        ISETH(address(ethx)).upgradeByETH{value: 1e18}();
        ethx.distributeToPool(alice, gdaPool, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        ethx.connectPool(gdaPool);
        vm.stopPrank();

        assertEq(ethx.balanceOf(bob), 1 ether, "bob balance wrong after gda distribution");
    }
}