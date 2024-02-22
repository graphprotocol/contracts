// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GraphTokenLockWallet } from "./GraphTokenLockWallet.sol";
import { Ownable as OwnableInitializable } from "./Ownable.sol";
import { L2GraphTokenLockManager } from "./L2GraphTokenLockManager.sol";

/**
 * @title L2GraphTokenLockWallet
 * @notice This contract is built on top of the base GraphTokenLock functionality.
 * It allows wallet beneficiaries to use the deposited funds to perform specific function calls
 * on specific contracts.
 *
 * The idea is that supporters with locked tokens can participate in the protocol
 * but disallow any release before the vesting/lock schedule.
 * The beneficiary can issue authorized function calls to this contract that will
 * get forwarded to a target contract. A target contract is any of our protocol contracts.
 * The function calls allowed are queried to the GraphTokenLockManager, this way
 * the same configuration can be shared for all the created lock wallet contracts.
 *
 * This L2 variant includes a special initializer so that it can be created from
 * a wallet's data received from L1. These transferred wallets will not allow releasing
 * funds in L2 until the end of the vesting timeline, but they can allow withdrawing
 * funds back to L1 using the L2GraphTokenLockTransferTool contract.
 *
 * Note that surplusAmount and releasedAmount in L2 will be skewed for wallets received from L1,
 * so releasing surplus tokens might also only be possible by bridging tokens back to L1.
 *
 * NOTE: Contracts used as target must have its function signatures checked to avoid collisions
 * with any of this contract functions.
 * Beneficiaries need to approve the use of the tokens to the protocol contracts. For convenience
 * the maximum amount of tokens is authorized.
 * Function calls do not forward ETH value so DO NOT SEND ETH TO THIS CONTRACT.
 */
contract L2GraphTokenLockWallet is GraphTokenLockWallet {
    // Initializer when created from a message from L1
    function initializeFromL1(
        address _manager,
        address _token,
        L2GraphTokenLockManager.TransferredWalletData calldata _walletData
    ) external {
        require(!isInitialized, "Already initialized");
        isInitialized = true;

        OwnableInitializable._initialize(_walletData.owner);
        beneficiary = _walletData.beneficiary;
        token = IERC20(_token);

        managedAmount = _walletData.managedAmount;

        startTime = _walletData.startTime;
        endTime = _walletData.endTime;
        periods = 1;
        isAccepted = true;

        // Optionals
        releaseStartTime = _walletData.endTime;
        revocable = Revocability.Disabled;

        _setManager(_manager);
    }
}
