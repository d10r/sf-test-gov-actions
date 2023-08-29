// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";
import "forge-std/StdJson.sol";

contract Upgrade_1_8 is UpgradeBase {

    function testUpgrade() public {
        uint txId = getLastMultisigTxId();
        console.log("gov logic before: %s", UUPSProxiable(address(gov)).getCodeAddress());
        console.log("execute first gov action");
        execMultisigGovAction(txId);
        console.log("execute second gov action");
        execMultisigGovAction(txId-1);
        console.log("gov logic after : %s", UUPSProxiable(address(gov)).getCodeAddress());
        updateSuperToken(NATIVE_TOKEN_WRAPPER);
        console.log("smoke testing native token wrapper %s after framework upgrade", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }
}