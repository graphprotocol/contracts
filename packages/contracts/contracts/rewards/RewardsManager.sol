// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../upgrades/GraphUpgradeable.sol";
import "../staking/libs/MathUtils.sol";

import "./RewardsManagerStorage.sol";
import "./IRewardsManager.sol";
import "../allocate/IIssuanceAllocator.sol";
import "../allocate/IIssuanceTarget.sol";

/**
 * @title Rewards Manager Contract
 * @dev Tracks how inflationary GRT rewards should be handed out. Relies on the Curation contract
 * and the Staking contract. Signaled GRT in Curation determine what percentage of the tokens go
 * towards each subgraph. Then each Subgraph can have multiple Indexers Staked on it. Thus, the
 * total rewards for the Subgraph are split up for each Indexer based on much they have Staked on
 * that Subgraph.
 *
 * Note:
 * The contract provides getter functions to query the state of accrued rewards:
 * - getAccRewardsPerSignal
 * - getAccRewardsForSubgraph
 * - getAccRewardsPerAllocatedToken
 * - getRewards
 * These functions may overestimate the actual rewards due to changes in the total supply
 * until the actual takeRewards function is called.
 */
contract RewardsManager is RewardsManagerV4Storage, GraphUpgradeable, IRewardsManager, IIssuanceTarget {
    using SafeMath for uint256;

    uint256 private constant FIXED_POINT_SCALING_FACTOR = 1e18;

    // -- Namespaced Storage --

    /// @custom:storage-location erc7201:graphprotocol.storage.RewardsManager
    struct RewardsManagerData {
        // Address of the issuance allocator
        address issuanceAllocator;
        // Address of the service quality oracle contract
        IServiceQualityOracle serviceQualityOracle;

        // Add any new storage variables here
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.RewardsManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RewardsManagerStorageLocation =
        0x9fdd92e6e31da4e559d6f92dbd1fea63f400785c9e6dcd98c8d0c1fe96c42200;

    function _getRewardsManagerStorage() internal pure returns (RewardsManagerData storage $) {
        assembly {
            $.slot := RewardsManagerStorageLocation
        }
    }

    // -- Events --

    /**
     * @dev Emitted when rewards are assigned to an indexer.
     */
    event RewardsAssigned(address indexed indexer, address indexed allocationID, uint256 epoch, uint256 amount);

    /**
     * @dev Emitted when rewards are denied to an indexer.
     */
    event RewardsDenied(address indexed indexer, address indexed allocationID, uint256 epoch);

    /**
     * @dev Emitted when rewards are denied to an indexer due to service quality.
     */
    event RewardsDeniedDueToServiceQuality(address indexed indexer, address indexed allocationID, uint256 amount);

    /**
     * @dev Emitted when a subgraph is denied for claiming rewards.
     */
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);

    /**
     * @dev Emitted when the issuance allocator is set
     */
    event IssuanceAllocatorSet(address indexed oldIssuanceAllocator, address indexed newIssuanceAllocator);

    /**
     * @dev Emitted when the service quality oracle contract is set
     */
    event ServiceQualityOracleSet(address indexed oldServiceQualityOracle, address indexed newServiceQualityOracle);

    // -- Modifiers --

    modifier onlySubgraphAvailabilityOracle() {
        require(msg.sender == address(subgraphAvailabilityOracle), "Caller must be the subgraph availability oracle");
        _;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    // -- Config --

    /**
     * @dev Sets the GRT issuance per block directly.
     * The issuance is defined as a fixed amount of rewards per block in GRT.
     * This function can only be called when no IssuanceAllocator is set.
     * When using an IssuanceAllocator, issuance is controlled centrally through that contract.
     * @param _issuancePerBlock Issuance expressed in GRT per block (scaled by 1e18)
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external override onlyGovernor {
        // Revert if IssuanceAllocator is set - issuance should be controlled by the allocator
        require(_getRewardsManagerStorage().issuanceAllocator == address(0), "Use IssuanceAllocator");
        _setIssuancePerBlock(_issuancePerBlock);
    }

    /**
     * @dev Sets the GRT issuance per block.
     * The issuance is defined as a fixed amount of rewards per block in GRT.
     * @param _issuancePerBlock Issuance expressed in GRT per block (scaled by 1e18)
     */
    function _setIssuancePerBlock(uint256 _issuancePerBlock) private {
        // Called since `issuance per block` will change
        updateAccRewardsPerSignal();

        issuancePerBlock = _issuancePerBlock;
        emit ParameterUpdated("issuancePerBlock");
    }

    /**
     * @dev Sets the subgraph oracle allowed to denegate distribution of rewards to subgraphs.
     * @param _subgraphAvailabilityOracle Address of the subgraph availability oracle
     */
    function setSubgraphAvailabilityOracle(address _subgraphAvailabilityOracle) external override onlyGovernor {
        subgraphAvailabilityOracle = _subgraphAvailabilityOracle;
        emit ParameterUpdated("subgraphAvailabilityOracle");
    }

    /**
     * @dev Sets the minimum signaled tokens on a subgraph to start accruing rewards.
     * @dev Can be set to zero which means that this feature is not being used.
     * @param _minimumSubgraphSignal Minimum signaled tokens
     */
    function setMinimumSubgraphSignal(uint256 _minimumSubgraphSignal) external override {
        // Caller can be the SAO or the governor
        require(
            msg.sender == address(subgraphAvailabilityOracle) || msg.sender == controller.getGovernor(),
            "Not authorized"
        );
        minimumSubgraphSignal = _minimumSubgraphSignal;
        emit ParameterUpdated("minimumSubgraphSignal");
    }

    /**
     * @dev Sets the issuance allocator for this target.
     * @notice Implementation of the IIssuanceTarget interface function
     * @dev This function facilitates upgrades by providing a standard way for targets
     * to change their allocator. Only the governor can call this function.
     * @param _issuanceAllocator Address of the issuance allocator
     */
    function setIssuanceAllocator(address _issuanceAllocator) external override onlyGovernor {
        RewardsManagerData storage $ = _getRewardsManagerStorage();
        if ($.issuanceAllocator != _issuanceAllocator) {
            // Update rewards calculation before changing the issuance allocator
            updateAccRewardsPerSignal();

            address oldIssuanceAllocator = $.issuanceAllocator;
            $.issuanceAllocator = _issuanceAllocator;
            emit IssuanceAllocatorSet(oldIssuanceAllocator, _issuanceAllocator);
        }
    }

    /**
     * @notice Called by the IssuanceAllocator before this target's issuance allocation changes
     * @dev Ensures that all reward calculations are up-to-date with the current block
     * before any allocation changes take effect.
     *
     * This function is part of the IIssuanceTarget interface implemented by contracts that
     * receive issuance from the IssuanceAllocator. The IssuanceAllocator calls this function
     * before changing a target's allocation to ensure all issuance is properly accounted for
     * with the current issuance rate before applying an issuance allocation change.
     *
     * Only the IssuanceAllocator can call this function to ensure proper access control
     * for any future changes that might require this level of restriction.
     */
    function preIssuanceAllocationChange() external override {
        require(msg.sender == _getRewardsManagerStorage().issuanceAllocator, "Caller must be IssuanceAllocator");

        // Update rewards calculation with the current issuance rate
        updateAccRewardsPerSignal();
    }

    /**
     * @dev Sets the service quality oracle contract.
     * @param _serviceQualityOracle Address of the service quality oracle contract
     */
    function setServiceQualityOracle(address _serviceQualityOracle) external override onlyGovernor {
        RewardsManagerData storage $ = _getRewardsManagerStorage();
        if (address($.serviceQualityOracle) != _serviceQualityOracle) {
            address oldServiceQualityOracle = address($.serviceQualityOracle);
            $.serviceQualityOracle = IServiceQualityOracle(_serviceQualityOracle);
            emit ServiceQualityOracleSet(oldServiceQualityOracle, _serviceQualityOracle);
        }
    }

    // -- Denylist --

    /**
     * @dev Denies to claim rewards for a subgraph.
     * NOTE: Can only be called by the subgraph availability oracle
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny Whether to set the subgraph as denied for claiming rewards or not
     */
    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external override onlySubgraphAvailabilityOracle {
        _setDenied(_subgraphDeploymentID, _deny);
    }

    /**
     * @dev Internal: Denies to claim rewards for a subgraph.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny Whether to set the subgraph as denied for claiming rewards or not
     */
    function _setDenied(bytes32 _subgraphDeploymentID, bool _deny) private {
        uint256 sinceBlock = _deny ? block.number : 0;
        denylist[_subgraphDeploymentID] = sinceBlock;
        emit RewardsDenylistUpdated(_subgraphDeploymentID, sinceBlock);
    }

    /**
     * @dev Tells if subgraph is in deny list
     * @param _subgraphDeploymentID Subgraph deployment ID to check
     * @return Whether the subgraph is denied for claiming rewards or not
     */
    function isDenied(bytes32 _subgraphDeploymentID) public view override returns (bool) {
        return denylist[_subgraphDeploymentID] > 0;
    }

    // -- Getters --

    /**
     * @dev Gets the effective issuance per block, taking into account the IssuanceAllocator if set.
     * @return Effective issuance per block
     */
    function getRewardsIssuancePerBlock() public view override returns (uint256) {
        RewardsManagerData storage $ = _getRewardsManagerStorage();
        if ($.issuanceAllocator != address(0)) {
            return IIssuanceAllocator($.issuanceAllocator).getTargetIssuancePerBlock(address(this));
        }
        return issuancePerBlock;
    }

    /**
     * @dev Gets the issuance of rewards per signal since last updated.
     *
     * Linear formula: `x = r * t`
     *
     * Notation:
     * t: time steps are in blocks since last updated
     * x: newly accrued rewards tokens for the period `t`
     *
     * @return newly accrued rewards per signal since last update, scaled by FIXED_POINT_SCALING_FACTOR
     */
    function getNewRewardsPerSignal() public view override returns (uint256) {
        // Calculate time steps
        uint256 t = block.number.sub(accRewardsPerSignalLastBlockUpdated);
        // Optimization to skip calculations if zero time steps elapsed
        if (t == 0) {
            return 0;
        }

        uint256 rewardsIssuancePerBlock = getRewardsIssuancePerBlock();

        if (rewardsIssuancePerBlock == 0) {
            return 0;
        }

        // Zero issuance if no signalled tokens
        IGraphToken graphToken = graphToken();
        uint256 signalledTokens = graphToken.balanceOf(address(curation()));
        if (signalledTokens == 0) {
            return 0;
        }

        uint256 x = rewardsIssuancePerBlock.mul(t);

        // Get the new issuance per signalled token
        // We multiply the decimals to keep the precision as fixed-point number
        return x.mul(FIXED_POINT_SCALING_FACTOR).div(signalledTokens);
    }

    /**
     * @dev Gets the currently accumulated rewards per signal.
     * @return Currently accumulated rewards per signal
     */
    function getAccRewardsPerSignal() public view override returns (uint256) {
        return accRewardsPerSignal.add(getNewRewardsPerSignal());
    }

    /**
     * @dev Gets the accumulated rewards for the subgraph.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID) public view override returns (uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        // Get tokens signalled on the subgraph
        uint256 subgraphSignalledTokens = curation().getCurationPoolTokens(_subgraphDeploymentID);

        // Only accrue rewards if over a threshold
        uint256 newRewards = (subgraphSignalledTokens >= minimumSubgraphSignal) // Accrue new rewards since last snapshot
            ? getAccRewardsPerSignal().sub(subgraph.accRewardsPerSignalSnapshot).mul(subgraphSignalledTokens).div(
                FIXED_POINT_SCALING_FACTOR
            )
            : 0;
        return subgraph.accRewardsForSubgraph.add(newRewards);
    }

    /**
     * @dev Gets the accumulated rewards per allocated token for the subgraph.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for the subgraph
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsPerAllocatedToken(
        bytes32 _subgraphDeploymentID
    ) public view override returns (uint256, uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        uint256 newRewardsForSubgraph = MathUtils.diffOrZero(
            accRewardsForSubgraph,
            subgraph.accRewardsForSubgraphSnapshot
        );

        uint256 subgraphAllocatedTokens = staking().getSubgraphAllocatedTokens(_subgraphDeploymentID);
        if (subgraphAllocatedTokens == 0) {
            return (0, accRewardsForSubgraph);
        }

        uint256 newRewardsPerAllocatedToken = newRewardsForSubgraph.mul(FIXED_POINT_SCALING_FACTOR).div(
            subgraphAllocatedTokens
        );
        return (subgraph.accRewardsPerAllocatedToken.add(newRewardsPerAllocatedToken), accRewardsForSubgraph);
    }

    // -- Updates --

    /**
     * @dev Updates the accumulated rewards per signal and save checkpoint block number.
     * Must be called before `issuancePerBlock` or `total signalled GRT` changes
     * Called from the Curation contract on mint() and burn()
     * @return Accumulated rewards per signal
     */
    function updateAccRewardsPerSignal() public override returns (uint256) {
        accRewardsPerSignal = getAccRewardsPerSignal();
        accRewardsPerSignalLastBlockUpdated = block.number;
        return accRewardsPerSignal;
    }

    /**
     * @dev Triggers an update of rewards for a subgraph.
     * Must be called before `signalled GRT` on a subgraph changes.
     * Note: Hook called from the Curation contract on mint() and burn()
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID) external override returns (uint256) {
        // Called since `total signalled GRT` will change
        updateAccRewardsPerSignal();

        // Updates the accumulated rewards for a subgraph
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        subgraph.accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        subgraph.accRewardsPerSignalSnapshot = accRewardsPerSignal;
        return subgraph.accRewardsForSubgraph;
    }

    /**
     * @dev Triggers an update of rewards for a subgraph.
     * Must be called before allocation on a subgraph changes.
     * NOTE: Hook called from the Staking contract on allocate() and close()
     *
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for a subgraph
     */
    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) public override returns (uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        (uint256 accRewardsPerAllocatedToken, uint256 accRewardsForSubgraph) = getAccRewardsPerAllocatedToken(
            _subgraphDeploymentID
        );
        subgraph.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        subgraph.accRewardsForSubgraphSnapshot = accRewardsForSubgraph;
        return subgraph.accRewardsPerAllocatedToken;
    }

    /**
     * @dev Calculate current rewards for a given allocation on demand.
     * @param _allocationID Allocation
     * @return Rewards amount for an allocation
     */
    function getRewards(address _allocationID) external view override returns (uint256) {
        IStaking.AllocationState allocState = staking().getAllocationState(_allocationID);
        if (allocState != IStakingBase.AllocationState.Active) {
            return 0;
        }

        IStaking.Allocation memory alloc = staking().getAllocation(_allocationID);

        (uint256 accRewardsPerAllocatedToken, ) = getAccRewardsPerAllocatedToken(alloc.subgraphDeploymentID);
        return _calcRewards(alloc.tokens, alloc.accRewardsPerAllocatedToken, accRewardsPerAllocatedToken);
    }

    /**
     * @dev Calculate current rewards for a given allocation.
     * @param _tokens Tokens allocated
     * @param _startAccRewardsPerAllocatedToken Allocation start accumulated rewards
     * @param _endAccRewardsPerAllocatedToken Allocation end accumulated rewards
     * @return Rewards amount
     */
    function _calcRewards(
        uint256 _tokens,
        uint256 _startAccRewardsPerAllocatedToken,
        uint256 _endAccRewardsPerAllocatedToken
    ) private pure returns (uint256) {
        uint256 newAccrued = _endAccRewardsPerAllocatedToken.sub(_startAccRewardsPerAllocatedToken);
        return newAccrued.mul(_tokens).div(FIXED_POINT_SCALING_FACTOR);
    }

    /**
     * @dev Pull rewards from the contract for a particular allocation.
     * This function can only be called by the Staking contract.
     * This function will mint the necessary tokens to reward based on the inflation calculation.
     * @param _allocationID Allocation
     * @return Assigned rewards amount
     */
    function takeRewards(address _allocationID) external override returns (uint256) {
        // Only Staking contract is authorized as caller
        IStaking staking = staking();
        require(msg.sender == address(staking), "Caller must be the staking contract");

        IStaking.Allocation memory alloc = staking.getAllocation(_allocationID);
        uint256 accRewardsPerAllocatedToken = onSubgraphAllocationUpdate(alloc.subgraphDeploymentID);

        // Do not do rewards on denied subgraph deployments ID
        if (isDenied(alloc.subgraphDeploymentID)) {
            emit RewardsDenied(alloc.indexer, _allocationID, alloc.closedAtEpoch);
            return 0;
        }

        // Calculate rewards accrued by this allocation
        uint256 rewards = _calcRewards(alloc.tokens, alloc.accRewardsPerAllocatedToken, accRewardsPerAllocatedToken);

        // Do not reward if indexer is not eligible based on service quality
        RewardsManagerData storage $ = _getRewardsManagerStorage();
        if (address($.serviceQualityOracle) != address(0) && !$.serviceQualityOracle.meetsRequirements(alloc.indexer)) {
            emit RewardsDeniedDueToServiceQuality(alloc.indexer, _allocationID, rewards);
            return 0;
        }

        if (rewards > 0) {
            // Mint directly to staking contract for the reward amount
            // The staking contract will do bookkeeping of the reward and
            // assign in proportion to each stakeholder incentive
            graphToken().mint(address(staking), rewards);
        }

        emit RewardsAssigned(alloc.indexer, _allocationID, alloc.closedAtEpoch, rewards);

        return rewards;
    }
}
