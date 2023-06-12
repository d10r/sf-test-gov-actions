// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { 
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperTokenFactory,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IMultiSigWallet } from "./helpers/IMultiSigWallet.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";

contract Upgrade_1_7 is Test {
    
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    ISuperTokenFactory factory;
    IMultiSigWallet multisig;
    address NATIVE_TOKEN_WRAPPER;
    address SUPERTOKEN;
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    constructor() {
        string memory rpc = vm.envString("RPC");
        vm.createSelectFork(rpc);
        HOST_ADDR = vm.envAddress("HOST_ADDR");
        NATIVE_TOKEN_WRAPPER = vm.envAddress("NATIVE_TOKEN_WRAPPER");
        SUPERTOKEN = vm.envAddress("SUPERTOKEN");
        host = ISuperfluid(HOST_ADDR);
        gov = ISuperfluidGovernance(host.getGovernance());
        factory = host.getSuperTokenFactory();
        address govOwner = Ownable(address(gov)).owner();
        multisig = IMultiSigWallet(govOwner);
    }

    // TESTS ======================================================

    function testConfirmAndExecuteUpgrade() public {
        execGovAction();
        console.log("smoke testing native token wrapper %s after framework upgrade", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

    function testUpdateSuperTokenLogic() public {
        execGovAction();

        console.log("SuperToken logic before upgrade: %s", UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress());
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(NATIVE_TOKEN_WRAPPER);
        vm.startPrank(address(multisig));
        gov.batchUpdateSuperTokenLogic(host, tokens);
        console.log("SuperToken logic after upgrade: %s", UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress());
        vm.stopPrank();
        assertEq(UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress(), address(factory.getSuperTokenLogic()));

        console.log("smoke testing native token wrapper after token logic update %s", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

     // HELPERS =====================================================

    function isAddressInArray(address[] memory addrArr, address addr) public pure returns (bool) {
        for (uint i = 0; i < addrArr.length; i++) {
            if (addrArr[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function execGovAction() public {
        uint256 TXID = vm.envUint("TXID");

        assertFalse(multisig.isConfirmed(TXID), "gov action already executed");

        // for visual check
        console.log("host logic before upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
        
        uint ownerId = 0;
        while (!multisig.isConfirmed(TXID)) {
            address signer = multisig.owners(ownerId);
            if (!isAddressInArray(multisig.getConfirmations(TXID), signer)) {
                console.log("signer %s confirms", signer);
                vm.startPrank(signer);
                // confirmTransaction already executes if it's the last required confirmation
                multisig.confirmTransaction(TXID);
                vm.stopPrank();
            } else {
                console.log("skipping signer %s (already signed)", signer);
            }
            ownerId++;
        }
        console.log("host logic after upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
    }

    function smokeTestNativeTokenWrapper() public {
        ISETH ethx = ISETH(NATIVE_TOKEN_WRAPPER);

        // the GH agent account has native tokens everywhere
        vm.startPrank(0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015);

        // upgrade some native tokens
        ethx.upgradeByETH{value: 1e16}();

        // start a stream using the forwarder
        cfaFwd.setFlowrate(ethx, address(this), 1e9);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e9 * 1000);

        // stop the stream
        cfaFwd.setFlowrate(ethx, address(this), 0);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e9 * 1000); // no change

        vm.stopPrank();
    }

    function smokeTestSuperToken() public {
        ISuperToken superToken = ISuperToken(SUPERTOKEN);

        // the GH agent account has native tokens everywhere
        vm.startPrank(0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015);

        // upgrade some native tokens
        ethx.upgradeByETH{value: 1e16}();

        // start a stream using the forwarder
        cfaFwd.setFlowrate(ethx, address(this), 1e9);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e9 * 1000);

        // stop the stream
        cfaFwd.setFlowrate(ethx, address(this), 0);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e9 * 1000); // no change

        vm.stopPrank();
    }
}