// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Staking } from "../../staking/Staking.sol";
import { IL2StakingBase } from "./IL2StakingBase.sol";
import { IL2Staking } from "./IL2Staking.sol";
import { Stakes } from "../../staking/libs/Stakes.sol";

/**
 * @title L2Staking contract
 * @dev This contract is the L2 variant of the Staking contract. It adds a function
 * to receive an indexer's stake or delegation from L1. Note that this contract inherits Staking,
 * which uses a StakingExtension contract to implement the full IStaking interface through delegatecalls.
 */
contract L2Staking is Staking, IL2StakingBase {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    /// @dev Minimum amount of tokens that can be delegated
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    /**
     * @dev Emitted when `delegator` delegated `tokens` to the `indexer`, the delegator
     * gets `shares` for the delegation pool proportionally to the tokens staked.
     * This is copied from IStakingExtension, but we can't inherit from it because we
     * don't implement the full interface here.
     */
    event StakeDelegated(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == address(graphTokenGateway()), "ONLY_GATEWAY");
        _;
    }

    /**
     * @notice Receive ETH into the L2Staking contract: this will always revert
     * @dev This function is only here to prevent ETH from being sent to the contract
     */
    receive() external payable {
        revert("RECEIVE_ETH_NOT_ALLOWED");
    }

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * @dev The encoded _data can contain information about an indexer's stake
     * or a delegator's delegation.
     * See L1MessageCodes in IL2Staking for the supported messages.
     * @param _from Token sender in L1
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data which must include a uint8 code and either a ReceiveIndexerStakeData or ReceiveDelegationData struct.
     */
    function onTokenTransfer(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external override notPartialPaused onlyL2Gateway {
        require(_from == counterpartStakingAddress, "ONLY_L1_STAKING_THROUGH_BRIDGE");
        (uint8 code, bytes memory functionData) = abi.decode(_data, (uint8, bytes));

        if (code == uint8(IL2Staking.L1MessageCodes.RECEIVE_INDEXER_STAKE_CODE)) {
            IL2Staking.ReceiveIndexerStakeData memory indexerData = abi.decode(
                functionData,
                (IL2Staking.ReceiveIndexerStakeData)
            );
            _receiveIndexerStake(_amount, indexerData);
        } else if (code == uint8(IL2Staking.L1MessageCodes.RECEIVE_DELEGATION_CODE)) {
            IL2Staking.ReceiveDelegationData memory delegationData = abi.decode(
                functionData,
                (IL2Staking.ReceiveDelegationData)
            );
            _receiveDelegation(_amount, delegationData);
        } else {
            revert("INVALID_CODE");
        }
    }

    /**
     * @dev Receive an Indexer's stake from L1.
     * The specified amount is added to the indexer's stake; the indexer's
     * address is specified in the _indexerData struct.
     * @param _amount Amount of tokens that were transferred
     * @param _indexerData struct containing the indexer's address
     */
    function _receiveIndexerStake(
        uint256 _amount,
        IL2Staking.ReceiveIndexerStakeData memory _indexerData
    ) internal {
        address _indexer = _indexerData.indexer;
        // Deposit tokens into the indexer stake
        __stakes[_indexer].deposit(_amount);

        // Initialize the delegation pool the first time
        if (__delegationPools[_indexer].updatedAtBlock == 0) {
            _setDelegationParameters(_indexer, MAX_PPM, MAX_PPM);
        }

        emit StakeDeposited(_indexer, _amount);
    }

    /**
     * @dev Receive a Delegator's delegation from L1.
     * The specified amount is added to the delegator's delegation; the delegator's
     * address and the indexer's address are specified in the _delegationData struct.
     * Note that no delegation tax is applied here.
     * @param _amount Amount of tokens that were transferred
     * @param _delegationData struct containing the delegator's address and the indexer's address
     */
    function _receiveDelegation(
        uint256 _amount,
        IL2Staking.ReceiveDelegationData memory _delegationData
    ) internal {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = __delegationPools[_delegationData.indexer];
        Delegation storage delegation = pool.delegators[_delegationData.delegator];

        // Calculate shares to issue (without applying any delegation tax)
        uint256 shares = (pool.tokens == 0) ? _amount : _amount.mul(pool.shares).div(pool.tokens);

        if (shares == 0 || _amount < MINIMUM_DELEGATION) {
            // If no shares would be issued (probably a rounding issue or attack),
            // or if the amount is under the minimum delegation (which could be part of a rounding attack),
            // return the tokens to the delegator
            graphToken().transfer(_delegationData.delegator, _amount);
            emit TransferredDelegationReturnedToDelegator(
                _delegationData.indexer,
                _delegationData.delegator,
                _amount
            );
        } else {
            // Update the delegation pool
            pool.tokens = pool.tokens.add(_amount);
            pool.shares = pool.shares.add(shares);

            // Update the individual delegation
            delegation.shares = delegation.shares.add(shares);

            emit StakeDelegated(
                _delegationData.indexer,
                _delegationData.delegator,
                _amount,
                shares
            );
        }
    }
}
