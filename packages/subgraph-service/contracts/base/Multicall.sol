// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one

import { IMulticall } from "@graphprotocol/interfaces/contracts/contracts/base/IMulticall.sol";

// Inspired by https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/base/Multicall.sol
// Note: Removed payable from the multicall

/**
 * @title Multicall
 * @author Edge & Node
 * @notice Enables calling multiple methods in a single call to the contract
 */
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            // forge-lint: disable-next-line(calls-loop)
            (bool success, bytes memory result) = address(this).delegatecall(data[i]); // solhint-disable-line avoid-low-level-calls

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                // forge-lint: disable-next-line(require-revert-in-loop)
                if (result.length < 68) revert();
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    result := add(result, 0x04)
                }
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
