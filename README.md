# SwapVolume Hook

The **SwapVolume** hook implements dynamic fees based on swap volume. The hook adjusts fees in a tiered structure based on swap amounts:
- **Below minAmount:** Uses `defaultFee`
- **Between minAmount and maxAmount:** Uses linear interpolation between `feeAtMinAmount` and `feeAtMaxAmount`
- **Above maxAmount:** Uses `feeAtMaxAmount`

Fee relationships must maintain:
- `feeAtMinAmount < defaultFee`
- `feeAtMaxAmount < feeAtMinAmount`
- `minAmount < maxAmount`

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh) (Forge)
- [Anvil](https://book.getfoundry.sh/anvil/) (for local development)

### Installation

Clone the repository and install dependencies:

```bash
forge install
```

## SwapVolume Hook Details

- **Source:** [`src/SwapVolume.sol`](src/SwapVolume.sol)
- **Interface:** [`src/interfaces/ISwapVolume.sol`](src/interfaces/ISwapVolume.sol)

The SwapVolume hook is designed to be deployed with a set of parameters encapsulated in the `ISwapVolume.SwapVolumeParams` struct.

### Example Parameters

```solidity
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
```

## Interacting with the SwapVolume Hook

Several scripts are provided in the `script/` folder to deploy and interact with the SwapVolume hook. These include:
- **Deployment via CREATE2:** [`SwapVolume.s.sol`](script/SwapVolume.s.sol)
- **Local lifecycle testing (pool initialization, liquidity provision, swaps):** [`Anvil.s.sol`](script/Anvil.s.sol)

### Deploying using Forge Scripts

#### Deploying the SwapVolume Hook

Use the following command to deploy the SwapVolume hook (via CREATE2) on your local network:

```bash
forge script script/SwapVolume.s.sol:SwapVolumeScript --rpc-url http://localhost:8545 --private-key <YOUR_PRIVATE_KEY> --broadcast
```

This script:
- Mines the correct salt (using `HookMiner`) for the given parameters and flags
- Deploys the SwapVolume hook with the provided parameters
- Logs the deployed hook address

#### Full Lifecycle Testing on Anvil

You can also run a full deployment and test lifecycle (pool creation, liquidity addition, and swapping) using:

```bash
forge script script/Anvil.s.sol:SwapVolumeScript --rpc-url http://localhost:8545 --private-key <YOUR_PRIVATE_KEY> --broadcast
```

The `Anvil.s.sol` script:
- Deploys a pool manager and the SwapVolume hook
- Sets up additional helper contracts (like the Position Manager and Routers)
- Initializes a pool using the SwapVolume hook
- Adds liquidity and performs a test swap for full-end-to-end verification

## Constants & Config Files

Two important files help configure and bootstrap the system:

### Constants File

[`script/base/Constants.sol`](script/base/Constants.sol)  
The **Constants** file contains shared, immutable parameters used across scripts. These include:

- **Deployer Addresses:**  
  The address from which CREATE2 deployments are performed (e.g., `CREATE2_DEPLOYER`).

- **Pool Manager & Other Contract Addresses:**  
  Pre-set addresses for key contracts such as the Pool Manager, Position Manager, and the Permit2 contract, which help in setting up the system on a local Anvil network.

This file centralizes addresses to keep scripts consistent and to easily change deployment configuration if needed.

### Config File

[`script/base/Config.sol`](script/base/Config.sol)  
The **Config** file (if present) is used to configure and fine-tune deployment parameters for different environments. It may include:
- Network-specific configurations
- Pool fee settings and tick spacing
- Default token amounts for liquidity, price parameters, and more

Using these files helps in keeping the deployment scripts clean—by abstracting environment-specific configuration details away from the logic in the scripts themselves.

## Debugging & Troubleshooting

### Common Issues

1. **Hook Deployment Failures:**
   - Verify that the deployment flags passed to `HookMiner.find` match the ones returned by `getHookCalls()` in your hook.
   - Ensure that the salt mining logic uses the same deployer address (in scripts, this should be the CREATE2 deployer at `0x4e59b44847b379578588920cA78FbF26c0B4956C`).

2. **Permission Denied / SSH Key Issues:**
   - If you encounter Github SSH errors, ensure your SSH keys are correctly added to your agent. Refer to [GitHub’s SSH setup guide](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh).

3. **Incorrect Fee or Parameter Issues:**
   - Ensure that the fee parameters follow the valid relationships:
     * `feeAtMinAmount < defaultFee`
     * `feeAtMaxAmount < feeAtMinAmount`
     * `minAmount < maxAmount`
   - You can add extra debugging logs within your hook to monitor fee calculations if needed.

### Additional Debugging Tips

- Use `console.log` statements in your script to output key variable values.
- Run your tests on Anvil locally and inspect the transaction logs via Foundry’s output.
- Check the [v4-core](https://github.com/uniswap/v4-core) and [v4-periphery](https://github.com/uniswap/v4-periphery) repositories for more detailed implementation examples.

