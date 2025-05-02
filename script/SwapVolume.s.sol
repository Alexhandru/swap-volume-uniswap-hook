// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {SwapVolume} from "../src/SwapVolume.sol";
import {ISwapVolume} from "../src/interfaces/ISwapVolume.sol";
import {Constants} from "./base/Constants.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Mines the address and deploys the SwapVolume Hook contract
contract SwapVolumeScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // Only need BEFORE_SWAP_FLAG for SwapVolume
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Define SwapVolume parameters
        ISwapVolume.SwapVolumeParams memory params = ISwapVolume.SwapVolumeParams({
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
        bytes memory constructorArgs = abi.encode(POOLMANAGER, params);
        (address hookAddress, bytes32 salt) = 
            HookMiner.find(CREATE2_DEPLOYER, flags, type(SwapVolume).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        SwapVolume swapVolume = new SwapVolume{salt: salt}(IPoolManager(POOLMANAGER), params);
        require(address(swapVolume) == hookAddress, "SwapVolumeScript: hook address mismatch");

        console.log("SwapVolume deployed at:", address(swapVolume));
    }
}