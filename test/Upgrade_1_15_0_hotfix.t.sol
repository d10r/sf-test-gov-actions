// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {
    ISuperToken,
    ISuperfluidPool,
    IGeneralDistributionAgreementV1,
    PoolConfig
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISETH} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import {IConstantFlowAgreementV1} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {SuperfluidGovernanceII} from
    "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";
import {UUPSProxiable} from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import {SuperTokenV1Library} from
    "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import "./Upgrade_1_15_0.t.sol";

using SuperTokenV1Library for ISuperToken;
using SuperTokenV1Library for ISETH;
using SafeCast for uint256;

/*
v1.15.0 hotfix (2026-06-gdafix):
Single gov action: updateContracts (host + CFA + GDA + pool beacon). No token upgrade.

CFA/GDA liquidation now uses account-level totalDeposit from realtimeBalanceOf
(sum across agreements) instead of CFA-only / GDA-only deposit. Also reverts
GDA_FLOW_DOES_NOT_EXIST when liquidating a critical sender with no GDA flow.

Recommended invocation (gov Safe autodetection):
  scripts/run_test.sh xdai-mainnet Upgrade_1_15_0_hotfix --match-test testWithUpgrade -vvv
*/
contract Upgrade_1_15_0_hotfix is Upgrade_1_15_0 {
    IConstantFlowAgreementV1 internal cfa;
    // ETHx on Base/Mainnet already has a yield backend; the hotfix must not clear it.
    address internal nativeYieldBackendBefore;

    struct LogicSnapshot {
        address host;
        address cfa;
        address gda;
        address factory;
        address superTokenLogic;
        address nativeWrapper;
        address poolBeacon;
    }

    struct CrossAgreementScenario {
        address sender;
        address cfaReceiver;
        address liquidator;
        ISuperfluidPool pool;
        int96 cfaFlowRate;
        uint256 gdaDeposit;
        int256 availableBalance;
        uint256 totalDeposit;
    }

    constructor() {
        cfa = IConstantFlowAgreementV1(
            address(host.getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")))
        );
        nativeYieldBackendBefore = ISuperToken(NATIVE_TOKEN_WRAPPER).getYieldBackend();
    }

    function _testVersionAndYieldBackend(ISuperToken nativeWrapper, ISuperToken erc20Wrapper)
        internal
        view
        override
    {
        address expectedLogic = address(factory.getSuperTokenLogic());

        if (UUPSProxiable(address(nativeWrapper)).getCodeAddress() == expectedLogic) {
            assertEq(nativeWrapper.VERSION(), "1.0.0", "native wrapper version mismatch");
            assertEq(
                nativeWrapper.getYieldBackend(),
                nativeYieldBackendBefore,
                "native wrapper yield backend should be unchanged"
            );
        }

        assertEq(UUPSProxiable(address(erc20Wrapper)).getCodeAddress(), expectedLogic, "new wrapper logic mismatch");
        assertEq(erc20Wrapper.VERSION(), "1.0.0", "ERC20 wrapper version mismatch");
        assertEq(erc20Wrapper.getYieldBackend(), address(0), "new wrapper should have no yield backend");
    }

    function _phase1(uint frameworkUpdateTxId, bytes memory govCallData) internal override {
        LogicSnapshot memory before_ = _snapshotLogics();
        super._phase1(frameworkUpdateTxId, govCallData);
        _assertHotfixLogicsUpdated(before_);
        _testRevertGDALiquidateCriticalSenderWithoutGDAFlow();
        _testGdaLiquidationUsesAccountTotalDeposit();
    }

    function _snapshotLogics() internal view returns (LogicSnapshot memory s) {
        s.host = UUPSProxiable(HOST_ADDR).getCodeAddress();
        s.cfa = UUPSProxiable(address(cfa)).getCodeAddress();
        s.gda = UUPSProxiable(address(gda)).getCodeAddress();
        s.factory = UUPSProxiable(address(factory)).getCodeAddress();
        s.superTokenLogic = address(factory.getSuperTokenLogic());
        s.nativeWrapper = UUPSProxiable(NATIVE_TOKEN_WRAPPER).getCodeAddress();
        s.poolBeacon = IBeacon(address(gda.superfluidPoolBeacon())).implementation();
    }

    function _assertHotfixLogicsUpdated(LogicSnapshot memory before_) internal view {
        LogicSnapshot memory after_ = _snapshotLogics();
        console.log("hotfix logic addresses:");
        console.log("  host %s -> %s", before_.host, after_.host);
        console.log("  cfa  %s -> %s", before_.cfa, after_.cfa);
        console.log("  gda  %s -> %s", before_.gda, after_.gda);
        console.log("  pool beacon %s -> %s", before_.poolBeacon, after_.poolBeacon);

        assertTrue(after_.host != before_.host, "host logic should change");
        assertTrue(after_.cfa != before_.cfa, "CFA logic should change");
        assertTrue(after_.gda != before_.gda, "GDA logic should change");
        assertTrue(after_.poolBeacon != before_.poolBeacon, "pool beacon logic should change");
        assertEq(after_.factory, before_.factory, "factory logic should not change");
        assertEq(after_.superTokenLogic, before_.superTokenLogic, "super token logic should not change");
        assertEq(after_.nativeWrapper, before_.nativeWrapper, "native wrapper logic should not change");
    }

    /// @dev Critical CFA-only sender: distributeFlow(..., 0) must not take the liquidation path.
    function _testRevertGDALiquidateCriticalSenderWithoutGDAFlow() internal {
        console.log("+++ hotfix: GDA_FLOW_DOES_NOT_EXIST on CFA-only critical sender...");

        address sender = makeAddr("hotfixCfaOnlySender");
        address receiver = makeAddr("hotfixCfaOnlyReceiver");
        address liquidator = makeAddr("hotfixCfaOnlyLiquidator");

        ISuperfluidPool pool = ethx.createPool(address(this), PoolConfig(true, true));

        deal(sender, 50 ether);
        vm.startPrank(sender);
        ethx.upgradeByETH{value: 20 ether}();
        ethx.createFlow(receiver, 1e14);
        ethx.transfer(makeAddr("hotfixCfaOnlySink"), ethx.balanceOf(sender));
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        (int256 availableBalance,,,) = ethx.realtimeBalanceOfNow(sender);
        assertLt(availableBalance, 0, "sender should be critical");

        vm.startPrank(liquidator);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_FLOW_DOES_NOT_EXIST.selector);
        ethx.distributeFlow(sender, pool, 0);
        vm.stopPrank();

        console.log("--- passed GDA_FLOW_DOES_NOT_EXIST");
    }

    /// @dev Dominant CFA + minor GDA: after GDA deposit alone is exhausted, account is still
    ///      globally deposit-covered. Liquidating the GDA flow must not bail out from the PIC.
    function _testGdaLiquidationUsesAccountTotalDeposit() internal {
        console.log("+++ hotfix: GDA liquidation uses account-level totalDeposit...");
        CrossAgreementScenario memory s = _setupCfaDominantGdaOutflows();
        _warpPastGdaDepositWhileGloballyCovered(s);
        _assertGdaLiquidationDoesNotBailOut(s);
        console.log("--- passed GDA account-level totalDeposit liquidation");
    }

    function _setupCfaDominantGdaOutflows() internal returns (CrossAgreementScenario memory s) {
        s.sender = makeAddr("hotfixSender");
        s.cfaReceiver = makeAddr("hotfixCfaReceiver");
        s.liquidator = makeAddr("hotfixLiquidator");
        s.cfaFlowRate = 1e15;
        address member = makeAddr("hotfixMember");

        s.pool = ethx.createPool(address(this), PoolConfig(true, true));
        s.pool.updateMemberUnits(member, 1);
        vm.prank(member);
        ethx.connectPool(s.pool);

        deal(s.sender, 100 ether);
        vm.startPrank(s.sender);
        ethx.upgradeByETH{value: 50 ether}();
        ethx.createFlow(s.cfaReceiver, s.cfaFlowRate);
        ethx.distributeFlow(s.sender, s.pool, 1e13);
        ethx.transfer(makeAddr("hotfixSink"), ethx.balanceOf(s.sender));
        vm.stopPrank();

        (,, uint256 cfaDeposit,) = cfa.getAccountFlowInfo(ethx, s.sender);
        (, s.totalDeposit,,) = ethx.realtimeBalanceOfNow(s.sender);
        s.gdaDeposit = s.totalDeposit - cfaDeposit;
        assertGt(cfaDeposit, s.gdaDeposit, "CFA deposit should dominate");
        assertGt(s.gdaDeposit, 0, "GDA deposit should be set");
    }

    function _warpPastGdaDepositWhileGloballyCovered(CrossAgreementScenario memory s) internal {
        int96 netFlow = ethx.getNetFlowRate(s.sender);
        assertLt(netFlow, 0, "expected net outflow");
        uint256 totalOutflowRate = uint256(uint96(-netFlow));
        uint256 warpSeconds = s.gdaDeposit / totalOutflowRate + 1;
        assertLt(warpSeconds, s.totalDeposit / totalOutflowRate, "no globally-covered window past GDA deposit");
        vm.warp(block.timestamp + warpSeconds);

        (s.availableBalance, s.totalDeposit,,) = ethx.realtimeBalanceOfNow(s.sender);
        assertLt(s.availableBalance, 0, "critical");
        assertGe(s.availableBalance + s.totalDeposit.toInt256(), 0, "globally deposit-covered");
        assertLt(s.gdaDeposit.toInt256(), -s.availableBalance, "GDA deposit alone should not cover");
    }

    function _assertGdaLiquidationDoesNotBailOut(CrossAgreementScenario memory s) internal {
        int256 expectedReward = s.gdaDeposit.toInt256() * (s.availableBalance + s.totalDeposit.toInt256())
            / s.totalDeposit.toInt256();
        (bool isPatricianPeriod,) = gda.isPatricianPeriodNow(ethx, s.sender);
        address rewardAccount = SuperfluidGovernanceII(address(gov)).getRewardAddress(host, ethx);
        (int256 rewardBefore,,,) = ethx.realtimeBalanceOfNow(rewardAccount);
        (int256 liquidatorBefore,,,) = ethx.realtimeBalanceOfNow(s.liquidator);

        vm.prank(s.liquidator);
        ethx.distributeFlow(s.sender, s.pool, 0);

        (int256 rewardAfter,,,) = ethx.realtimeBalanceOfNow(rewardAccount);
        (int256 liquidatorAfter,,,) = ethx.realtimeBalanceOfNow(s.liquidator);
        (, int96 remainingCfaRate,,) = ethx.getFlowInfo(s.sender, s.cfaReceiver);
        assertEq(remainingCfaRate, s.cfaFlowRate, "CFA flow should remain open");
        assertEq(gda.getFlowRate(ethx, s.sender, s.pool), 0, "GDA flow should be closed");

        // Pre-fix, GDA used GDA-only deposit as TD and would debit the PIC (bailout).
        assertGe(rewardAfter, rewardBefore, "reward account must not be bailed out");
        if (isPatricianPeriod) {
            assertEq(rewardAfter, rewardBefore + expectedReward, "incorrect GDA patrician reward");
            assertEq(liquidatorAfter, liquidatorBefore, "liquidator should not receive patrician reward");
        } else {
            assertEq(rewardAfter, rewardBefore, "reward account should not receive pleb reward");
            assertEq(liquidatorAfter, liquidatorBefore + expectedReward, "incorrect GDA pleb reward");
        }
        console.log("  patrician: %s", isPatricianPeriod);
    }
}
