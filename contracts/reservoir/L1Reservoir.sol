// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../arbitrum/ITokenGateway.sol";

import "./IReservoir.sol";
import "./Reservoir.sol";
import "./L1ReservoirStorage.sol";

/**
 * @title L1 Rewards Reservoir
 * @dev This contract acts as a reservoir/vault for the rewards to be distributed on Layer 1.
 * It provides a function to periodically drip rewards, and functions to compute accumulated and new
 * total rewards at a particular block number.
 */
contract L1Reservoir is L1ReservoirV1Storage, Reservoir {
    using SafeMath for uint256;

    // Emitted when the initial supply snapshot is taken after contract deployment
    event InitialSnapshotTaken(
        uint256 blockNumber,
        uint256 issuanceBase,
        uint256 mintedPendingRewards
    );
    // Emitted when an issuance rate update is staged, to be applied on the next drip
    event IssuanceRateStaged(uint256 newValue);
    // Emitted when an L2 rewards fraction update is staged, to be applied on the next drip
    event L2RewardsFractionStaged(uint256 newValue);
    // Emitted when the L2 rewards fraction is updated (during a drip)
    event L2RewardsFractionUpdated(uint256 newValue);
    // Emitted when the drip interval is updated
    event DripIntervalUpdated(uint256 newValue);
    // Emitted when new rewards are dripped and potentially sent to L2
    event RewardsDripped(uint256 totalMinted, uint256 sentToL2, uint256 nextDeadline);
    // Emitted when the address for the L2Reservoir is updated
    event L2ReservoirAddressUpdated(address l2ReservoirAddress);

    /**
     * @dev Initialize this contract.
     * The contract will be paused.
     * Note that the contract is designed to not accrue rewards until the first call
     * to the drip function, that also requires the initial supply snapshot to be taken
     * using initialSnapshot. For this reason, issuanceRate and l2RewardsFraction
     * are not initialized here and instead need a call to setIssuanceRate and setL2RewardsFraction.
     * On the other hand, the l2ReservoirAddress is not expected to be known at initialization
     * time and must therefore be set using setL2ReservoirAddress.
     * The RewardsManager's address might also not be available in the controller at initialization
     * time, so approveRewardsManager() must be called separately as well.
     * @param _controller Address of the Controller that manages this contract
     * @param _dripInterval Drip interval, i.e. time period for which rewards are minted each time we drip
     */
    function initialize(address _controller, uint256 _dripInterval) external onlyImpl {
        Managed._initialize(_controller);
        _setDripInterval(_dripInterval);
    }

    /**
     * @dev Sets the drip interval.
     * This is the time in the future (in blocks) for which drip() will mint rewards.
     * Keep in mind that changing this value will require manually re-adjusting
     * the reservoir's token balance, because the first call to drip might produce
     * more or less tokens than needed.
     * @param _dripInterval The new interval in blocks for which drip() will mint rewards
     */
    function setDripInterval(uint256 _dripInterval) external onlyGovernor {
        _setDripInterval(_dripInterval);
    }

    /**
     * @dev Sets the issuance rate.
     * The issuance rate is defined as a relative increase of the total supply per block, plus 1.
     * This means that it needs to be greater than 1.0, any number under 1.0 is not
     * allowed and an issuance rate of 1.0 means no issuance.
     * To accommodate a high precision the issuance rate is expressed in wei, i.e. fixed point at 1e18.
     * Note: It is strongly recommended that the governor triggers a drip immediately after calling this,
     * including excess gas to guarantee that the L2 retryable ticket succeeds immediately, to ensure
     * good synchronization between L1 and L2.
     * @param _issuanceRate Issuance rate expressed in wei / fixed point at 1e18
     */
    function setIssuanceRate(uint256 _issuanceRate) external onlyGovernor {
        require(_issuanceRate >= MIN_ISSUANCE_RATE, "Issuance rate under minimum allowed");
        nextIssuanceRate = _issuanceRate;
        emit IssuanceRateStaged(_issuanceRate);
    }

    /**
     * @dev Sets the L2 rewards fraction.
     * This is the portion of the indexer rewards that are sent to L2.
     * The value is in fixed point at 1e18 and must be less than or equal to 1.
     * Note: It is strongly recommended that the governor triggers a drip immediately after calling this,
     * including excess gas to guarantee that the L2 retryable ticket succeeds immediately, to ensure
     * good synchronization between L1 and L2.
     * @param _l2RewardsFraction Fraction of rewards to send to L2, in wei / fixed point at 1e18
     */
    function setL2RewardsFraction(uint256 _l2RewardsFraction) external onlyGovernor {
        require(_l2RewardsFraction <= TOKEN_DECIMALS, "L2 Rewards fraction must be <= 1");
        nextL2RewardsFraction = _l2RewardsFraction;
        emit L2RewardsFractionStaged(_l2RewardsFraction);
    }

    /**
     * @dev Sets the L2 Reservoir address
     * This is the address on L2 to which we send tokens for rewards.
     * @param _l2ReservoirAddress New address for the L2Reservoir on L2
     */
    function setL2ReservoirAddress(address _l2ReservoirAddress) external onlyGovernor {
        require(_l2ReservoirAddress != address(0), "INVALID_L2_RESERVOIR");
        l2ReservoirAddress = _l2ReservoirAddress;
        emit L2ReservoirAddressUpdated(_l2ReservoirAddress);
    }

    /**
     * @dev Computes the initial snapshot for token supply and mints any pending rewards
     * This will initialize the issuanceBase to the current GRT supply, after which
     * we will keep an internal accounting only using newly minted rewards. This function
     * will also mint any pending rewards to cover up to the current block for open allocations,
     * to be computed off-chain. Can only be called once as it checks that the issuanceBase is zero.
     * @param _pendingRewards Pending rewards up to the current block for open allocations, to be minted by this function
     */
    function initialSnapshot(uint256 _pendingRewards) external onlyGovernor {
        require(issuanceBase == 0, "Cannot call this function more than once");
        lastRewardsUpdateBlock = block.number;
        IGraphToken grt = graphToken();
        grt.mint(address(this), _pendingRewards);
        issuanceBase = grt.totalSupply();
        emit InitialSnapshotTaken(block.number, issuanceBase, _pendingRewards);
    }

    /**
     * @dev Drip indexer rewards for layers 1 and 2
     * This function will mint enough tokens to cover all indexer rewards for the next
     * dripInterval number of blocks. If the l2RewardsFraction is > 0, it will also send
     * tokens and a callhook to the L2Reservoir, through the GRT Arbitrum bridge.
     * Any staged changes to issuanceRate or l2RewardsFraction will be applied when this function
     * is called. If issuanceRate changes, it also triggers a snapshot of rewards per signal on the RewardsManager.
     * The call value must be equal to l2MaxSubmissionCost + (l2MaxGas * l2GasPriceBid), and must
     * only be nonzero if l2RewardsFraction is nonzero.
     * Calling this function can revert if the issuance rate has recently been reduced, and the existing
     * tokens are sufficient to cover the full pending period. In this case, it's necessary to wait
     * until the drip amount becomes positive before calling the function again. It can also revert
     * if the l2RewardsFraction has been updated and the amount already sent to L2 is more than what we
     * should send now.
     * @param _l2MaxGas Max gas for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     * @param _l2GasPriceBid Gas price for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     * @param _l2MaxSubmissionCost Max submission price for the L2 retryable ticket, only needed if L2RewardsFraction is > 0
     */
    function drip(
        uint256 _l2MaxGas,
        uint256 _l2GasPriceBid,
        uint256 _l2MaxSubmissionCost
    ) external payable notPaused {
        uint256 mintedRewardsTotal = getNewGlobalRewards(rewardsMintedUntilBlock);
        uint256 mintedRewardsActual = getNewGlobalRewards(block.number);
        // eps = (signed int) mintedRewardsTotal - mintedRewardsActual

        if (nextIssuanceRate != issuanceRate) {
            rewardsManager().updateAccRewardsPerSignal();
            snapshotAccumulatedRewards(mintedRewardsActual); // This updates lastRewardsUpdateBlock
            issuanceRate = nextIssuanceRate;
            emit IssuanceRateUpdated(issuanceRate);
        } else {
            snapshotAccumulatedRewards(mintedRewardsActual);
        }

        rewardsMintedUntilBlock = block.number.add(dripInterval);
        // n = deltaR(t1, t0)
        uint256 newRewardsToDistribute = getNewGlobalRewards(rewardsMintedUntilBlock);
        // N = n - eps
        uint256 tokensToMint;
        {
            uint256 newRewardsPlusMintedActual = newRewardsToDistribute.add(mintedRewardsActual);
            require(
                newRewardsPlusMintedActual >= mintedRewardsTotal,
                "Would mint negative tokens, wait before calling again"
            );
            tokensToMint = newRewardsPlusMintedActual.sub(mintedRewardsTotal);
        }

        if (tokensToMint > 0) {
            graphToken().mint(address(this), tokensToMint);
        }

        uint256 tokensToSendToL2 = 0;
        if (l2RewardsFraction != nextL2RewardsFraction) {
            tokensToSendToL2 = nextL2RewardsFraction.mul(newRewardsToDistribute).div(
                TOKEN_DECIMALS
            );
            if (mintedRewardsTotal > mintedRewardsActual) {
                // eps > 0, i.e. t < t1_old
                // Note this can fail if the old l2RewardsFraction is larger
                // than the new, in which case we just have to wait until enough time has passed
                // so that eps is small enough. This also applies to the case where the new
                // l2RewardsFraction is zero, since we still need to send one last message
                // with the new values to the L2Reservoir.
                uint256 l2OffsetAmount = l2RewardsFraction
                    .mul(mintedRewardsTotal.sub(mintedRewardsActual))
                    .div(TOKEN_DECIMALS);
                require(
                    tokensToSendToL2 > l2OffsetAmount,
                    "Negative amount would be sent to L2, wait before calling again"
                );
                tokensToSendToL2 = tokensToSendToL2.sub(l2OffsetAmount);
            } else {
                tokensToSendToL2 = tokensToSendToL2.add(
                    l2RewardsFraction.mul(mintedRewardsActual.sub(mintedRewardsTotal)).div(
                        TOKEN_DECIMALS
                    )
                );
            }
            l2RewardsFraction = nextL2RewardsFraction;
            emit L2RewardsFractionUpdated(l2RewardsFraction);
            _sendNewTokensAndStateToL2(
                tokensToSendToL2,
                _l2MaxGas,
                _l2GasPriceBid,
                _l2MaxSubmissionCost
            );
        } else if (l2RewardsFraction > 0) {
            tokensToSendToL2 = tokensToMint.mul(l2RewardsFraction).div(TOKEN_DECIMALS);
            _sendNewTokensAndStateToL2(
                tokensToSendToL2,
                _l2MaxGas,
                _l2GasPriceBid,
                _l2MaxSubmissionCost
            );
        } else {
            // Avoid locking funds in this contract if we don't need to
            // send a message to L2.
            require(msg.value == 0, "No eth value needed");
        }
        emit RewardsDripped(tokensToMint, tokensToSendToL2, rewardsMintedUntilBlock);
    }

    /**
     * @dev Get new total rewards on both layers at a particular block, since the last drip event
     * This is deltaR = p * r ^ (blocknum - t0) - p, where:
     * - p is the total token supply snapshot at t0
     * - t0 is the last drip block, i.e. lastRewardsUpdateBlock
     * - r is the issuanceRate
     * @param _blocknum Block number at which to calculate rewards
     * @return New total rewards on both layers since the last drip
     */
    function getNewGlobalRewards(uint256 _blocknum) public view returns (uint256) {
        uint256 t0 = lastRewardsUpdateBlock;
        if (issuanceRate <= MIN_ISSUANCE_RATE || _blocknum == t0) {
            return 0;
        }
        return
            issuanceBase
                .mul(_pow(issuanceRate, _blocknum.sub(t0), TOKEN_DECIMALS))
                .div(TOKEN_DECIMALS)
                .sub(issuanceBase);
    }

    /**
     * @dev Get new total rewards on this layer at a particular block, since the last drip event
     * This is deltaR_L1 = (1-lambda) * deltaR, where:
     * - deltaR is the new global rewards on both layers (see getNewGlobalRewards)
     * - lambda is the fraction of rewards sent to L2, i.e. l2RewardsFraction
     * @param _blocknum Block number at which to calculate rewards
     * @return New total rewards on Layer 1 since the last drip
     */
    function getNewRewards(uint256 _blocknum) public view override returns (uint256) {
        return
            getNewGlobalRewards(_blocknum).mul(TOKEN_DECIMALS.sub(l2RewardsFraction)).div(
                TOKEN_DECIMALS
            );
    }

    /**
     * @dev Sets the drip interval (internal).
     * This is the time in the future (in blocks) for which drip() will mint rewards.
     * Keep in mind that changing this value will require manually re-adjusting
     * the reservoir's token balance, because the first call to drip might produce
     * more or less tokens than needed.
     * @param _dripInterval The new interval in blocks for which drip() will mint rewards
     */
    function _setDripInterval(uint256 _dripInterval) internal {
        require(_dripInterval > 0, "Drip interval must be > 0");
        dripInterval = _dripInterval;
        emit DripIntervalUpdated(_dripInterval);
    }

    /**
     * @dev Snapshot accumulated rewards on this layer
     * We compute accumulatedLayerRewards and mark this block as the lastRewardsUpdateBlock.
     * We also update the issuanceBase by adding the new total rewards on both layers.
     * @param _globalDelta New global rewards (i.e. rewards on L1 and L2) since the last update block
     */
    function snapshotAccumulatedRewards(uint256 _globalDelta) internal {
        issuanceBase = issuanceBase + _globalDelta;
        // Reimplementation of getAccumulatedRewards but reusing the _globalDelta calculated above,
        // to save gas
        accumulatedLayerRewards =
            accumulatedLayerRewards +
            _globalDelta.mul(TOKEN_DECIMALS.sub(l2RewardsFraction)).div(TOKEN_DECIMALS);
        lastRewardsUpdateBlock = block.number;
    }

    /**
     * @dev Send new tokens and a message with state to L2
     * This function will use the L1GraphTokenGateway to send tokens
     * to L2, and will also encode a callhook to update state on the L2Reservoir.
     * @param _nTokens Number of tokens to send to L2
     * @param _maxGas Max gas for the L2 retryable ticket execution
     * @param _gasPriceBid Gas price for the L2 retryable ticket execution
     * @param _maxSubmissionCost Max submission price for the L2 retryable ticket
     */
    function _sendNewTokensAndStateToL2(
        uint256 _nTokens,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) internal {
        uint256 l2IssuanceBase = l2RewardsFraction.mul(issuanceBase).div(TOKEN_DECIMALS);
        bytes memory extraData = abi.encodeWithSelector(
            IL2Reservoir.receiveDrip.selector,
            l2IssuanceBase,
            issuanceRate,
            nextDripNonce
        );
        nextDripNonce = nextDripNonce.add(1);
        bytes memory data = abi.encode(_maxSubmissionCost, extraData);
        IGraphToken grt = graphToken();
        ITokenGateway gateway = ITokenGateway(_resolveContract(keccak256("GraphTokenGateway")));
        grt.approve(address(gateway), _nTokens);
        gateway.outboundTransfer{ value: msg.value }(
            address(grt),
            l2ReservoirAddress,
            _nTokens,
            _maxGas,
            _gasPriceBid,
            data
        );
    }
}
