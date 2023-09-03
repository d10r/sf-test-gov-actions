// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { 
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperToken,
    IConstantOutflowNFT,
    IConstantInflowNFT
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultiSigWallet } from "../helpers/IMultiSigWallet.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { ConstantOutflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantOutflowNFT.sol";
import { ConstantInflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantInflowNFT.sol";
import { SuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

// Base contract with functionality commonly needed for testing framework and token upgrades
contract UpgradeBase is Test {
    
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    SuperTokenFactory factory;
    IMultiSigWallet multisig;
    address NATIVE_TOKEN_WRAPPER;
    address SUPERTOKEN;
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    address constant alice = address(0x420);

    uint256 constant NOT_SET = type(uint256).max;

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

    // HELPERS =====================================================

    function isAddressInArray(address[] memory addrArr, address addr) public pure returns (bool) {
        for (uint i = 0; i < addrArr.length; i++) {
            if (addrArr[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function getLastMultisigTxId() public view returns(uint) {
        return multisig.transactionCount() - 1;
    }

    // if env TXID is not set, it will use the latest tx
    function execMultisigGovAction() public {
        uint256 TXID = vm.envOr("TXID", NOT_SET);
        if (TXID == NOT_SET) {
            TXID = multisig.transactionCount() - 1;
            console.log("TXID not provided, assuming it's the latest tx: %s", TXID);
        }
        execMultisigGovAction(TXID);
    }

    // executes a gov action with Multisig owner.
    function execMultisigGovAction(uint txId) public {

        assertFalse(multisig.isConfirmed(txId), "gov action already executed");

        // for visual check
        console.log("host logic before upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
        
        uint ownerId = 0;
        while (!multisig.isConfirmed(txId)) {
            address signer = multisig.owners(ownerId);
            if (!isAddressInArray(multisig.getConfirmations(txId), signer)) {
                console.log("signer %s confirms", signer);
                vm.startPrank(signer);
                // confirmTransaction already executes if it's the last required confirmation
                multisig.confirmTransaction(txId);
                vm.stopPrank();
            } else {
                console.log("skipping signer %s (already signed)", signer);
            }
            ownerId++;
        }
        console.log("host logic after upgrade: %s", UUPSProxiable(HOST_ADDR).getCodeAddress());
    }

    // precondition: SuperToken is owned by SF gov
    function updateSuperToken(address superTokenAddr) public {
        console.log("SuperToken %s logic before upgrade: %s", superTokenAddr, UUPSProxiable(superTokenAddr).getCodeAddress());
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(superTokenAddr);
        vm.startPrank(Ownable(address(gov)).owner());
        gov.batchUpdateSuperTokenLogic(host, tokens);
        console.log("SuperToken logic after upgrade: %s", UUPSProxiable(superTokenAddr).getCodeAddress());
        vm.stopPrank();
        assertEq(UUPSProxiable(superTokenAddr).getCodeAddress(), address(factory.getSuperTokenLogic()));
    }

    // smoke tests the native token wrapper provided in env var NATIVE_TOKEN_WRAPPER
    // relied on min deposit for the token not messing with the test
    function smokeTestNativeTokenWrapper() public {
        ISETH ethx = ISETH(NATIVE_TOKEN_WRAPPER);
        // give alice plenty of native tokens
        deal(alice, uint256(100e18));

        vm.startPrank(alice);

        // upgrade some native tokens
        ethx.upgradeByETH{value: 1e18}();

        // start a stream using the forwarder
        cfaFwd.setFlowrate(ethx, address(this), 1e12);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e12 * 1000);

        // stop the stream
        cfaFwd.setFlowrate(ethx, address(this), 0);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), 1e12 * 1000); // no change

        vm.stopPrank();
    }

    function smokeTestSuperToken(address superTokenAddr) public {
        ISuperToken superToken = ISuperToken(superTokenAddr);
        IERC20 underlying = IERC20(superToken.getUnderlyingToken());
        console.log("underlying of %s is %s", superTokenAddr, address(underlying));

        vm.startPrank(alice);

        // deal() seems too unreliable to be used across underlyings. See e.g. https://github.com/foundry-rs/forge-std/issues/140
        /*
        (bool success, bytes memory result) = address(underlying).call(abi.encodeWithSignature("ATOKEN_REVISION()"));
        if (success) {
            console.log("skipping ATOKEN wrapper %s", superTokenAddr);
            return;
        }

        if (address(underlying) != address(0)) {
            deal(address(underlying), alice, uint256(100e18));
            return;
            underlying.approve(superTokenAddr, 100e18);
            superToken.upgrade(1e18);
        } else { */
            deal(address(superTokenAddr), alice, uint256(100e18));
//        }

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

    function printCodeAddress(address superTokenAddr) public view {
        console.log("code address of %s is %s", superTokenAddr, UUPSProxiable(superTokenAddr).getCodeAddress());
    }
}