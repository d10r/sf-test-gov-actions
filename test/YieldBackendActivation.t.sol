// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {
    ISuperToken,
    IERC20
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IYieldBackend} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/IYieldBackend.sol";
import {ISETH} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import {IERC20Metadata} from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// Admin-only yield functions (on SuperToken impl, not in ISuperToken)
interface ISuperTokenYieldAdmin {
    function enableYieldBackend(IYieldBackend newYieldBackend) external;
    function disableYieldBackend() external;
    function withdrawSurplusFromYieldBackend() external;
}

import "./lib/UpgradeBase.sol";

/**
 * Fork test for yield backend activation: two Safe actions on the forked chain.
 * 1. Gov Safe: changeSuperTokenAdmin(host, token, newAdmin)
 * 2. SuperToken Admin Safe: superToken.enableYieldBackend(yieldBackend)
 *
 * Requires env: RPC, HOST_ADDR, NATIVE_TOKEN_WRAPPER (from run_yield_backend_test.sh),
 *   SUPER_TOKEN, YIELD_BACKEND, SUPER_TOKEN_ADMIN, GOV_CALLDATA, SUPER_TOKEN_ADMIN_CALLDATA.
 *
 * Native-asset SuperTokens (e.g. ETHx): `getUnderlyingToken()` is address(0). Uses ETH balances and
 * ISETH upgradeByETH / downgradeToETH. AaveETHYieldBackend still has A_TOKEN() (detected as Aave).
 */
contract YieldBackendActivation is UpgradeBase {

    uint256 constant ROUNDING_TOLERANCE = 1000;

    function _isNativeAssetSuperToken(address superTokenAddr) internal view returns (bool) {
        return ISuperToken(superTokenAddr).getUnderlyingToken() == address(0);
    }

    /// @dev Underlying liquidity held passively on the SuperToken (ERC20 balance or native ETH)
    function _superTokenPassiveUnderlyingBalance(address superTokenAddr) internal view returns (uint256) {
        if (_isNativeAssetSuperToken(superTokenAddr)) {
            return superTokenAddr.balance;
        }
        return IERC20(ISuperToken(superTokenAddr).getUnderlyingToken()).balanceOf(superTokenAddr);
    }

    /// @dev Decimals for `toUnderlyingAmount` / yield dust when SuperToken underlying is unset (native).
    function _underlyingDecimalsForYieldAccounting(address superTokenAddr, address yieldBackendAddr)
        internal
        view
        returns (uint256)
    {
        address u = ISuperToken(superTokenAddr).getUnderlyingToken();
        if (u != address(0)) {
            return IERC20Metadata(u).decimals();
        }
        string memory t = _detectBackendType(yieldBackendAddr);
        if (keccak256(bytes(t)) == keccak256(bytes("Aave"))) {
            (, bytes memory data) = yieldBackendAddr.staticcall(abi.encodeWithSignature("ASSET_TOKEN()"));
            address asset = abi.decode(data, (address));
            return IERC20Metadata(asset).decimals();
        }
        if (keccak256(bytes(t)) == keccak256(bytes("ERC4626"))) {
            (, bytes memory vd) = yieldBackendAddr.staticcall(abi.encodeWithSignature("VAULT()"));
            address vault = abi.decode(vd, (address));
            (, bytes memory ad) = vault.staticcall(abi.encodeWithSignature("asset()"));
            address vaultAsset = abi.decode(ad, (address));
            return IERC20Metadata(vaultAsset).decimals();
        }
        revert("Unsupported yield backend for native SuperToken");
    }

    function _runActivationPhases() internal returns (address superTokenAddr, address yieldBackendAddr, address superTokenAdminAddr) {
        bytes memory govCalldata = vm.envOr("GOV_CALLDATA", new bytes(0));
        bytes memory superTokenAdminCalldata = vm.envOr("SUPER_TOKEN_ADMIN_CALLDATA", new bytes(0));
        require(govCalldata.length > 0, "GOV_CALLDATA must be set");
        require(superTokenAdminCalldata.length > 0, "SUPER_TOKEN_ADMIN_CALLDATA must be set");

        superTokenAddr = vm.envAddress("SUPER_TOKEN");
        yieldBackendAddr = vm.envAddress("YIELD_BACKEND");
        superTokenAdminAddr = vm.envAddress("SUPER_TOKEN_ADMIN");

        execGovAction(govCalldata);
        assertEq(ISuperToken(superTokenAddr).getAdmin(), superTokenAdminAddr, "admin after phase 1");

        execSuperTokenAdminAction(superTokenAddr, superTokenAdminAddr, superTokenAdminCalldata);
        assertEq(ISuperToken(superTokenAddr).getYieldBackend(), yieldBackendAddr, "yield backend after phase 2");
    }

    /// @return "Aave" or "ERC4626" (Spark uses ERC4626)
    function _detectBackendType(address yieldBackendAddr) internal view returns (string memory) {
        // AaveYieldBackend has A_TOKEN() immutable
        (bool aaveOk,) = yieldBackendAddr.staticcall(abi.encodeWithSignature("A_TOKEN()"));
        if (aaveOk) return "Aave";
        // ERC4626YieldBackend / SparkYieldBackend has VAULT() immutable
        (bool vaultOk,) = yieldBackendAddr.staticcall(abi.encodeWithSignature("VAULT()"));
        if (vaultOk) return "ERC4626";
        return "Unknown";
    }

    /// @return yield position in underlying terms (for assertion)
    function _getYieldAssetBalanceInUnderlying(address superTokenAddr, address yieldBackendAddr)
        internal
        view
        returns (uint256)
    {
        string memory backendType = _detectBackendType(yieldBackendAddr);
        if (keccak256(bytes(backendType)) == keccak256(bytes("Aave"))) {
            (, bytes memory aTokenData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("A_TOKEN()"));
            address aToken = abi.decode(aTokenData, (address));
            return IERC20(aToken).balanceOf(superTokenAddr);
        }
        if (keccak256(bytes(backendType)) == keccak256(bytes("ERC4626"))) {
            (, bytes memory vaultData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("VAULT()"));
            address vault = abi.decode(vaultData, (address));
            uint256 shares = IERC20(vault).balanceOf(superTokenAddr);
            (, bytes memory assetsData) = vault.staticcall(abi.encodeWithSignature("convertToAssets(uint256)", shares));
            return abi.decode(assetsData, (uint256));
        }
        revert("Unsupported yield backend type");
    }

    /// @return yield position in shares (aToken balance or vault shares) for zero/dust assertion after disable
    function _getYieldPositionShares(address superTokenAddr, address yieldBackendAddr)
        internal
        view
        returns (uint256)
    {
        string memory backendType = _detectBackendType(yieldBackendAddr);
        if (keccak256(bytes(backendType)) == keccak256(bytes("Aave"))) {
            (, bytes memory aTokenData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("A_TOKEN()"));
            address aToken = abi.decode(aTokenData, (address));
            return IERC20(aToken).balanceOf(superTokenAddr);
        }
        if (keccak256(bytes(backendType)) == keccak256(bytes("ERC4626"))) {
            (, bytes memory vaultData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("VAULT()"));
            address vault = abi.decode(vaultData, (address));
            return IERC20(vault).balanceOf(superTokenAddr);
        }
        revert("Unsupported yield backend type");
    }

    /// @return Max allowed yield position (shares) after disable: 10 ** decimalsGap (protocol-style dust)
    function _getYieldPositionDustTolerance(address superTokenAddr, address yieldBackendAddr)
        internal
        view
        returns (uint256)
    {
        string memory backendType = _detectBackendType(yieldBackendAddr);
        uint256 shareDecimals;
        uint256 underlyingDecimals = _underlyingDecimalsForYieldAccounting(superTokenAddr, yieldBackendAddr);
        if (keccak256(bytes(backendType)) == keccak256(bytes("Aave"))) {
            (, bytes memory aTokenData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("A_TOKEN()"));
            address aToken = abi.decode(aTokenData, (address));
            shareDecimals = uint256(IERC20Metadata(aToken).decimals());
        } else if (keccak256(bytes(backendType)) == keccak256(bytes("ERC4626"))) {
            (, bytes memory vaultData) = yieldBackendAddr.staticcall(abi.encodeWithSignature("VAULT()"));
            address vault = abi.decode(vaultData, (address));
            (, bytes memory decimalsData) = vault.staticcall(abi.encodeWithSignature("decimals()"));
            shareDecimals = uint256(abi.decode(decimalsData, (uint8)));
        } else {
            revert("Unsupported yield backend type");
        }
        uint256 decimalsGap = shareDecimals >= underlyingDecimals
            ? shareDecimals - underlyingDecimals
            : underlyingDecimals - shareDecimals;
        return 10 ** decimalsGap;
    }

    function testYieldBackendActivation() public {
        console.log("Phase 1: exec gov action (changeSuperTokenAdmin)");
        console.log("Phase 2: exec SuperToken admin action (enableYieldBackend)");
        (address superTokenAddr, address yieldBackendAddr,) = _runActivationPhases();

        string memory backendType = _detectBackendType(yieldBackendAddr);
        console.log("Detected yield backend type: %s", backendType);

        (uint256 normalizedTotalSupply,) = ISuperToken(superTokenAddr).toUnderlyingAmount(ISuperToken(superTokenAddr).totalSupply());

        assertEq(_superTokenPassiveUnderlyingBalance(superTokenAddr), 0, "SuperToken underlying balance should be 0 after enable");

        uint256 yieldBalanceInUnderlying = _getYieldAssetBalanceInUnderlying(superTokenAddr, yieldBackendAddr);
        assertGe(
            yieldBalanceInUnderlying,
            normalizedTotalSupply - ROUNDING_TOLERANCE,
            "SuperToken should hold expected aTokens/vault assets >= supply in underlying"
        );

        console.log("YieldBackendActivation: both phases passed, yield position verified");
    }

    function testUpgradeDowngradeRandomHolders(
        uint256 gap,
        uint256 delayBeforeDowngrade,
        uint256 upgradeAmountRaw
    ) public {
        gap = bound(gap, uint256(30 minutes), uint256(3 days));
        delayBeforeDowngrade = bound(delayBeforeDowngrade, uint256(1 hours), uint256(14 days));
        uint256 maxUpgradeSuper = 50_000 * 1e18;
        uint256 upgradeAmount = bound(upgradeAmountRaw, 1e18, maxUpgradeSuper);

        (address superTokenAddr, address yieldBackendAddr,) = _runActivationPhases();
        string memory backendType = _detectBackendType(yieldBackendAddr);
        console.log("Detected yield backend type: %s", backendType);

        ISuperToken superToken = ISuperToken(superTokenAddr);
        bool native = _isNativeAssetSuperToken(superTokenAddr);
        uint256 underlyingPerHolder = native ? 50_000 ether : 50_000 * 1e6;

        // Avoid low vm.addr seeds: on a fork they can collide with contracts; downgradeToETH uses
        // `.transfer()`, which fails (or runs out of gas) for non-trivial receive/fallback.
        address[3] memory holders =
            [makeAddr("yba_holder_0"), makeAddr("yba_holder_1"), makeAddr("yba_holder_2")];

        for (uint256 i = 0; i < holders.length; i++) {
            if (i > 0) skip(gap);
            if (native) {
                vm.deal(holders[i], underlyingPerHolder);
                vm.startPrank(holders[i]);
                ISETH(superTokenAddr).upgradeByETH{value: upgradeAmount}();
            } else {
                address underlyingAddr = superToken.getUnderlyingToken();
                IERC20 underlying = IERC20(underlyingAddr);
                deal(underlyingAddr, holders[i], underlyingPerHolder);
                vm.startPrank(holders[i]);
                underlying.approve(superTokenAddr, type(uint256).max);
                superToken.upgrade(upgradeAmount);
            }
            skip(delayBeforeDowngrade);
            if (native) {
                ISETH(superTokenAddr).downgradeToETH(superToken.balanceOf(holders[i]));
            } else {
                superToken.downgrade(superToken.balanceOf(holders[i]));
            }
            vm.stopPrank();
            assertEq(superToken.balanceOf(holders[i]), 0, "holder balance should be 0 after downgrade");
        }
    }

    function testDisableYieldBackendAndVerifyUnderlying(uint256 delayBeforeDisable) public {
        delayBeforeDisable = bound(delayBeforeDisable, uint256(1 hours), uint256(30 days));

        (address superTokenAddr, address yieldBackendAddr, address superTokenAdminAddr) = _runActivationPhases();
        console.log("Detected yield backend type: %s", _detectBackendType(yieldBackendAddr));

        ISuperToken superToken = ISuperToken(superTokenAddr);
        (uint256 normalizedTotalSupplyBefore,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        skip(delayBeforeDisable);

        bytes memory disableCalldata = abi.encodeWithSignature("disableYieldBackend()");
        execSuperTokenAdminAction(superTokenAddr, superTokenAdminAddr, disableCalldata);

        assertEq(superToken.getYieldBackend(), address(0), "yield backend should be cleared");

        uint256 underlyingAfter = _superTokenPassiveUnderlyingBalance(superTokenAddr);
        assertGe(
            underlyingAfter,
            normalizedTotalSupplyBefore - ROUNDING_TOLERANCE,
            "SuperToken underlying after disable should be >= supply in underlying"
        );

        uint256 yieldPositionSharesAfter = _getYieldPositionShares(superTokenAddr, yieldBackendAddr);
        uint256 dustTolerance = _getYieldPositionDustTolerance(superTokenAddr, yieldBackendAddr);
        assertLe(
            yieldPositionSharesAfter,
            dustTolerance,
            "SuperToken should hold no (or dust) yield asset after disable"
        );
    }

    function testNonAdminCannotEnableYieldBackend() public {
        (address superTokenAddr, address yieldBackendAddr,) = _runActivationPhases();
        address attacker = vm.addr(9999);
        vm.prank(attacker);
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        ISuperTokenYieldAdmin(superTokenAddr).enableYieldBackend(IYieldBackend(yieldBackendAddr));
    }

    function testNonAdminCannotDisableYieldBackend() public {
        (address superTokenAddr,,) = _runActivationPhases();
        address attacker = vm.addr(9999);
        vm.prank(attacker);
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        ISuperTokenYieldAdmin(superTokenAddr).disableYieldBackend();
    }

    function testNonAdminCannotWithdrawSurplusFromYieldBackend() public {
        (address superTokenAddr,,) = _runActivationPhases();
        address attacker = vm.addr(9999);
        vm.prank(attacker);
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        ISuperTokenYieldAdmin(superTokenAddr).withdrawSurplusFromYieldBackend();
    }
}
