// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";
import "forge-std/StdJson.sol";
import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";
import { 
    ISuperfluidToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { IConstantOutflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantOutflowNFT.sol";
import { IConstantInflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantInflowNFT.sol";

using stdJson for string;

/**
 * Test the governance logic update done in https://github.com/superfluid-finance/protocol-monorepo/pull/1565
 * Requires an update of the host contract (signature of updateSuperTokenLogic changed) and of the governance contract.
 */
contract UpgradeGovernance is UpgradeBase {
    SuperfluidGovernanceII govII;
    address govOwner;

    constructor() {
        govII = SuperfluidGovernanceII(address(gov));
        govOwner = Ownable(address(gov)).owner();
        console.log("gov owner: %s", govOwner);
    }

    // HELPERS =====================================================

    // the new gov contract relies on a host method (updateSuperTokenLogic) with changed signature
    function updateHost() public {
        address newHostLogic = address(new Superfluid(false, true));
        vm.startPrank(address(gov));
        UUPSProxiable(HOST_ADDR).updateCode(newHostLogic);
        vm.stopPrank();
    }

    // uses the newly added batchUpdateSuperTokenLogic with user provided logic addresses
    function updateSuperTokenToCustomLogic(address superTokenAddr) public {
        ISuperToken tokenToUpgrade = ISuperToken(superTokenAddr);

        SuperToken dummyTokenLogic = new SuperToken(host, tokenToUpgrade.CONSTANT_OUTFLOW_NFT(), tokenToUpgrade.CONSTANT_INFLOW_NFT());

        console.log("SuperToken %s logic before upgrade: %s", superTokenAddr, UUPSProxiable(superTokenAddr).getCodeAddress());
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(superTokenAddr);

        address[] memory tokenLogics = new address[](1);
        tokenLogics[0] = address(dummyTokenLogic);
        
        vm.startPrank(address(multisig));
        gov.batchUpdateSuperTokenLogic(host, tokens, tokenLogics);
        console.log("SuperToken logic after upgrade: %s", UUPSProxiable(superTokenAddr).getCodeAddress());
        vm.stopPrank();
        assertTrue(UUPSProxiable(superTokenAddr).getCodeAddress() != address(factory.getSuperTokenLogic()));
    }

    // TESTS =======================================================

    function testUpdateToken() public {
        updateSuperToken(NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

    function testUpgradeGovAndUpdateToken() public {
        updateHost();
        console.log("gov logic before upgrade: %s", govII.getCodeAddress());
        execMultisigGovAction();
        console.log("gov logic after upgrade: %s", govII.getCodeAddress());

        updateSuperToken(NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

    function testUpgradeGovAndUpdateTokenToCustomLogic() public {
        // reverse order, because - why not
        execMultisigGovAction();
        updateHost();

        updateSuperTokenToCustomLogic(NATIVE_TOKEN_WRAPPER);
    }

    function testUpgradeGovAndEnableForwarder() public {
        execMultisigGovAction();
        // this doesn't rely on a host upgrade, so we skip it

        vm.startPrank(address(govOwner));
        govII.enableTrustedForwarder(host, ISuperfluidToken(address(0)), address(0x420));
        vm.stopPrank();
    }

    function testUpgradeGovAndUpgradeGovAgain() public {
        console.log("gov logic before upgrade: %s", govII.getCodeAddress());
        execMultisigGovAction();
        console.log("gov logic after first upgrade: %s", govII.getCodeAddress());
        SuperfluidGovernanceII newGovLogic = new SuperfluidGovernanceII();

        vm.expectRevert(SuperfluidGovernanceII.SF_GOV_II_ONLY_OWNER.selector);
        govII.updateCode(address(newGovLogic));
        
        vm.startPrank(address(govOwner));
        govII.updateCode(address(newGovLogic));
        vm.stopPrank();
        console.log("gov logic after second upgrade: %s", govII.getCodeAddress());
    }
}
