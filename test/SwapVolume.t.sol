// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {SwapVolume} from "../src/SwapVolume.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {SwapVolumeHarness} from "./harnesses/SwapVolumeHarness.sol";

contract SwapVolumeTest is Test, Fixtures {
    using StateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    SwapVolume hook;

    uint24 defaultFee = 3000;
    uint24 feeAtMinAmount0 = 2700;
    uint24 feeAtMaxAmount0 = 2400;
    uint24 feeAtMinAmount1 = 2100;
    uint24 feeAtMaxAmount1 = 2000;
    uint256 minAmount0In = 1e18;
    uint256 maxAmount0In = 10e18;
    uint256 minAmount1In = 1e18;
    uint256 maxAmount1In = 10e18;

    uint160 flags = uint160(
                Hooks.BEFORE_SWAP_FLAG 
            ) ^ (0x4444 << 144); // Namespace the hook to avoid collisions

    SwapVolume.SwapVolumeParams swapVolumeParams = 
        SwapVolume.SwapVolumeParams({
            defaultFee: defaultFee,
            feeAtMinAmount0: feeAtMinAmount0,
            feeAtMaxAmount0: feeAtMaxAmount0,
            feeAtMinAmount1: feeAtMinAmount1,
            feeAtMaxAmount1: feeAtMaxAmount1,
            minAmount0In: minAmount0In,
            maxAmount0In: maxAmount0In,
            minAmount1In: minAmount1In,
            maxAmount1In: maxAmount1In
        });

    function setUp() public {
        deployFreshManagerAndRouters();

        hook = SwapVolume(
            address(flags)
        );

        deployCodeTo(
            "SwapVolume.sol:SwapVolume",
            abi.encode(
                manager,
                swapVolumeParams
            ),
            address(hook)
        );

        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    function test_revert_invalidFeeAtMinAmount0() public {
        uint24 invalidFeeAtMinAmount0 = defaultFee + 1; // Fee higher than defaultFee

        swapVolumeParams.feeAtMinAmount0 = invalidFeeAtMinAmount0;

        bytes memory constructorArgs = abi.encode(
            manager,
            swapVolumeParams
        );

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(abi.encodeWithSelector(SwapVolume.InvalidFee.selector, invalidFeeAtMinAmount0));
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_revert_invalidFeeAtMaxAmount0() public {
        uint24 invalidFeeAtMaxAmount0 = feeAtMinAmount0 + 1; // Fee higher than feeAtMinAmount0

        swapVolumeParams.feeAtMaxAmount0 = invalidFeeAtMaxAmount0;

        bytes memory constructorArgs = abi.encode(manager, swapVolumeParams);

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(abi.encodeWithSelector(SwapVolume.InvalidFee.selector, invalidFeeAtMaxAmount0));
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_revert_invalidFeeAtMinAmount1() public {
        uint24 invalidFeeAtMinAmount1 = defaultFee + 1; // Fee higher than defaultFee

        swapVolumeParams.feeAtMinAmount1 = invalidFeeAtMinAmount1;

        bytes memory constructorArgs = abi.encode(manager, swapVolumeParams);

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(abi.encodeWithSelector(SwapVolume.InvalidFee.selector, invalidFeeAtMinAmount1));
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_revert_invalidFeeAtMaxAmount1() public {
        uint24 invalidFeeAtMaxAmount1 = feeAtMinAmount1 + 1; // Fee higher than feeAtMinAmount1

        swapVolumeParams.feeAtMaxAmount1 = invalidFeeAtMaxAmount1;

        bytes memory constructorArgs = abi.encode(manager, swapVolumeParams);

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(abi.encodeWithSelector(SwapVolume.InvalidFee.selector, invalidFeeAtMaxAmount1));
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_revert_invalidAmountThresholds_minAmount0In() public {
        uint256 invalidMinAmount0In = maxAmount0In + 1; // minAmount0In greater than maxAmount0In

        swapVolumeParams.minAmount0In = invalidMinAmount0In;

        bytes memory constructorArgs = abi.encode(manager, swapVolumeParams);

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(SwapVolume.InvalidAmountThresholds.selector);
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_revert_invalidAmountThresholds_minAmount1In() public {
        uint256 invalidMinAmount1In = maxAmount1In + 1; // minAmount1In greater than maxAmount1In

        swapVolumeParams.minAmount1In = invalidMinAmount1In;

        bytes memory constructorArgs = abi.encode(manager, swapVolumeParams);

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolume).creationCode, constructorArgs);

        vm.expectRevert(SwapVolume.InvalidAmountThresholds.selector);
        new SwapVolume{salt: salt}(IPoolManager(manager), swapVolumeParams);
    }

    function test_swap_updateDynamicFee_defaultFee() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18 + 1; // Swap amount that doesn't hit min or max thresholds
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), defaultFee);
    }

    function test_swap_updateDynamicFee_mintAmount0_feeAtMinAmount0() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        
        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), feeAtMinAmount0);
    }

    function test_swap_updateDynamicFee_mintAmount0_feeAtMaxAmount0() public {
        bool zeroForOne = true;
        int256 amountSpecified = -10e18; // Exact input swap hitting max threshold
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), feeAtMaxAmount0);
    }

    function test_swap_updateDynamicFee_mintAmount1_feeAtMinAmount1() public {
        bool zeroForOne = false;
        int256 amountSpecified = -1e18; // Exact input swap hitting min threshold for token1
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), feeAtMinAmount1);
    }

    function test_swap_updateDynamicFee_mintAmount1_feeAtMaxAmount1() public {
        bool zeroForOne = false;
        int256 amountSpecified = -10e18; // Exact input swap hitting max threshold for token1
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), feeAtMaxAmount1);
    }

    function test_swap_middleVolume_exactInput_zeroForOne() public {
        bool zeroForOne = true;
        int256 amountSpecified = -int256((minAmount0In + maxAmount0In) / 2); // Dynamically calculate middle value
        uint24 expectedFee = uint24(feeAtMinAmount0 - ((feeAtMinAmount0 - feeAtMaxAmount0) * ((minAmount0In + maxAmount0In) / 2 - minAmount0In)) / (maxAmount0In - minAmount0In));
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), expectedFee);
    }

    function test_swap_middleVolume_exactOutput_zeroForOne() public {
        bool zeroForOne = true;
        int256 amountSpecified = int256((minAmount1In + maxAmount1In) / 2); // Dynamically calculate middle value
        uint24 expectedFee = uint24(feeAtMinAmount1 - ((feeAtMinAmount1 - feeAtMaxAmount1) * ((minAmount1In + maxAmount1In) / 2 - minAmount1In)) / (maxAmount1In - minAmount1In));
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), expectedFee);
    }

    function test_swap_middleVolume_exactInput_notZeroForOne() public {
        bool zeroForOne = false;
        int256 amountSpecified = -int256((minAmount1In + maxAmount1In) / 2); // Dynamically calculate middle value
        uint24 expectedFee = uint24(feeAtMinAmount1 - ((feeAtMinAmount1 - feeAtMaxAmount1) * ((minAmount1In + maxAmount1In) / 2 - minAmount1In)) / (maxAmount1In - minAmount1In));
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), expectedFee);
    }

    function test_swap_middleVolume_exactOutput_notZeroForOne() public {
        bool zeroForOne = false;
        int256 amountSpecified = int256((minAmount0In + maxAmount0In) / 2); // Dynamically calculate middle value
        uint24 expectedFee = uint24(feeAtMinAmount0 - ((feeAtMinAmount0 - feeAtMaxAmount0) * ((minAmount0In + maxAmount0In) / 2 - minAmount0In)) / (maxAmount0In - minAmount0In));
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        assertEq(_fetchPoolLPFee(key), expectedFee);
    }

    function test_fuzz_swapParams(
        uint24 _defaultFee,
        uint24 _feeAtMinAmount0,
        uint24 _feeAtMaxAmount0,
        uint24 _feeAtMinAmount1,
        uint24 _feeAtMaxAmount1,
        uint256 _minAmount0In,
        uint256 _maxAmount0In,
        uint256 _minAmount1In,
        uint256 _maxAmount1In,
        int256 _amountSpecified,
        uint8 _zeroForOne
    ) public {
        _defaultFee = uint24(bound(_defaultFee, 0, 1000000)); // 0% to 100%

        _feeAtMinAmount0 = uint24(bound(_feeAtMinAmount0, 0, _defaultFee)); // 0% to defaultFee
        _feeAtMaxAmount0 = uint24(bound(_feeAtMaxAmount0, 0, _feeAtMinAmount0)); // 0% to feeAtMinAmount0

        _feeAtMinAmount1 = uint24(bound(_feeAtMinAmount1, 0, _defaultFee)); // 0% to defaultFee
        _feeAtMaxAmount1 = uint24(bound(_feeAtMaxAmount1, 0, _feeAtMinAmount1)); // 0% to feeAtMinAmount1

        _minAmount0In = bound(_minAmount0In, 1, 10e18 - 1); // 1 to 10e18
        _maxAmount0In = bound(_maxAmount0In, _minAmount0In + 1, 10e18); // minAmount0In < maxAmount0In

        _minAmount1In = bound(_minAmount1In, 1, 10e18 - 1); // 1 to 10e18
        _maxAmount1In = bound(_maxAmount1In, _minAmount1In + 1, 10e18); // minAmount1In < maxAmount1In

        _zeroForOne = _zeroForOne % 2; // 0 or 1 

        bool zeroForOne = _zeroForOne == 1 ? true : false; // true or false

        bool exactInput = _amountSpecified < 0 ? true : false; // Check if it's an exact input swap
        int256 minAmount = zeroForOne ? 
            (exactInput ? int256(minAmount0In) : int256(_minAmount1In)) : 
            (exactInput ? int256(_minAmount1In) : int256(_minAmount0In));
        int256 maxAmount = zeroForOne ? 
            (exactInput ? int256(_maxAmount0In) : int256(_maxAmount1In)) : 
            (exactInput ? int256(_maxAmount1In) : int256(_maxAmount0In));

        vm.assume(_amountSpecified > 0); // Avoid zero amount
        // Determine the range for _amountSpecified based on _amountSpecified % 3
        if (_amountSpecified % 3 == 0) {
            _amountSpecified = bound(
                _amountSpecified,
                int256(1),
                minAmount == 1 ? int256(1) : minAmount - 1 
            ); // Between 1 and less than minAmount
        } else if (_amountSpecified % 3 == 1) {
            _amountSpecified = bound(
                _amountSpecified,
                minAmount,
                maxAmount
            ); // Between minAmount and maxAmount
        } else if (_amountSpecified % 3 == 2) {
            _amountSpecified = bound(
                _amountSpecified,
                maxAmount + 1, 
                int256(1e40)
            ); // Above maxAmount
        }

        _amountSpecified = exactInput ? -_amountSpecified : _amountSpecified; // Negate the amount if it's an exact input swap

        SwapVolume.SwapVolumeParams memory params = SwapVolume.SwapVolumeParams({
            defaultFee: _defaultFee,
            feeAtMinAmount0: _feeAtMinAmount0,
            feeAtMaxAmount0: _feeAtMaxAmount0,
            feeAtMinAmount1: _feeAtMinAmount1,
            feeAtMaxAmount1: _feeAtMaxAmount1,
            minAmount0In: _minAmount0In,
            maxAmount0In: _maxAmount0In,
            minAmount1In: _minAmount1In,
            maxAmount1In: _maxAmount1In
        });

        // Deploy the hook with the fuzzed parameters

        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(SwapVolumeHarness).creationCode, abi.encode(manager, params));  

        SwapVolumeHarness swapVolume = new SwapVolumeHarness{salt: salt}(IPoolManager(manager), params);

        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(swapVolume)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        // Perform the swap
        swap(key, zeroForOne, _amountSpecified, ZERO_BYTES);

        // Check the swap amounts
        uint24 expectedFee = swapVolume.exposed_calculateFee(
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: _amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            })
        );

        assertEq(_fetchPoolLPFee(key), expectedFee, "LP fee mismatch after swap");
    }

    function _fetchPoolLPFee(PoolKey memory _key) internal view returns (uint256 lpFee) {
        PoolId id = _key.toId();
        (,,, lpFee) = manager.getSlot0(id);
    }
}