// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "./lib/UpgradeBase.sol";
import "forge-std/StdJson.sol";

using stdJson for string;

// smoke tests a provided list (json file) of SuperTokens before and after an upgrade via Multisig gov action
contract UpgradeTokens is UpgradeBase {

    address[] tokenList;

    constructor() {
        string memory TOKEN_LIST_FILE = vm.envString("TOKEN_LIST_FILE");
        console.log("file: %s", TOKEN_LIST_FILE);

        string memory json = vm.readFile(TOKEN_LIST_FILE);
        console.log("file string size: %s", bytes(json).length);

        address addr1 = vm.parseJsonAddress(json, ".[0]");
        console.log("addr1: %s", addr1);

        tokenList = vm.parseJsonAddressArray(json, "");
        console.log("parsed %s addresses", tokenList.length);
        
    }

    function testBeforeUpgrade() public {
        for(uint256 i; i<tokenList.length; i++) {
            smokeTestSuperToken(tokenList[i]);
            printCodeAddress(tokenList[i]);
        }
    }

    function testAfterUpgrade() public {
        execMultisigGovAction();
        //smokeTestNativeTokenWrapper();
        for(uint256 i; i<tokenList.length; i++) {
            smokeTestSuperToken(tokenList[i]);
            printCodeAddress(tokenList[i]);
        }
    }
}
