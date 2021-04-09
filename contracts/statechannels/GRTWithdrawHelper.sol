// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "../token/IGraphToken.sol";

import "./WithdrawHelper.sol";

/**
 * @title WithdrawHelper contract for GRT tokens
 * @notice This contract encodes the logic that connects the transfer of funds from a
 * Channel Multisig to the protocol in the context of a withdrawal.
 * A Channel Multisig will atomically transfer the tokens to the WithdrawHelper and then
 * these tokens will get pulled from the Staking contract using the `allocationID` passed
 * in the `callData` of the WithdrawCommitment.
 * Tokens transferred are associated to a particular allocation in the Staking contract.
 * This contract is not meant to hold funds, as they can be stolen by presenting a
 * handcrafted WithdrawalCommitment.
 */
contract GRTWithdrawHelper is WithdrawHelper {
    struct CollectData {
        address staking;
        address allocationID;
    }

    bytes4 private constant COLLECT_SELECTOR = bytes4(keccak256("collect(uint256,address)"));

    // -- State --

    address public tokenAddress;

    /**
     * @notice Contract constructor.
     * @param _tokenAddress Token address to use for transfers
     */
    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
    }

    /**
     * @notice Returns the ABI encoded representation of a CollectData struct.
     * @param _collectData CollectData struct with information about how to collect funds
     */
    function getCallData(CollectData calldata _collectData) public pure returns (bytes memory) {
        return abi.encode(_collectData);
    }

    /**
     * @notice Execute hook used by a channel to send funds to the protocol.
     * @param _wd WithdrawData struct for the withdrawal commitment
     * @param _actualAmount Amount to transfer to the Staking contract
     */
    function execute(WithdrawData calldata _wd, uint256 _actualAmount) external override {
        require(_wd.assetId == tokenAddress, "GRTWithdrawHelper: !token");

        // Decode and validate collect data
        CollectData memory collectData = abi.decode(_wd.callData, (CollectData));
        require(collectData.staking != address(0), "GRTWithdrawHelper: !staking");
        require(collectData.allocationID != address(0), "GRTWithdrawHelper: !allocationID");

        // Approve the staking contract to pull the transfer amount
        require(
            IGraphToken(_wd.assetId).approve(collectData.staking, _actualAmount),
            "GRTWithdrawHelper: !approve"
        );

        // Call the Staking contract to collect funds from this contract
        (bool success, ) =
            collectData.staking.call(
                abi.encodeWithSelector(COLLECT_SELECTOR, _actualAmount, collectData.allocationID)
            );

        // If the call fails return the funds to the channel multisig
        if (!success) {
            IGraphToken(_wd.assetId).transfer(_wd.channelAddress, _actualAmount);
        }
    }
}
