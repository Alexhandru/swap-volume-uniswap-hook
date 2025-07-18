// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {VolumeBasedFeeHook} from "../src/VolumeBasedFeeHook.sol";
import {Constants} from "./base/Constants.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Mines the address and deploys the VolumeBasedFeeHook Hook contract
contract VolumeBasedFeeHookScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // Only need BEFORE_SWAP_FLAG for VolumeBasedFeeHook
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
        bytes memory constructorArgs = abi.encode(POOLMANAGER, params);
        (address hookAddress, bytes32 salt) = 
            HookMiner.find(CREATE2_DEPLOYER, flags, type(VolumeBasedFeeHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        VolumeBasedFeeHook volumeBasedFeeHook = new VolumeBasedFeeHook{salt: salt}(IPoolManager(POOLMANAGER), params);
        require(address(volumeBasedFeeHook) == hookAddress, "VolumeBasedFeeHookScript: hook address mismatch");

        console.log("VolumeBasedFeeHook deployed at:", address(volumeBasedFeeHook));
    }
}