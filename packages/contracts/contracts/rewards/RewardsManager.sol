// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one, gas-indexed-events, gas-small-strings, gas-strict-inequalities

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { Managed } from "../governance/Managed.sol";
import { MathUtils } from "../staking/libs/MathUtils.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";

import { RewardsManagerV5Storage } from "./RewardsManagerStorage.sol";
import { IRewardsIssuer } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";

/**
 * @title Rewards Manager Contract
 * @author Edge & Node
 * @notice Manages rewards distribution for indexers and delegators in the Graph Protocol
 * @dev Tracks how inflationary GRT rewards should be handed out. Signaled GRT in Curation determine
 * what percentage of the tokens go towards each subgraph. Then each Subgraph can have multiple
 * Indexers Staked on it. Thus, the total rewards for the Subgraph are split up for each Indexer based
 * on much they have Staked on that Subgraph.
 *
 * Note:
 * The contract provides getter functions to query the state of accrued rewards:
 * - getAccRewardsPerSignal
 * - getAccRewardsForSubgraph
 * - getAccRewardsPerAllocatedToken
 * - getRewards
 * These functions may overestimate the actual rewards due to changes in the total supply
 * until the actual takeRewards function is called.
 * custom:security-contact Please email security+contracts@ thegraph.com (remove space) if you find any bugs. We might have an active bug bounty program.
 */
contract RewardsManager is RewardsManagerV5Storage, GraphUpgradeable, IRewardsManager {
    using SafeMath for uint256;

    /// @dev Fixed point scaling factor used for decimals in reward calculations
    uint256 private constant FIXED_POINT_SCALING_FACTOR = 1e18;

    // -- Events --

    /**
     * @notice Emitted when rewards are assigned to an indexer.
     * @dev We use the Horizon prefix to change the event signature which makes network subgraph development much easier
     * @param indexer Address of the indexer receiving rewards
     * @param allocationID Address of the allocation receiving rewards
     * @param amount Amount of rewards assigned
     */
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);

    /**
     * @notice Emitted when rewards are denied to an indexer
     * @param indexer Address of the indexer being denied rewards
     * @param allocationID Address of the allocation being denied rewards
     */
    event RewardsDenied(address indexed indexer, address indexed allocationID);

    /**
     * @notice Emitted when a subgraph is denied for claiming rewards
     * @param subgraphDeploymentID Subgraph deployment ID being denied
     * @param sinceBlock Block number since when the subgraph is denied
     */
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);

    /**
     * @notice Emitted when the subgraph service is set
     * @param oldSubgraphService Previous subgraph service address
     * @param newSubgraphService New subgraph service address
     */
    event SubgraphServiceSet(address indexed oldSubgraphService, address indexed newSubgraphService);

    // -- Modifiers --

    /**
     * @dev Modifier to restrict access to the subgraph availability oracle only
     */
    modifier onlySubgraphAvailabilityOracle() {
        require(msg.sender == address(subgraphAvailabilityOracle), "Caller must be the subgraph availability oracle");
        _;
    }

    /**
     * @notice Initialize this contract
     * @param _controller Address of the controller contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    // -- Config --

    /**
     * @inheritdoc IRewardsManager
     *
     * @dev The issuance is defined as a fixed amount of rewards per block in GRT.
     * Whenever this function is called in layer 2, the updateL2MintAllowance function
     * _must_ be called on the L1GraphTokenGateway in L1, to ensure the bridge can mint the
     * right amount of tokens.
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external override onlyGovernor {
        _setIssuancePerBlock(_issuancePerBlock);
    }

    /**
     * @notice Sets the GRT issuance per block.
     * @dev The issuance is defined as a fixed amount of rewards per block in GRT.
     * @param _issuancePerBlock Issuance expressed in GRT per block (scaled by 1e18)
     */
    function _setIssuancePerBlock(uint256 _issuancePerBlock) private {
        // Called since `issuance per block` will change
        updateAccRewardsPerSignal();

        issuancePerBlock = _issuancePerBlock;
        emit ParameterUpdated("issuancePerBlock");
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function setSubgraphAvailabilityOracle(address _subgraphAvailabilityOracle) external override onlyGovernor {
        subgraphAvailabilityOracle = _subgraphAvailabilityOracle;
        emit ParameterUpdated("subgraphAvailabilityOracle");
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Can be set to zero which means that this feature is not being used
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
     * @inheritdoc IRewardsManager
     */
    function setSubgraphService(address _subgraphService) external override onlyGovernor {
        address oldSubgraphService = address(subgraphService);
        subgraphService = IRewardsIssuer(_subgraphService);
        emit SubgraphServiceSet(oldSubgraphService, _subgraphService);
    }

    // -- Denylist --

    /**
     * @inheritdoc IRewardsManager
     * @dev Can only be called by the subgraph availability oracle
     */
    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external override onlySubgraphAvailabilityOracle {
        _setDenied(_subgraphDeploymentID, _deny);
    }

    /**
     * @notice Internal: Denies to claim rewards for a subgraph.
     * @param _subgraphDeploymentID Subgraph deployment ID
     * @param _deny Whether to set the subgraph as denied for claiming rewards or not
     */
    function _setDenied(bytes32 _subgraphDeploymentID, bool _deny) private {
        uint256 sinceBlock = _deny ? block.number : 0;
        denylist[_subgraphDeploymentID] = sinceBlock;
        emit RewardsDenylistUpdated(_subgraphDeploymentID, sinceBlock);
    }

    /// @inheritdoc IRewardsManager
    function isDenied(bytes32 _subgraphDeploymentID) public view override returns (bool) {
        return denylist[_subgraphDeploymentID] > 0;
    }

    // -- Getters --

    /**
     * @inheritdoc IRewardsManager
     * @dev Linear formula: `x = r * t`
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
        // ...or if issuance is zero
        if (issuancePerBlock == 0) {
            return 0;
        }

        // Zero issuance if no signalled tokens
        IGraphToken graphToken = graphToken();
        uint256 signalledTokens = graphToken.balanceOf(address(curation()));
        if (signalledTokens == 0) {
            return 0;
        }

        uint256 x = issuancePerBlock.mul(t);

        // Get the new issuance per signalled token
        // We multiply the decimals to keep the precision as fixed-point number
        return x.mul(FIXED_POINT_SCALING_FACTOR).div(signalledTokens);
    }

    /// @inheritdoc IRewardsManager
    function getAccRewardsPerSignal() public view override returns (uint256) {
        return accRewardsPerSignal.add(getNewRewardsPerSignal());
    }

    /// @inheritdoc IRewardsManager
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

    /// @inheritdoc IRewardsManager
    function getAccRewardsPerAllocatedToken(
        bytes32 _subgraphDeploymentID
    ) public view override returns (uint256, uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        uint256 newRewardsForSubgraph = MathUtils.diffOrZero(
            accRewardsForSubgraph,
            subgraph.accRewardsForSubgraphSnapshot
        );

        uint256 subgraphAllocatedTokens = 0;
        address rewardsIssuer = address(subgraphService);
        if (rewardsIssuer != address(0)) {
            subgraphAllocatedTokens += IRewardsIssuer(rewardsIssuer).getSubgraphAllocatedTokens(_subgraphDeploymentID);
        }

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
     * @inheritdoc IRewardsManager
     * @dev Must be called before `issuancePerBlock` or `total signalled GRT` changes.
     * Called from the Curation contract on mint() and burn()
     */
    function updateAccRewardsPerSignal() public override returns (uint256) {
        accRewardsPerSignal = getAccRewardsPerSignal();
        accRewardsPerSignalLastBlockUpdated = block.number;
        return accRewardsPerSignal;
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Must be called before `signalled GRT` on a subgraph changes.
     * Hook called from the Curation contract on mint() and burn()
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
     * @inheritdoc IRewardsManager
     * @dev Hook called from the IRewardsIssuer contract on allocate() and close()
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

    /// @inheritdoc IRewardsManager
    function getRewards(address _rewardsIssuer, address _allocationID) external view override returns (uint256) {
        require(_rewardsIssuer == address(subgraphService), "Not a rewards issuer");

        (
            bool isActive,
            ,
            bytes32 subgraphDeploymentId,
            uint256 tokens,
            uint256 alloAccRewardsPerAllocatedToken,
            uint256 accRewardsPending
        ) = IRewardsIssuer(_rewardsIssuer).getAllocationData(_allocationID);

        if (!isActive) {
            return 0;
        }

        (uint256 accRewardsPerAllocatedToken, ) = getAccRewardsPerAllocatedToken(subgraphDeploymentId);
        return
            accRewardsPending.add(_calcRewards(tokens, alloAccRewardsPerAllocatedToken, accRewardsPerAllocatedToken));
    }

    /**
     * @notice Calculate rewards for a given accumulated rewards per allocated token
     * @param _tokens Tokens allocated
     * @param _accRewardsPerAllocatedToken Allocation accumulated rewards per token
     * @return Rewards amount
     */
    function calcRewards(
        uint256 _tokens,
        uint256 _accRewardsPerAllocatedToken
    ) external pure override returns (uint256) {
        return _accRewardsPerAllocatedToken.mul(_tokens).div(FIXED_POINT_SCALING_FACTOR);
    }

    /**
     * @notice Calculate current rewards for a given allocation.
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
     * @inheritdoc IRewardsManager
     * @dev This function can only be called by an authorized rewards issuer which are
     * - the subgraph service (for new allocations).
     * Mints 0 tokens if the allocation is not active.
     */
    function takeRewards(address _allocationID) external override returns (uint256) {
        address rewardsIssuer = msg.sender;
        require(rewardsIssuer == address(subgraphService), "Caller must be a rewards issuer");

        (
            bool isActive,
            address indexer,
            bytes32 subgraphDeploymentID,
            uint256 tokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        ) = IRewardsIssuer(rewardsIssuer).getAllocationData(_allocationID);

        uint256 updatedAccRewardsPerAllocatedToken = onSubgraphAllocationUpdate(subgraphDeploymentID);

        // Do not do rewards on denied subgraph deployments ID
        if (isDenied(subgraphDeploymentID)) {
            emit RewardsDenied(indexer, _allocationID);
            return 0;
        }

        uint256 rewards = 0;
        if (isActive) {
            // Calculate rewards accrued by this allocation
            rewards = accRewardsPending.add(
                _calcRewards(tokens, accRewardsPerAllocatedToken, updatedAccRewardsPerAllocatedToken)
            );
            if (rewards > 0) {
                // Mint directly to rewards issuer for the reward amount
                // The rewards issuer contract will do bookkeeping of the reward and
                // assign in proportion to each stakeholder incentive
                graphToken().mint(rewardsIssuer, rewards);
            }
        }

        emit HorizonRewardsAssigned(indexer, _allocationID, rewards);

        return rewards;
    }
}
