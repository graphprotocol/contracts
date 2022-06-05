// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IReservoir.sol";
import "../gelato/OpsReady.sol";
import "../governance/Managed.sol";
import "../upgrades/GraphUpgradeable.sol";

contract L1ReservoirDripKeeper is OpsReady, GraphUpgradeable, Managed {
    /**
     * @dev Initialize this contract.
     * The contract will be paused.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Drip indexer rewards for layers 1 and 2, sending a Gelato reward
     * This function will mint enough tokens to cover all indexer rewards for the next
     * dripInterval number of blocks. If the l2RewardsFraction is > 0, it will also send
     * tokens and a callhook to the L2Reservoir, through the GRT Arbitrum bridge.
     * Any staged changes to issuanceRate or l2RewardsFraction will be applied when this function
     * is called. If issuanceRate changes, it also triggers a snapshot of rewards per signal on the RewardsManager.
     * The call value must be equal to l2MaxSubmissionCost + (l2MaxGas * l2GasPriceBid), and must
     * only be nonzero if l2RewardsFraction is nonzero.
     * @param l2MaxGas Max gas for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     * @param l2GasPriceBid Gas price for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     * @param l2MaxSubmissionCost Max submission price for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     */
    function dripWithReward(
        uint256 l2MaxGas,
        uint256 l2GasPriceBid,
        uint256 l2MaxSubmissionCost
    ) external payable onlyOps {
        uint256 fee;
        address feeToken;

        (fee, feeToken) = IOps(ops).getFeeDetails();

        // Transfer the reward to Gelato
        _transfer(fee, feeToken);

        // (After Nitro) this will revert if we need to send to L2 and maxSubmissionCost is insufficient.
        IReservoir(_resolveContract(keccak256("Reservoir"))).drip(
            l2MaxGas,
            l2GasPriceBid,
            l2MaxSubmissionCost
        );
    }
}
