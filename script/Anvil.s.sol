// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {VolumeBasedFeeHook} from "../src/VolumeBasedFeeHook.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {EasyPosm} from "../test/utils/EasyPosm.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../test/utils/forks/DeployPermit2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";

/// @notice Forge script for deploying v4 & hooks to anvil
contract VolumeBasedFeeHookScript is Script, DeployPermit2 {
    using EasyPosm for IPositionManager;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    IPoolManager manager;
    IPositionManager posm;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;

    function setUp() public {}

    function run() public {
        vm.broadcast();
        manager = deployPoolManager();

        // For VolumeBasedFeeHook, only the BEFORE_SWAP_FLAG is needed.
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Define VolumeBasedFeeHook parameters
        VolumeBasedFeeHook.SwapVolumeParams memory params = VolumeBasedFeeHook.SwapVolumeParams({
            defaultFee: 3000,      // 0.3%
            feeAtMinAmount0: 2700, // 0.27%
            feeAtMaxAmount0: 2400, // 0.24%
            feeAtMinAmount1: 2100, // 0.21%
            feeAtMaxAmount1: 2000, // 0.20%
            minAmount0: 1e18,      // 1 token0
            maxAmount0: 10e18,     // 10 token0
            minAmount1: 1e18,      // 1 token1
            maxAmount1: 10e18      // 10 token1
        });

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(address(manager), params);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(VolumeBasedFeeHook).creationCode, constructorArgs);

        // Deploy the VolumeBasedFeeHook hook using CREATE2
        vm.broadcast();
        VolumeBasedFeeHook VolumeBasedFeeHook = new VolumeBasedFeeHook{salt: salt}(manager, params);
        require(address(VolumeBasedFeeHook) == hookAddress, "VolumeBasedFeeHookScript: hook address mismatch");

        // Deploy additional helper contracts
        vm.startBroadcast();
        posm = deployPosm(manager);
        (lpRouter, swapRouter,) = deployRouters(manager);
        vm.stopBroadcast();

        // Test lifecycle: create pool, add liquidity, swap using the deployed VolumeBasedFeeHook hook.
        vm.startBroadcast();
        testLifecycle(address(VolumeBasedFeeHook));
        vm.stopBroadcast();
    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------
    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }

    function deployRouters(IPoolManager _manager)
        internal
        returns (PoolModifyLiquidityTest _lpRouter, PoolSwapTest _swapRouter, PoolDonateTest _donateRouter)
    {
        _lpRouter = new PoolModifyLiquidityTest(_manager);
        _swapRouter = new PoolSwapTest(_manager);
        _donateRouter = new PoolDonateTest(_manager);
    }

    function deployPosm(IPoolManager poolManager) public returns (IPositionManager) {
        anvilPermit2();
        return IPositionManager(
            new PositionManager(poolManager, permit2, 300_000, IPositionDescriptor(address(0)), IWETH9(address(0)))
        );
    }

    function approvePosmCurrency(IPositionManager _posm, Currency currency) internal {
        // POSM uses permit2 so we must execute two approvals:
        // 1. Approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        // 2. Approve POSM as a spender via permit2.
        permit2.approve(Currency.unwrap(currency), address(_posm), type(uint160).max, type(uint48).max);
    }

    function deployTokens() internal returns (MockERC20 token0, MockERC20 token1) {
        MockERC20 tokenA = new MockERC20("MockA", "A", 18);
        MockERC20 tokenB = new MockERC20("MockB", "B", 18);
        if (uint160(address(tokenA)) < uint160(address(tokenB))) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }
    }

    function testLifecycle(address hook) internal {
        (MockERC20 token0, MockERC20 token1) = deployTokens();
        token0.mint(msg.sender, 100_000 ether);
        token1.mint(msg.sender, 100_000 ether);

        // Initialize the pool using the VolumeBasedFeeHook hook
        int24 tickSpacing = 60;
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Approve tokens to the routers and POSM
        token0.approve(address(lpRouter), type(uint256).max);
        token1.approve(address(lpRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        approvePosmCurrency(posm, Currency.wrap(address(token0)));
        approvePosmCurrency(posm, Currency.wrap(address(token1)));

        // Add full-range liquidity to the pool
        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(tickSpacing);
        _exampleAddLiquidity(poolKey, tickLower, tickUpper);

        // Swap some tokens
        _exampleSwap(poolKey);
    }

    function _exampleAddLiquidity(PoolKey memory poolKey, int24 tickLower, int24 tickUpper) internal {
        // Provision full-range liquidity using two different interfaces for example purposes
        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams(tickLower, tickUpper, 100 ether, 0);
        lpRouter.modifyLiquidity(poolKey, liqParams, "");

        posm.mint(poolKey, tickLower, tickUpper, 100e18, 10_000e18, 10_000e18, msg.sender, block.timestamp + 300, "");
    }

    function _exampleSwap(PoolKey memory poolKey) internal {
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(poolKey, params, testSettings, "");
    }
}