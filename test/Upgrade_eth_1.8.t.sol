// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";
import "forge-std/StdJson.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

contract Upgrade_eth_1_8 is UpgradeBase {

    function testToken() public {
        smokeTestNativeTokenWrapper();
    }

    /*
    * eth-mainnet special treatment:
    * - deploy SuperToken with COF and CIF set to zero address (CFA NFTs disabled)
    * - deploy SuperTokenFactory logic with COF and CIF logics set to zero address
    * - exexute the upgrade (Superfluid logic, CFA and IDA were already deployed and are hardcoded here)
    * - deploy new SuperfluidGovernanceII logic which is part of 1.8 upgrade
    * - update native SuperToken and smoke test
    */
    function testDeploy() public {
        SuperToken stNewLogic = new SuperToken(ISuperfluid(HOST_ADDR), IConstantOutflowNFT(address(0)), IConstantInflowNFT(address(0)));
        console.log("SuperToken deployed to %s", address(stNewLogic));

        SuperTokenFactory factoryNewLogic = new SuperTokenFactory(
            ISuperfluid(HOST_ADDR),
            ISuperToken(stNewLogic),
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0))
        );
        console.log("SuperTokenFactory deployed to %s", address(factoryNewLogic));

        vm.startPrank(Ownable(address(gov)).owner());

        address hostNewLogic = 0x0FB7694c990CF19001127391Dbe53924dd7a61c7;
        address[] memory agreementNewLogics = new address[](2);
        agreementNewLogics[0] = 0xd0DE1486F69495D49c02D8f541B7dADf9Cf5CD91; // CFA
        agreementNewLogics[1] = 0xA794C9ee519FD31BbCE643e8D8138f735E97D1DB; // IDA

        gov.updateContracts(
            ISuperfluid(HOST_ADDR),
            hostNewLogic,
            agreementNewLogics,
            address(factoryNewLogic)
        );
        vm.stopPrank();

        // upgrade gov
        SuperfluidGovernanceII govNewLogic = new SuperfluidGovernanceII();
        govNewLogic.castrate();
        vm.startPrank(Ownable(address(gov)).owner());
        (UUPSProxiable(address(gov))).updateCode(address(govNewLogic));
        vm.stopPrank();

        updateSuperToken(NATIVE_TOKEN_WRAPPER);
        console.log("smoke testing native token wrapper %s after framework upgrade", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }
}