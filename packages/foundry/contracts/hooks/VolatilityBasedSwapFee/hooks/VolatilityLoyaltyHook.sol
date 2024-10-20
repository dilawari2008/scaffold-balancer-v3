// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";

import {
    LiquidityManagement,
    AfterSwapParams,
    PoolSwapParams,
    SwapKind,
    TokenConfig,
    HookFlags,
    RemoveLiquidityKind,
    AddLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { IVolatilityOracle } from "../volatility-module/IVolatilityOracle.sol";
import { ILoyaltyDiscount } from "../loyalty-module/ILoyaltyDiscount.sol";
import { IVolatilityDiscount } from "../volatility-module/IVolatilityDiscount.sol";

import "forge-std/console.sol";

// only for 2 token pools
contract VolatilityLoyaltyHook is BaseHooks, VaultGuard {
    using FixedPoint for uint256;

    address public _tokenAddress; // making public for debugging purposes only
    address public _oracleAddress; // making public for debugging purposes only
    address public _loyaltyModuleAddress; // making public for debugging purposes only
    address public _volatilityModuleAddress; // making public for debugging purposes only
    address public _factoryAddress; // allow only contant product factory
    bool public _isLoyaltyDiscountEnabled; // making public for debugging purposes only
    bool public _isVolatilityFeeEnabled; // making public for debugging purposes only

    // add checks :
    // only 2-token pools
    // froma registered factory
    constructor(
        IVault vault,
        address tokenAddress,
        address oracleAddress,
        address loyaltyModuleAddress,
        address volatilityModuleAddress
    ) VaultGuard(vault) {
        _tokenAddress = tokenAddress;
        _oracleAddress = oracleAddress;
        _loyaltyModuleAddress = loyaltyModuleAddress;
        _volatilityModuleAddress = volatilityModuleAddress;
    }

    // --------------------------------------------------------------------
    // ------------------------ Events & Errors ---------------------------
    // --------------------------------------------------------------------

    event PriceDataUpdated(uint256 tokenOutBalanceScaled18, uint256 tokenInBalanceScaled18, uint256 tokenPrice);

    // --------------------------------------------------------------------
    // ------------------------ Hook Stuff --------------------------------
    // --------------------------------------------------------------------

    // add checks :
    // only 2 token pools
    // from a registered factory
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override returns (bool) {
        return true;
    }

    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.enableHookAdjustedAmounts = false;
        hookFlags.shouldCallAfterSwap = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        return hookFlags;
    }

    function onAfterRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public override returns (bool, uint256[] memory) {
        console.log("(onAfterRemoveLiquidity) executed now");
        address[] memory tokenAddresses = getAllTokenConfigs(_factoryAddress); // -> need to do this cuz we do not know that what index points to what token address
        IVolatilityOracle volatilityOracle = IVolatilityOracle(_oracleAddress);
        uint256 tokenIndex;

        if (tokenAddresses[0] == _tokenAddress) {
            tokenIndex = 0;
            // emit event
        } else if (tokenAddresses[1] == _tokenAddress) {
            tokenIndex = 1;
            // emit event
        } else {
            // revert with error
        }

        volatilityOracle.updateOracle(balancesScaled18[1 - tokenIndex], balancesScaled18[tokenIndex]);

        return (true, amountsOutRaw); // check if false works here
    }

    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public override returns (bool, uint256[] memory) {
        console.log("(onAfterAddLiquidity) executed now");
        address[] memory tokenAddresses = getAllTokenConfigs(_factoryAddress); // -> need to do this cuz we do not know that what index points to what token address
        IVolatilityOracle volatilityOracle = IVolatilityOracle(_oracleAddress);
        uint256 tokenIndex;

        if (tokenAddresses[0] == _tokenAddress) {
            tokenIndex = 0;
            // emit event
        } else if (tokenAddresses[1] == _tokenAddress) {
            tokenIndex = 1;
            // emit event
        } else {
            // revert with error
        }

        volatilityOracle.updateOracle(balancesScaled18[1 - tokenIndex], balancesScaled18[tokenIndex]);

        return (true, amountsInRaw); // check if false works here
    }

    function onAfterSwap(AfterSwapParams calldata params) public override returns (bool, uint256) {
        // update volatility data
        console.log("(onAfterSwap) executed now");
        IVolatilityOracle volatilityOracle = IVolatilityOracle(_oracleAddress);
        if (address(params.tokenIn) == _tokenAddress) {
            volatilityOracle.updateOracle(params.tokenOutBalanceScaled18, params.tokenInBalanceScaled18);
            // emit event
        } else if (address(params.tokenOut) == _tokenAddress) {
            volatilityOracle.updateOracle(params.tokenInBalanceScaled18, params.tokenOutBalanceScaled18);
            // emit event
        } else {
            // revert with error
        }

        // update loyalty data

        address user = IRouterCommon(params.router).getSender();

        ILoyaltyDiscount loyaltyModule = ILoyaltyDiscount(_loyaltyModuleAddress);

        loyaltyModule.updateLoyaltyDataForUser(
            user,
            _tokenAddress,
            params.tokenIn,
            params.amountInScaled18,
            params.amountOutScaled18
        );

        return (true, params.amountCalculatedRaw);
    }

    // staticSwapFeePercentage -> split this between fixed and loyaltyFee
    // then add volatilityFee based on pool volatility
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        address user = IRouterCommon(params.router).getSender();

        uint256 swapFeePercentWithLoyaltyDiscount = _isLoyaltyDiscountEnabled
            ? getSwapFeeWithLoyaltyDiscount(user, staticSwapFeePercentage)
            : staticSwapFeePercentage;

        console.log(
            "(onComputeDynamicSwapFeePercentage) swapFeePercentWithLoyaltyDiscount",
            swapFeePercentWithLoyaltyDiscount
        );

        uint256 volatilityFeePercent = _isVolatilityFeeEnabled ? getVolatilityFee() : 0;

        console.log("(onComputeDynamicSwapFeePercentage) volatilityFee", volatilityFeePercent);

        uint256 totalSwapFeePercent = swapFeePercentWithLoyaltyDiscount + volatilityFeePercent;

        console.log("(onComputeDynamicSwapFeePercentage) totalSwapFeePercent", totalSwapFeePercent);

        return (true, totalSwapFeePercent);
    }

    // --------------------------------------------------------------------
    // ------------------- External Functions -----------------------------
    // --------------------------------------------------------------------

    function changeLoyaltyDiscountSetting() public {
        _isLoyaltyDiscountEnabled = !_isLoyaltyDiscountEnabled;
    }

    function changeVolatilityFeeSetting() public {
        _isVolatilityFeeEnabled = !_isVolatilityFeeEnabled;
    }

    // --------------------------------------------------------------------
    // ------------------------ internal functions ------------------------
    // --------------------------------------------------------------------

    function getSwapFeeWithLoyaltyDiscount(
        address user,
        uint256 staticSwapFeePercentage
    ) public view returns (uint256) {
        ILoyaltyDiscount loyaltyModule = ILoyaltyDiscount(_loyaltyModuleAddress);
        return loyaltyModule.getSwapFeeWithLoyaltyDiscount(user, staticSwapFeePercentage);
    }

    function getVolatilityFee() public view returns (uint256) {
        IVolatilityDiscount volatilityModule = IVolatilityDiscount(_volatilityModuleAddress);
        return volatilityModule.getVolatilityFeePercent(_oracleAddress);
    }

    function getAllTokenConfigs(address contractAddress) internal returns (address[] memory) {
        bytes memory data = abi.encodeWithSignature("tokenConfigs()");
        (bool success, bytes memory result) = contractAddress.call(data);
        require(success, "tokenConfigs call failed"); // change into revert
        address[] memory tokenAddresses = abi.decode(result, (address[]));
        console.log("tokenAddresses.length", tokenAddresses.length);

        return tokenAddresses;
    }
}