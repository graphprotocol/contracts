// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../upgrades/GraphUpgradeable.sol";

import "./RewardsManagerStorage.sol";
import "./IRewardsManager.sol";

import "../reservoir/IReservoir.sol";

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
contract RewardsManager is RewardsManagerV4Storage, GraphUpgradeable, IRewardsManager {
    using SafeMath for uint256;

    uint256 private constant TOKEN_DECIMALS = 1e18;
    uint256 private constant MIN_ISSUANCE_RATE = 1e18;

    // -- Events --

    /**
     * @dev Emitted when rewards are assigned to an indexer.
     */
    event RewardsAssigned(
        address indexed indexer,
        address indexed allocationID,
        uint256 epoch,
        uint256 amount
    );

    /**
     * @dev Emitted when rewards are denied to an indexer (and therefore burned).
     */
    event RewardsDenied(
        address indexed indexer,
        address indexed allocationID,
        uint256 epoch,
        uint256 amount
    );

    /**
     * @dev Emitted when rewards for an indexer are burned .
     */
    event RewardsBurned(
        address indexed indexer,
        address indexed allocationID,
        uint256 epoch,
        uint256 amount
    );

    /**
     * @dev Emitted when a subgraph is denied for claiming rewards.
     */
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);

    // -- Modifiers --

    modifier onlySubgraphAvailabilityOracle() {
        require(
            msg.sender == address(subgraphAvailabilityOracle),
            "Caller must be the subgraph availability oracle"
        );
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
     * @dev Sets the subgraph oracle allowed to denegate distribution of rewards to subgraphs.
     * @param _subgraphAvailabilityOracle Address of the subgraph availability oracle
     */
    function setSubgraphAvailabilityOracle(address _subgraphAvailabilityOracle)
        external
        override
        onlyGovernor
    {
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
            msg.sender == address(subgraphAvailabilityOracle) ||
                msg.sender == controller.getGovernor(),
            "Not authorized"
        );
        minimumSubgraphSignal = _minimumSubgraphSignal;
        emit ParameterUpdated("minimumSubgraphSignal");
    }

    // -- Denylist --

    /**
     * @dev Denies to claim rewards for a subgraph.
     * NOTE: Can only be called by the subgraph availability oracle
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny Whether to set the subgraph as denied for claiming rewards or not
     */
    function setDenied(bytes32 _subgraphDeploymentID, bool _deny)
        external
        override
        onlySubgraphAvailabilityOracle
    {
        _setDenied(_subgraphDeploymentID, _deny);
    }

    /**
     * @dev Denies to claim rewards for multiple subgraph.
     * NOTE: Can only be called by the subgraph availability oracle
     * @param _subgraphDeploymentID Array of subgraph deployment ID
     * @param _deny Array of denied status for claiming rewards for each subgraph
     */
    function setDeniedMany(bytes32[] calldata _subgraphDeploymentID, bool[] calldata _deny)
        external
        override
        onlySubgraphAvailabilityOracle
    {
        require(_subgraphDeploymentID.length == _deny.length, "!length");
        for (uint256 i = 0; i < _subgraphDeploymentID.length; i++) {
            _setDenied(_subgraphDeploymentID[i], _deny[i]);
        }
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
     * @dev Gets the issuance of rewards per signal since last updated.
     *
     * The compound interest formula is applied in the Reservoir contract.
     * This function will compare accumulated rewards at the current block
     * with the value that was cached at accRewardsPerSignalLastBlockUpdated.
     *
     * @return newly accrued rewards per signal since last update
     */
    function getNewRewardsPerSignal() public view override returns (uint256) {
        // Zero issuance if no signalled tokens
        IGraphToken graphToken = graphToken();
        uint256 signalledTokens = graphToken.balanceOf(address(curation()));
        if (signalledTokens == 0) {
            return 0;
        }

        uint256 accRewardsNow = reservoir().getAccumulatedRewards(block.number);

        // Get the new issuance per signalled token
        // We multiply the decimals to keep the precision as fixed-point number
        return
            (accRewardsNow.sub(accRewardsOnLastSignalUpdate)).mul(TOKEN_DECIMALS).div(
                signalledTokens
            );
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
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID)
        public
        view
        override
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        // Get tokens signalled on the subgraph
        uint256 subgraphSignalledTokens = curation().getCurationPoolTokens(_subgraphDeploymentID);

        // Only accrue rewards if over a threshold
        uint256 newRewards = (subgraphSignalledTokens >= minimumSubgraphSignal) // Accrue new rewards since last snapshot
            ? getAccRewardsPerSignal()
                .sub(subgraph.accRewardsPerSignalSnapshot)
                .mul(subgraphSignalledTokens)
                .div(TOKEN_DECIMALS)
            : 0;
        return subgraph.accRewardsForSubgraph.add(newRewards);
    }

    /**
     * @dev Gets the accumulated rewards per allocated token for the subgraph.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for the subgraph
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsPerAllocatedToken(bytes32 _subgraphDeploymentID)
        public
        view
        override
        returns (uint256, uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        uint256 newRewardsForSubgraph = accRewardsForSubgraph.sub(
            subgraph.accRewardsForSubgraphSnapshot
        );

        uint256 subgraphAllocatedTokens = staking().getSubgraphAllocatedTokens(
            _subgraphDeploymentID
        );
        if (subgraphAllocatedTokens == 0) {
            return (0, accRewardsForSubgraph);
        }

        uint256 newRewardsPerAllocatedToken = newRewardsForSubgraph.mul(TOKEN_DECIMALS).div(
            subgraphAllocatedTokens
        );
        return (
            subgraph.accRewardsPerAllocatedToken.add(newRewardsPerAllocatedToken),
            accRewardsForSubgraph
        );
    }

    // -- Updates --

    /**
     * @dev Updates the accumulated rewards per signal and save checkpoint block number.
     * Must be called before `issuanceRate` or `total signalled GRT` changes
     * Called from the Curation contract on mint() and burn()
     * @return Accumulated rewards per signal
     */
    function updateAccRewardsPerSignal() public override returns (uint256) {
        accRewardsPerSignal = getAccRewardsPerSignal();
        accRewardsPerSignalLastBlockUpdated = block.number;
        accRewardsOnLastSignalUpdate = reservoir().getAccumulatedRewards(block.number);
        return accRewardsPerSignal;
    }

    /**
     * @dev Triggers an update of rewards for a subgraph.
     * Must be called before `signalled GRT` on a subgraph changes.
     * Note: Hook called from the Curation contract on mint() and burn()
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID)
        external
        override
        returns (uint256)
    {
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
    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID)
        public
        override
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        (
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsForSubgraph
        ) = getAccRewardsPerAllocatedToken(_subgraphDeploymentID);
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
        IStaking.Allocation memory alloc = staking().getAllocation(_allocationID);

        (uint256 accRewardsPerAllocatedToken, ) = getAccRewardsPerAllocatedToken(
            alloc.subgraphDeploymentID
        );
        return
            _calcRewards(
                alloc.tokens,
                alloc.accRewardsPerAllocatedToken,
                accRewardsPerAllocatedToken
            );
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
        return newAccrued.mul(_tokens).div(TOKEN_DECIMALS);
    }

    /**
     * @dev Pull rewards from the contract for a particular allocation.
     * This function can only be called by the Staking contract.
     * This function will transfer the necessary tokens to reward based on the inflation calculation.
     * @param _allocationID Allocation
     * @return Assigned rewards amount
     */
    function takeRewards(address _allocationID) external override returns (uint256) {
        // Only Staking contract is authorized as caller
        IStaking staking = staking();
        require(msg.sender == address(staking), "Caller must be the staking contract");

        IStaking.Allocation memory alloc = staking.getAllocation(_allocationID);
        uint256 accRewardsPerAllocatedToken = onSubgraphAllocationUpdate(
            alloc.subgraphDeploymentID
        );

        // Calculate rewards accrued by this allocation
        uint256 rewards = _calcRewards(
            alloc.tokens,
            alloc.accRewardsPerAllocatedToken,
            accRewardsPerAllocatedToken
        );
        if (!isDenied(alloc.subgraphDeploymentID)) {
            // Transfer to staking contract for the reward amount
            // The staking contract will do bookkeeping of the reward and
            // assign in proportion to each stakeholder incentive
            if (rewards > 0) {
                graphToken().transferFrom(address(reservoir()), address(staking), rewards);
            }
            emit RewardsAssigned(alloc.indexer, _allocationID, alloc.closedAtEpoch, rewards);
        } else {
            if (rewards > 0) {
                graphToken().burnFrom(address(reservoir()), rewards);
            }
            emit RewardsDenied(alloc.indexer, _allocationID, alloc.closedAtEpoch, rewards);
            return 0;
        }

        return rewards;
    }

    /**
     * @dev Burn rewards for a particular allocation.
     * This function can only be called by the Staking contract.
     * This function will burn the necessary tokens to reward based on the inflation calculation.
     * @param _allocationID Allocation
     */
    function takeAndBurnRewards(address _allocationID) external override {
        // Only Staking contract is authorized as caller
        IStaking staking = staking();
        require(msg.sender == address(staking), "Caller must be the staking contract");

        IStaking.Allocation memory alloc = staking.getAllocation(_allocationID);
        uint256 accRewardsPerAllocatedToken = onSubgraphAllocationUpdate(
            alloc.subgraphDeploymentID
        );

        // Calculate rewards accrued by this allocation
        uint256 rewards = _calcRewards(
            alloc.tokens,
            alloc.accRewardsPerAllocatedToken,
            accRewardsPerAllocatedToken
        );
        if (rewards > 0) {
            graphToken().burnFrom(address(reservoir()), rewards);
            emit RewardsBurned(alloc.indexer, _allocationID, alloc.closedAtEpoch, rewards);
        }
    }

    function reservoir() internal view returns (IReservoir) {
        return IReservoir(_resolveContract(keccak256("Reservoir")));
    }
}
