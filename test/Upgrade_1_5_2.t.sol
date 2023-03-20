// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { 
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IMultiSigWallet } from "./helpers/IMultiSigWallet.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";

contract Upgrade_1_5_2 is Test {
    
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    IMultiSigWallet multisig;
    address NATIVE_TOKEN_WRAPPER = 0x3aD736904E9e65189c3000c7DD2c8AC8bB7cD4e3; // MATICx
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    constructor() {
        string memory rpc = vm.envString("RPC");
        vm.createSelectFork(rpc);
        HOST_ADDR = vm.envAddress("HOST_ADDR");
        host = ISuperfluid(HOST_ADDR);
        gov = ISuperfluidGovernance(host.getGovernance());
        address govOwner = Ownable(address(gov)).owner();
        multisig = IMultiSigWallet(govOwner);
    }

    // =========================================================

    function testConfirmAndExecuteUpgrade() public {
        uint256 TXID = vm.envUint("TXID");
        address signer1 = multisig.owners(0);
        vm.startPrank(signer1);
        // already executes because last required signer
        multisig.confirmTransaction(TXID);
        vm.stopPrank();
    // }
    //
    //function testUpdateSuperTokenLogic() public {
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(NATIVE_TOKEN_WRAPPER);
        vm.startPrank(address(multisig));
        gov.batchUpdateSuperTokenLogic(host, tokens);
        vm.stopPrank();
    //}
    //
    //function testCreateFlow() public {
        ISETH ethx = ISETH(NATIVE_TOKEN_WRAPPER);

        // the GH agent account has native tokens everywhere
        vm.startPrank(0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015);
        ethx.upgradeByETH{value: 1e16}();
        cfaFwd.setFlowrate(ethx, address(this), 1e9);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e12);
        cfaFwd.setFlowrate(ethx, address(this), 0);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e12); // no change
        vm.stopPrank();
    }
}