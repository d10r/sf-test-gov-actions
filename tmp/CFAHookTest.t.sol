// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { ConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";
import { Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import "cfanft/contracts/FlowNFT.sol";

contract CFAHookTest is Test {

    address constant CFA_PROXY = 0x6EeE6060f715257b970700bc2656De21dEdF074C;

    FlowNFT internal flowNFT;

    constructor() {
        vm.createSelectFork("https://polygon-rpc.com");

        flowNFT = new FlowNFT(CFA_PROXY, "TestFlowNFT", "TFN");
    }

    function testUpgradeWithHookSet() public {
        address CFA_PROXY = 0x6EeE6060f715257b970700bc2656De21dEdF074C;
        address HOST = 0x3E14dC1b13c488a8d5D310918780c983bD5982E7;
        address GOV = 0x3AD3f7A0965Ce6f9358AD5CCE86Bc2b05F1EE087;

        vm.startPrank(GOV);

        Superfluid host = Superfluid(HOST);

        // deploy new CFA logic
        ConstantFlowAgreementV1 cfaV1Logic = new ConstantFlowAgreementV1(host, IConstantFlowAgreementHook(flowNFT));

        host.updateAgreementClass(cfaV1Logic);

        UUPSProxiable cfaProxiable = UUPSProxiable(CFA_PROXY);
        address cfaLogic = cfaProxiable.getCodeAddress();
        assertEq(cfaProxiable.getCodeAddress(), address(cfaV1Logic));

        vm.stopPrank();
    }
}