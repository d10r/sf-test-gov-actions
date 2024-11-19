// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

/*
* Upgrade to 1.11.0
* - removes FlowNFTs
*/

import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import "./lib/UpgradeBase.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

using SuperTokenV1Library for ISuperToken;

contract Upgrade_1_11_0 is UpgradeBase {
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
        if (phases & 2 != 0) {
            console.log("testing phase 2 - upgrade super tokens");
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase2(TOKEN_UPGRADE_TX_ID, phase2CallData);
        }
    }

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal {
        preCheck();
        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        if (govCallData.length > 0) {
            execGovAction(govCallData);
        } else {
            execMultisigGovAction(frameworkUpdateTxId);
        }
        postCheck();



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

// for eth-mainnet which transitions to 1.8.1 to 1.11.0
contract Upgrade_1_11_0_Mainnet is UpgradeBase {
    function testUpgrade() public {
        int phase = vm.envInt("PHASE");

        uint lastTxId = getLastMultisigTxId();
        console.log("last multisig tx id: %s", lastTxId);

        if (phase == 1) {
            console.log("testing phase 1");
            uint GOV_UPDATE_TX_ID = vm.envOr("GOV_UPDATE_TX_ID", lastTxId - 1);
            uint REGISTER_GDA_TX_ID = vm.envOr("REGISTER_GDA_TX_ID", lastTxId);
            _phase1(GOV_UPDATE_TX_ID, REGISTER_GDA_TX_ID);
        } else if (phase == 2) {
            console.log("testing phase 2");
            uint FRAMEWORK_UPDATE_TX_ID = vm.envOr("FRAMEWORK_UPDATE_TX_ID", lastTxId-1);
            uint TOKEN_UPGRADE_TX_ID = vm.envOr("TOKEN_UPGRADE_TX_ID", lastTxId);
            _phase2(FRAMEWORK_UPDATE_TX_ID, TOKEN_UPGRADE_TX_ID);
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

    function _phase2(uint frameworkUpdateTxId, uint tokenUgradeTxId) internal {
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(
            ISuperfluid(host).getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));

        console.log("executing framework update tx id %s", frameworkUpdateTxId);
        printUUPSCodeAddress("--- gda address before update", address(gda));
        printBeaconCodeAddress("--- pool master address before update", address(gda.superfluidPoolBeacon()));
        execMultisigGovAction(frameworkUpdateTxId);
        printUUPSCodeAddress("+++ gda address after update", address(gda));
        printBeaconCodeAddress("+++ pool master address after update", address(gda.superfluidPoolBeacon()));

        smokeTestNativeTokenWrapper();

        console.log("executing token upgrade tx id %s", tokenUgradeTxId);

        printUUPSCodeAddress("--- native token wrapper logic address before update", NATIVE_TOKEN_WRAPPER);
        execMultisigGovAction(tokenUgradeTxId);
        printUUPSCodeAddress("+++ native token wrapper logic address after update", NATIVE_TOKEN_WRAPPER);

        smokeTestNativeTokenWrapper();

        _smokeTestGDA();

        //_smokeTestGDA();
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