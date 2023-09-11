// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";
import "forge-std/StdJson.sol";

/*
* Scenario: A SuperToken previously managed by SF gov is upgraded to a non-canonical logic.
* Assumes an unexecuted Multisig action for the operation to be ready.
*/
contract Secede_SuperToken is UpgradeBase {
    function testUpgrade() public {
        uint txId = getLastMultisigTxId();
        console.log("gov logic before: %s", UUPSProxiable(address(gov)).getCodeAddress());
        console.log("supertoken logic before: %s", UUPSProxiable(address(SUPERTOKEN)).getCodeAddress());
        console.log("execute gov action");
        execMultisigGovAction(txId);
        console.log("gov logic after : %s", UUPSProxiable(address(gov)).getCodeAddress());
        console.log("supertoken logic after: %s", UUPSProxiable(address(SUPERTOKEN)).getCodeAddress());
        console.log("smoke testing token %s after framework upgrade", SUPERTOKEN);
        smokeTestSuperToken(SUPERTOKEN);
    }

    function testUpgradeWithNewAdmin() public {
        address UPGRADE_ADMIN = vm.envAddress("UPGRADE_ADMIN");
        address prevLogic = UUPSProxiable(address(SUPERTOKEN)).getCodeAddress();

        uint txId = getLastMultisigTxId();
        execMultisigGovAction(txId);
        console.log("supertoken logic after upgrade: %s", UUPSProxiable(address(SUPERTOKEN)).getCodeAddress());

        // upgrading back to the previous logic
        vm.startPrank(UPGRADE_ADMIN);
        UUPSProxiable(address(SUPERTOKEN)).updateCode(prevLogic);
        console.log("supertoken logic after upgrade again: %s", UUPSProxiable(address(SUPERTOKEN)).getCodeAddress());
    }
}