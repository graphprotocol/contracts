// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-strict-inequalities

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { StakingV4Storage } from "./StakingStorage.sol";
import { IStakingExtension } from "./IStakingExtension.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { IGraphToken } from "@graphprotocol/common/contracts/token/IGraphToken.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { Stakes } from "./libs/Stakes.sol";
import { IStakingData } from "./IStakingData.sol";
import { MathUtils } from "./libs/MathUtils.sol";

/**
 * @title StakingExtension contract
 * @author Edge & Node
 * @notice This contract provides the logic to manage delegations and other Staking
 * extension features (e.g. storage getters). It is meant to be called through delegatecall from the
 * Staking contract, and is only kept separate to keep the Staking contract size
 * within limits.
 */
contract StakingExtension is StakingV4Storage, GraphUpgradeable, IStakingExtension {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    /// @dev 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;
    /// @dev Minimum amount of tokens that can be delegated
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    /**
     * @dev Check if the caller is the slasher.
     */
    modifier onlySlasher() {
        require(__slashers[msg.sender] == true, "!slasher");
        _;
    }

    /**
     * @notice Initialize the StakingExtension contract
     * @dev This function is meant to be delegatecalled from the Staking contract's
     * initialize() function, so it uses the same access control check to ensure it is
     * being called by the Staking implementation as part of the proxy upgrade process.
     * @param _delegationUnbondingPeriod Delegation unbonding period in blocks
     * @param _cooldownBlocks Deprecated parameter (no longer used)
     * @param _delegationRatio Delegation capacity multiplier (e.g. 10 means 10x the indexer stake)
     * @param _delegationTaxPercentage Percentage of delegated tokens to burn as delegation tax, expressed in parts per million
     */
    function initialize(
        uint32 _delegationUnbondingPeriod,
        // solhint-disable-next-line no-unused-vars
        uint32 _cooldownBlocks, // deprecated
        uint32 _delegationRatio,
        uint32 _delegationTaxPercentage
    ) external onlyImpl {
        _setDelegationUnbondingPeriod(_delegationUnbondingPeriod);
        _setDelegationRatio(_delegationRatio);
        _setDelegationTaxPercentage(_delegationTaxPercentage);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function setDelegationTaxPercentage(uint32 _percentage) external override onlyGovernor {
        _setDelegationTaxPercentage(_percentage);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function setDelegationRatio(uint32 _delegationRatio) external override onlyGovernor {
        _setDelegationRatio(_delegationRatio);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function setDelegationUnbondingPeriod(uint32 _delegationUnbondingPeriod) external override onlyGovernor {
        _setDelegationUnbondingPeriod(_delegationUnbondingPeriod);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function setSlasher(address _slasher, bool _allowed) external override onlyGovernor {
        require(_slasher != address(0), "!slasher");
        __slashers[_slasher] = _allowed;
        emit SlasherUpdate(msg.sender, _slasher, _allowed);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function delegate(address _indexer, uint256 _tokens) external override notPartialPaused returns (uint256) {
        address delegator = msg.sender;

        // Transfer tokens to delegate to this contract
        TokenUtils.pullTokens(graphToken(), delegator, _tokens);

        // Update state
        return _delegate(delegator, _indexer, _tokens);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function undelegate(address _indexer, uint256 _shares) external override notPartialPaused returns (uint256) {
        return _undelegate(msg.sender, _indexer, _shares);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function withdrawDelegated(address _indexer, address _newIndexer) external override notPaused returns (uint256) {
        return _withdrawDelegated(msg.sender, _indexer, _newIndexer);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function slash(
        address _indexer,
        uint256 _tokens,
        uint256 _reward,
        address _beneficiary
    ) external override onlySlasher notPartialPaused {
        Stakes.Indexer storage indexerStake = __stakes[_indexer];

        // Only able to slash a non-zero number of tokens
        require(_tokens > 0, "!tokens");

        // Rewards comes from tokens slashed balance
        require(_tokens >= _reward, "rewards>slash");

        // Cannot slash stake of an indexer without any or enough stake
        require(indexerStake.tokensStaked > 0, "!stake");
        require(_tokens <= indexerStake.tokensStaked, "slash>stake");

        // Validate beneficiary of slashed tokens
        require(_beneficiary != address(0), "!beneficiary");

        // Slashing more tokens than freely available (over allocation condition)
        // Unlock locked tokens to avoid the indexer to withdraw them
        if (_tokens > indexerStake.tokensAvailable() && indexerStake.tokensLocked > 0) {
            uint256 tokensOverAllocated = _tokens.sub(indexerStake.tokensAvailable());
            uint256 tokensToUnlock = MathUtils.min(tokensOverAllocated, indexerStake.tokensLocked);
            indexerStake.unlockTokens(tokensToUnlock);
        }

        // Remove tokens to slash from the stake
        indexerStake.release(_tokens);

        // -- Interactions --

        IGraphToken graphToken = graphToken();

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        TokenUtils.burnTokens(graphToken, _tokens.sub(_reward));

        // Give the beneficiary a reward for slashing
        TokenUtils.pushTokens(graphToken, _beneficiary, _reward);

        emit StakeSlashed(_indexer, _tokens, _reward, _beneficiary);
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function getDelegation(address _indexer, address _delegator) external view override returns (Delegation memory) {
        return __delegationPools[_indexer].delegators[_delegator];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function delegationRatio() external view override returns (uint32) {
        return __delegationRatio;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function delegationUnbondingPeriod() external view override returns (uint32) {
        return __delegationUnbondingPeriod;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function delegationTaxPercentage() external view override returns (uint32) {
        return __delegationTaxPercentage;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function delegationPools(address _indexer) external view override returns (DelegationPoolReturn memory) {
        DelegationPool storage pool = __delegationPools[_indexer];
        return
            DelegationPoolReturn(
                0, // Blocks to wait before updating parameters (deprecated)
                pool.indexingRewardCut, // in PPM
                pool.queryFeeCut, // in PPM
                pool.updatedAtBlock, // Block when the pool was last updated
                pool.tokens, // Total tokens as pool reserves
                pool.shares // Total shares minted in the pool
            );
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function rewardsDestination(address _indexer) external view override returns (address) {
        return __rewardsDestination[_indexer];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function operatorAuth(address _indexer, address _maybeOperator) external view override returns (bool) {
        return __operatorAuth[_indexer][_maybeOperator];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function subgraphAllocations(bytes32 _subgraphDeploymentId) external view override returns (uint256) {
        return __subgraphAllocations[_subgraphDeploymentId];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function slashers(address _maybeSlasher) external view override returns (bool) {
        return __slashers[_maybeSlasher];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function minimumIndexerStake() external view override returns (uint256) {
        return __minimumIndexerStake;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function thawingPeriod() external view override returns (uint32) {
        return __thawingPeriod;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function curationPercentage() external view override returns (uint32) {
        return __curationPercentage;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function protocolPercentage() external view override returns (uint32) {
        return __protocolPercentage;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function maxAllocationEpochs() external view override returns (uint32) {
        return __maxAllocationEpochs;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function alphaNumerator() external view override returns (uint32) {
        return __alphaNumerator;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function alphaDenominator() external view override returns (uint32) {
        return __alphaDenominator;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function lambdaNumerator() external view override returns (uint32) {
        return __lambdaNumerator;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function lambdaDenominator() external view override returns (uint32) {
        return __lambdaDenominator;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function stakes(address _indexer) external view override returns (Stakes.Indexer memory) {
        return __stakes[_indexer];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function allocations(address _allocationID) external view override returns (IStakingData.Allocation memory) {
        return __allocations[_allocationID];
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function isDelegator(address _indexer, address _delegator) public view override returns (bool) {
        return __delegationPools[_indexer].delegators[_delegator].shares > 0;
    }

    /**
     * @inheritdoc IStakingExtension
     */
    function getWithdraweableDelegatedTokens(Delegation memory _delegation) public view override returns (uint256) {
        // There must be locked tokens and period passed
        uint256 currentEpoch = epochManager().currentEpoch();
        if (_delegation.tokensLockedUntil > 0 && currentEpoch >= _delegation.tokensLockedUntil) {
            return _delegation.tokensLocked;
        }
        return 0;
    }

    /**
     * @notice Internal: Set a delegation tax percentage to burn when delegated funds are deposited.
     * @param _percentage Percentage of delegated tokens to burn as delegation tax
     */
    function _setDelegationTaxPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        __delegationTaxPercentage = _percentage;
        emit ParameterUpdated("delegationTaxPercentage");
    }

    /**
     * @notice Internal: Set the delegation ratio.
     * If set to 10 it means the indexer can use up to 10x the indexer staked amount
     * from their delegated tokens
     * @param _delegationRatio Delegation capacity multiplier
     */
    function _setDelegationRatio(uint32 _delegationRatio) private {
        __delegationRatio = _delegationRatio;
        emit ParameterUpdated("delegationRatio");
    }

    /**
     * @notice Internal: Set the period for undelegation of stake from indexer.
     * @param _delegationUnbondingPeriod Period in epochs to wait for token withdrawals after undelegating
     */
    function _setDelegationUnbondingPeriod(uint32 _delegationUnbondingPeriod) private {
        require(_delegationUnbondingPeriod > 0, "!delegationUnbondingPeriod");
        __delegationUnbondingPeriod = _delegationUnbondingPeriod;
        emit ParameterUpdated("delegationUnbondingPeriod");
    }

    /**
     * @notice Delegate tokens to an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued of the delegation pool
     */
    function _delegate(address _delegator, address _indexer, uint256 _tokens) private returns (uint256) {
        // Only allow delegations over a minimum, to prevent rounding attacks
        require(_tokens >= MINIMUM_DELEGATION, "!minimum-delegation");
        // Only delegate to non-empty address
        require(_indexer != address(0), "!indexer");
        // Only delegate to staked indexer
        require(__stakes[_indexer].tokensStaked > 0, "!stake");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = __delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Collect delegation tax
        uint256 delegationTax = _collectTax(graphToken(), _tokens, __delegationTaxPercentage);
        uint256 delegatedTokens = _tokens.sub(delegationTax);

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? delegatedTokens : delegatedTokens.mul(pool.shares).div(pool.tokens);
        require(shares > 0, "!shares");

        // Update the delegation pool
        pool.tokens = pool.tokens.add(delegatedTokens);
        pool.shares = pool.shares.add(shares);

        // Update the individual delegation
        delegation.shares = delegation.shares.add(shares);

        emit StakeDelegated(_indexer, _delegator, delegatedTokens, shares);

        return shares;
    }

    /**
     * @notice Undelegate tokens from an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function _undelegate(address _delegator, address _indexer, uint256 _shares) private returns (uint256) {
        // Can only undelegate a non-zero amount of shares
        require(_shares > 0, "!shares");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = __delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Delegator need to have enough shares in the pool to undelegate
        require(delegation.shares >= _shares, "!shares-avail");

        // Withdraw tokens if available
        if (getWithdraweableDelegatedTokens(delegation) > 0) {
            _withdrawDelegated(_delegator, _indexer, address(0));
        }

        uint256 poolTokens = pool.tokens;
        uint256 poolShares = pool.shares;

        // Calculate tokens to get in exchange for the shares
        uint256 tokens = _shares.mul(poolTokens).div(poolShares);

        // Update the delegation pool
        poolTokens = poolTokens.sub(tokens);
        poolShares = poolShares.sub(_shares);
        pool.tokens = poolTokens;
        pool.shares = poolShares;

        // Update the delegation
        delegation.shares = delegation.shares.sub(_shares);
        // Enforce more than the minimum delegation is left,
        // to prevent rounding attacks
        if (delegation.shares > 0) {
            uint256 remainingDelegation = delegation.shares.mul(poolTokens).div(poolShares);
            require(remainingDelegation >= MINIMUM_DELEGATION, "!minimum-delegation");
        }
        delegation.tokensLocked = delegation.tokensLocked.add(tokens);
        delegation.tokensLockedUntil = epochManager().currentEpoch().add(__delegationUnbondingPeriod);

        emit StakeDelegatedLocked(_indexer, _delegator, tokens, _shares, delegation.tokensLockedUntil);

        return tokens;
    }

    /**
     * @notice Withdraw delegated tokens once the unbonding period has passed.
     * @param _delegator Delegator that is withdrawing tokens
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _delegateToIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     * @return Amount of tokens withdrawn or re-delegated
     */
    function _withdrawDelegated(
        address _delegator,
        address _indexer,
        address _delegateToIndexer
    ) private returns (uint256) {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = __delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Validation
        uint256 tokensToWithdraw = getWithdraweableDelegatedTokens(delegation);
        require(tokensToWithdraw > 0, "!tokens");

        // Reset lock
        delegation.tokensLocked = 0;
        delegation.tokensLockedUntil = 0;

        emit StakeDelegatedWithdrawn(_indexer, _delegator, tokensToWithdraw);

        // -- Interactions --

        if (_delegateToIndexer != address(0)) {
            // Re-delegate tokens to a new indexer
            _delegate(_delegator, _delegateToIndexer, tokensToWithdraw);
        } else {
            // Return tokens to the delegator
            TokenUtils.pushTokens(graphToken(), _delegator, tokensToWithdraw);
        }

        return tokensToWithdraw;
    }

    /**
     * @notice Collect tax to burn for an amount of tokens.
     * @param _graphToken Token to burn
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @param _percentage Percentage of tokens to burn as tax
     * @return Amount of tax charged
     */
    function _collectTax(IGraphToken _graphToken, uint256 _tokens, uint256 _percentage) private returns (uint256) {
        uint256 tax = uint256(_percentage).mul(_tokens).div(MAX_PPM);
        TokenUtils.burnTokens(_graphToken, tax); // Burn tax if any
        return tax;
    }
}
