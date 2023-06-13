// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { 
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultiSigWallet } from "./helpers/IMultiSigWallet.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { ConstantOutflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantOutflowNFT.sol";
import { ConstantInflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantInflowNFT.sol";
import { SuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

contract Upgrade_1_7 is Test {
    
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    SuperTokenFactory factory;
    IMultiSigWallet multisig;
    address NATIVE_TOKEN_WRAPPER;
    address SUPERTOKEN;
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    address constant alice = address(0x420);

    constructor() {
        string memory rpc = vm.envString("RPC");
        vm.createSelectFork(rpc);
        HOST_ADDR = vm.envAddress("HOST_ADDR");
        NATIVE_TOKEN_WRAPPER = vm.envAddress("NATIVE_TOKEN_WRAPPER");
        SUPERTOKEN = vm.envOr("SUPERTOKEN", address(0));
        host = ISuperfluid(HOST_ADDR);
        gov = ISuperfluidGovernance(host.getGovernance());
        factory = SuperTokenFactory(address(host.getSuperTokenFactory()));
        address govOwner = Ownable(address(gov)).owner();
        multisig = IMultiSigWallet(govOwner);
    }

    // TESTS ======================================================

    function testConfirmAndExecuteUpgrade() public {
        execGovAction();
        console.log("smoke testing native token wrapper %s after framework upgrade", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

    function testUpdateNativeSuperTokenLogic() public {
        execGovAction();

        updateSuperToken(NATIVE_TOKEN_WRAPPER);

        console.log("smoke testing native token wrapper after token logic update %s", NATIVE_TOKEN_WRAPPER);
        smokeTestNativeTokenWrapper();
    }

    function testUpdateOtherSuperTokenLogic() public {
        if (SUPERTOKEN != address(0)) {
            execGovAction();

            updateSuperToken(SUPERTOKEN);

            console.log("smoke testing token wrapper after token logic update %s", SUPERTOKEN);
            smokeTestSuperToken(SUPERTOKEN);
        } else {
            console.log("skipping (zero address set)");
        }
    }

    function testSuperTokenHasNFTWithCorrectBaseUri() public {
        execGovAction();
        updateSuperToken(NATIVE_TOKEN_WRAPPER);

        ISuperToken superToken = ISuperToken(NATIVE_TOKEN_WRAPPER);

        ConstantOutflowNFT cof = ConstantOutflowNFT(address(superToken.CONSTANT_OUTFLOW_NFT()));
        assertEq(cof.baseURI(), "https://nft.superfluid.finance/cfa/v2/getmeta", "wrong base uri");
        assertEq(address(factory.CONSTANT_OUTFLOW_NFT_LOGIC()), address(UUPSProxiable(cof.getCodeAddress())), "cof logic mismatch");

        ConstantInflowNFT cif = ConstantInflowNFT(address(superToken.CONSTANT_INFLOW_NFT()));
        assertEq(cif.baseURI(), "https://nft.superfluid.finance/cfa/v2/getmeta", "wrong base uri");
        assertEq(address(factory.CONSTANT_INFLOW_NFT_LOGIC()), address(UUPSProxiable(cif.getCodeAddress())), "cif logic mismatch");

        assertTrue(address(cif) != address(cof), "cif and cof should not have same address");
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
        uint256 TXID = vm.envOr("TXID", type(uint256).max); // unset means autodetect

        if (TXID == type(uint256).max) {
            TXID = multisig.transactionCount()-1;
            console.log("TXID not provided, assuming it's the latest tx: %s", TXID);
        }

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

    function updateSuperToken(address superTokenAddr) public {
        console.log("SuperToken %s logic before upgrade: %s", superTokenAddr, UUPSProxiable(superTokenAddr).getCodeAddress());
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(superTokenAddr);
        vm.startPrank(address(multisig));
        gov.batchUpdateSuperTokenLogic(host, tokens);
        console.log("SuperToken logic after upgrade: %s", UUPSProxiable(superTokenAddr).getCodeAddress());
        vm.stopPrank();
        assertEq(UUPSProxiable(superTokenAddr).getCodeAddress(), address(factory.getSuperTokenLogic()));
    }

    function smokeTestNativeTokenWrapper() public {
        ISETH ethx = ISETH(NATIVE_TOKEN_WRAPPER);
        // give alice plenty of native tokens
        deal(alice, uint256(100e18));

        vm.startPrank(alice);

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

    function smokeTestSuperToken(address superTokenAddr) public {
        ISuperToken superToken = ISuperToken(superTokenAddr);
        IERC20 underlying = IERC20(superToken.getUnderlyingToken());
        deal(address(underlying), alice, uint256(100e18));

        vm.startPrank(alice);

        underlying.approve(superTokenAddr, 100e18);
        superToken.upgrade(1e18);

        // start a stream using the forwarder
        cfaFwd.setFlowrate(superToken, address(this), 1e9);
        skip(1000);
        assertEq(superToken.balanceOf(address(this)), 1e9 * 1000);

        // stop the stream
        cfaFwd.setFlowrate(superToken, address(this), 0);
        skip(1000);
        assertEq(superToken.balanceOf(address(this)), 1e9 * 1000); // no change

        vm.stopPrank();
    }
}