// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../reservoir/IReservoir.sol";
import "../../reservoir/Reservoir.sol";
import "./L2ReservoirStorage.sol";

/**
 * @title L2 Rewards Reservoir
 * @dev This contract acts as a reservoir/vault for the rewards to be distributed on Layer 2.
 * It receives tokens for rewards from L1, and provides functions to compute accumulated and new
 * total rewards at a particular block number.
 */
contract L2Reservoir is L2ReservoirV1Storage, Reservoir, IL2Reservoir {
    using SafeMath for uint256;

    event DripReceived(uint256 _normalizedTokenSupply);
    event NextDripNonceUpdated(uint256 _nonce);

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == _resolveContract(keccak256("GraphTokenGateway")), "ONLY_GATEWAY");
        _;
    }

    /**
     * @dev Initialize this contract.
     * The contract will be paused.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Update the next drip nonce
     * To be used only as a backup option if the two layers get out of sync.
     * @param _nonce Expected value for the nonce of the next drip message
     */
    function setNextDripNonce(uint256 _nonce) external onlyGovernor {
        nextDripNonce = _nonce;
        emit NextDripNonceUpdated(_nonce);
    }

    /**
     * @dev Get new total rewards accumulated since the last drip.
     * This is deltaR = p * r ^ (blocknum - t0) - p, where:
     * - p is the normalized token supply snapshot at t0
     * - t0 is the last drip block, i.e. lastRewardsUpdateBlock
     * - r is the issuanceRate
     * @param blocknum Block number at which to calculate rewards
     * @return deltaRewards New total rewards on L2 since the last drip
     */
    function getNewRewards(uint256 blocknum)
        public
        view
        override(Reservoir, IReservoir)
        returns (uint256 deltaRewards)
    {
        uint256 t0 = lastRewardsUpdateBlock;
        if (issuanceRate <= MIN_ISSUANCE_RATE || blocknum == t0) {
            return 0;
        }
        deltaRewards = normalizedTokenSupplyCache
            .mul(_pow(issuanceRate, blocknum.sub(t0), TOKEN_DECIMALS))
            .div(TOKEN_DECIMALS)
            .sub(normalizedTokenSupplyCache);
    }

    /**
     * @dev Receive dripped tokens from L1.
     * This function can only be called by the gateway, as it is
     * meant to be a callhook when receiving tokens from L1. It
     * updates the normalizedTokenSupplyCache and issuanceRate,
     * and snapshots the accumulated rewards. If issuanceRate changes,
     * it also triggers a snapshot of rewards per signal on the RewardsManager.
     * @param _normalizedTokenSupply Snapshot of total GRT supply multiplied by L2 rewards fraction
     * @param _issuanceRate Rewards issuance rate, using fixed point at 1e18, and including a +1
     * @param _nonce Incrementing nonce to ensure messages are received in order
     */
    function receiveDrip(
        uint256 _normalizedTokenSupply,
        uint256 _issuanceRate,
        uint256 _nonce
    ) external override onlyL2Gateway {
        require(_nonce == nextDripNonce, "INVALID_NONCE");
        nextDripNonce = nextDripNonce.add(1);
        if (_issuanceRate != issuanceRate) {
            rewardsManager().updateAccRewardsPerSignal();
            snapshotAccumulatedRewards();
            issuanceRate = _issuanceRate;
            emit IssuanceRateUpdated(_issuanceRate);
        } else {
            snapshotAccumulatedRewards();
        }
        normalizedTokenSupplyCache = _normalizedTokenSupply;
        emit DripReceived(normalizedTokenSupplyCache);
    }

    /**
     * @dev Snapshot accumulated rewards on this layer
     * We compute accumulatedLayerRewards and mark this block as the lastRewardsUpdateBlock.
     */
    function snapshotAccumulatedRewards() internal {
        accumulatedLayerRewards = getAccumulatedRewards(block.number);
        lastRewardsUpdateBlock = block.number;
    }
}
