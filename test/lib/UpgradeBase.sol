// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperToken,
    IConstantOutflowNFT,
    IConstantInflowNFT,
    ISuperfluidPool,
    PoolConfig,
    IGeneralDistributionAgreementV1
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
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

using SuperTokenV1Library for ISuperToken;

// Base contract with functionality commonly needed for testing framework and token upgrades
contract UpgradeBase is Test {
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    address govOwner;
    SuperTokenFactory factory;
    IMultiSigWallet multisig;
    address NATIVE_TOKEN_WRAPPER;
    address SUPERTOKEN;
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    address constant alice = address(0x420);
    address constant bob = address(0x421);

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
        govOwner = Ownable(address(gov)).owner();
        // optimistically assume the govOwner is of type IMultiSigWallet
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

    // executes the latest pending action of the legacy Gnosis Multisig
    function execMultisigGovAction() public {
        execMultisigGovAction(getLastMultisigTxId());
    }

    // executes the given action of the legacy Gnosis Multisig
    // see https://github.com/gnosis/MultiSigWallet/blob/master/contracts/MultiSigWallet.sol
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    function execMultisigGovAction(uint txId) public {

        assertFalse(multisig.isConfirmed(txId), "gov action already executed");

        uint ownerId = 0;
        while (!multisig.isConfirmed(txId)) {
            address signer = multisig.owners(ownerId);
            if (!isAddressInArray(multisig.getConfirmations(txId), signer)) {
                console.log("  tx %s: signer %s confirms", txId, signer);
                vm.startPrank(signer);

                vm.expectEmit(true, false, false, false);
                emit Execution(txId);
                // confirmTransaction already executes if it's the last required confirmation
                multisig.confirmTransaction(txId);
                vm.stopPrank();
            } else {
                console.log("skipping signer %s (already signed)", signer);
            }
            ownerId++;
        }
    }

    // executes a gov action using the provided calldata
    event ExecutionSuccess(bool success);
    function execGovAction(bytes memory data) public {
        vm.startPrank(govOwner);
        (bool success, bytes memory returnData) = address(gov).call(data);
        vm.stopPrank();
        require(success, "Inner transaction execution failed");
    }


    // precondition: SuperToken is owned by SF gov
    function updateSuperToken(address superTokenAddr) public {
        //console.log("SuperToken %s logic before upgrade: %s", superTokenAddr, UUPSProxiable(superTokenAddr).getCodeAddress());
        ISuperToken[] memory tokens = new ISuperToken[](1);
        tokens[0] = ISuperToken(superTokenAddr);
        vm.startPrank(Ownable(address(gov)).owner());
        gov.batchUpdateSuperTokenLogic(host, tokens);
        //console.log("SuperToken logic after upgrade: %s", UUPSProxiable(superTokenAddr).getCodeAddress());
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

        uint256 balanceBefore = ethx.balanceOf(address(this));

        // start a stream using the forwarder
        cfaFwd.setFlowrate(ethx, address(this), 1e12);
        skip(1000);

        assertEq(ethx.balanceOf(address(this)), balanceBefore + 1e12 * 1000);

        // stop the stream
        cfaFwd.setFlowrate(ethx, address(this), 0);
        skip(1000);
        assertEq(ethx.balanceOf(address(this)), balanceBefore + 1e12 * 1000); // no change

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

    function printUUPSCodeAddress(string memory description, address uupsProxyAddr) public view {
        console.log("%s %s -> %s", description, uupsProxyAddr, UUPSProxiable(uupsProxyAddr).getCodeAddress());
    }
    // backwards compat
    function printCodeAddress(address uupsProxyAddr) public view {
        printUUPSCodeAddress("Code address:", uupsProxyAddr);
    }

    function printBeaconCodeAddress(string memory description, address beaconProxyAddr) public view {
        console.log("%s %s -> %s", description, beaconProxyAddr, IBeacon(beaconProxyAddr).implementation());
    }
}