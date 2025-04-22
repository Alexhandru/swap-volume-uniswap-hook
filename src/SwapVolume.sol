pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";


contract SwapVolume is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CustomRevert for bytes4;
    using PoolIdLibrary for PoolKey;

    error InvalidFees();
    error InvalidAmountThresholds();

    struct SwapVolumeParams {
        uint24 defaultFee;
        uint24 feeAtMinAmount0;
        uint24 feeAtMaxAmount0;
        uint24 feeAtMinAmount1;
        uint24 feeAtMaxAmount1;
        uint256 minAmount0;
        uint256 maxAmount0;
        uint256 minAmount1;
        uint256 maxAmount1;
    }

    uint24 immutable defaultFee;
    uint24 immutable feeAtMinAmount0;
    uint24 immutable feeAtMaxAmount0;
    uint24 immutable feeAtMinAmount1;
    uint24 immutable feeAtMaxAmount1;
    uint256 immutable minAmount0;
    uint256 immutable maxAmount0;
    uint256 immutable minAmount1;
    uint256 immutable maxAmount1;

    constructor(IPoolManager _poolManager, SwapVolumeParams memory params) BaseHook(_poolManager){
        if(params.feeAtMinAmount0 > params.defaultFee) InvalidFees.selector.revertWith();
        if(params.feeAtMaxAmount0 > params.feeAtMinAmount0) InvalidFees.selector.revertWith();
        if(params.feeAtMinAmount1 > params.defaultFee) InvalidFees.selector.revertWith();
        if(params.feeAtMaxAmount1 > params.feeAtMinAmount1) InvalidFees.selector.revertWith();
        if(params.minAmount0 >= params.maxAmount0) InvalidAmountThresholds.selector.revertWith();
        if(params.minAmount1 >= params.maxAmount1) InvalidAmountThresholds.selector.revertWith();

        defaultFee = params.defaultFee;
        feeAtMinAmount0 = params.feeAtMinAmount0;
        feeAtMaxAmount0 = params.feeAtMaxAmount0;
        feeAtMinAmount1 = params.feeAtMinAmount1;
        feeAtMaxAmount1 = params.feeAtMaxAmount1;
        minAmount0 = params.minAmount0;
        maxAmount0 = params.maxAmount0;
        minAmount1 = params.minAmount1;
        maxAmount1 = params.maxAmount1;
    }

    function getSwapVolumeParams() external view returns (SwapVolumeParams memory) {
        return SwapVolumeParams({
            defaultFee: defaultFee,
            feeAtMinAmount0: feeAtMinAmount0,
            feeAtMaxAmount0: feeAtMaxAmount0,
            feeAtMinAmount1: feeAtMinAmount1,
            feeAtMaxAmount1: feeAtMaxAmount1,
            minAmount0: minAmount0,
            maxAmount0: maxAmount0,
            minAmount1: minAmount1,
            maxAmount1: maxAmount1
        });
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        poolManager.updateDynamicLPFee(key, calculateFee(swapParams));
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function calculateFee(
        IPoolManager.SwapParams calldata swapParams
    ) internal view returns(uint24) {
        if(swapParams.zeroForOne) {
            if(swapParams.amountSpecified < 0) {
                return calculateFeePerScenario(
                    uint256(-swapParams.amountSpecified),
                    minAmount0,
                    maxAmount0,
                    feeAtMaxAmount0,
                    feeAtMinAmount0,
                    defaultFee
                );
            } else {
                return calculateFeePerScenario(
                    uint256(swapParams.amountSpecified),
                    minAmount1,
                    maxAmount1,
                    feeAtMaxAmount1,
                    feeAtMinAmount1,
                    defaultFee
                );
            }
        } else {
            if(swapParams.amountSpecified < 0) {
                return calculateFeePerScenario(
                    uint256(-swapParams.amountSpecified),
                    minAmount1,
                    maxAmount1,
                    feeAtMaxAmount1,
                    feeAtMinAmount1,
                    defaultFee
                );
            } else {
                return calculateFeePerScenario(
                    uint256(swapParams.amountSpecified),
                    minAmount0,
                    maxAmount0,
                    feeAtMaxAmount0,
                    feeAtMinAmount0,
                    defaultFee
                );
            }
        }
    }

    function calculateFeePerScenario(
        uint256 volume,
        uint256 minAmount,
        uint256 maxAmount,
        uint24 feeAtMaxAmount,
        uint24 feeAtMinAmount,
        uint24 defaultFee
    ) internal pure returns(uint24) {
        if(volume < minAmount){
            return defaultFee;
        }

        if(volume > maxAmount){
            return feeAtMaxAmount;
        }

        uint256 deltaFee = feeAtMinAmount - feeAtMaxAmount;
        uint256 feeDifference = (deltaFee * (volume - minAmount)) / (maxAmount - minAmount);
        return feeAtMinAmount - uint24(feeDifference);
    }
}