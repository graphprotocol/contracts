// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC165 } from "@openzeppelin/contracts/introspection/IERC165.sol";

import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { Managed } from "../governance/Managed.sol";
import { MathUtils } from "../staking/libs/MathUtils.sol";

import { RewardsManagerV6Storage } from "./RewardsManagerStorage.sol";
import { IRewardsIssuer } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IRewardsManagerDeprecated } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManagerDeprecated.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";

/**
 * @title Rewards Manager Contract
 * @author Edge & Node
 * @notice Manages rewards distribution for indexers and delegators in the Graph Protocol
 *
 * @dev ## Token Accounting Model
 *
 * Rewards use a two-level accumulation model with snapshot-based safety:
 *
 * **Level 1 - Signal Distribution (cross-subgraph):**
 * - `accRewardsPerSignal` accumulates rewards per signaled token globally
 * - Each subgraph gets rewards proportional to its curation signal
 * - `accRewardsForSubgraph` tracks total rewards allocated to each subgraph
 *
 * **Level 2 - Allocation Distribution (within-subgraph):**
 * - `accRewardsPerAllocatedToken` scales subgraph rewards to indexer allocations
 * - Each allocation tracks its starting snapshot to calculate its share
 *
 * Accumulation invariants:
 * - Snapshots prevent double-counting: each allocation's reward = (current - snapshot) × tokens
 * - Accumulator values never decrease
 * - Tokens are minted at claim time
 *
 * @dev If an `issuanceAllocator` is set, it determines GRT issued per block.
 * Otherwise, the `issuancePerBlock` storage value is used. This contract
 * is a self-minting target responsible for directly minting allocated GRT.
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
contract RewardsManager is
    GraphUpgradeable,
    IERC165,
    IRewardsManager,
    IIssuanceTarget,
    IRewardsManagerDeprecated,
    RewardsManagerV6Storage
{
    using SafeMath for uint256;

    /// @dev Fixed point scaling factor used for decimals in reward calculations
    uint256 private constant FIXED_POINT_SCALING_FACTOR = 1e18;

    // -- Modifiers --

    /**
     * @dev Modifier to restrict access to the subgraph availability oracle only
     */
    modifier onlySubgraphAvailabilityOracle() {
        // solhint-disable-next-line gas-small-strings
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

    /**
     * @inheritdoc IERC165
     * @dev Implements ERC165 interface detection
     * Returns true if this contract implements the interface defined by interfaceId.
     * See: https://eips.ethereum.org/EIPS/eip-165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IIssuanceTarget).interfaceId ||
            interfaceId == type(IRewardsManager).interfaceId;
    }

    // -- Config --

    /**
     * @inheritdoc IRewardsManagerDeprecated
     * @dev When an IssuanceAllocator is set, the effective issuance will be determined by the allocator,
     * but this local value can still be updated for cases when the allocator is later removed.
     *
     * The issuance is defined as a fixed amount of rewards per block in GRT.
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

    /**
     * @inheritdoc IIssuanceTarget
     * @dev This function facilitates upgrades by providing a standard way for targets
     * to change their allocator. Only the governor can call this function.
     * Note that the IssuanceAllocator can be set to the zero address to disable use of an allocator, and
     * use the local `issuancePerBlock` variable instead to control issuance.
     */
    function setIssuanceAllocator(address newIssuanceAllocator) external override onlyGovernor {
        if (address(issuanceAllocator) != newIssuanceAllocator) {
            // Update rewards calculation before changing the issuance allocator
            updateAccRewardsPerSignal();

            // Check that the contract supports the IIssuanceAllocationDistribution interface
            // Allow zero address to disable the allocator
            if (newIssuanceAllocator != address(0)) {
                // solhint-disable-next-line gas-small-strings
                require(
                    IERC165(newIssuanceAllocator).supportsInterface(type(IIssuanceAllocationDistribution).interfaceId),
                    "Contract does not support IIssuanceAllocationDistribution interface"
                );
            }

            address oldIssuanceAllocator = address(issuanceAllocator);
            issuanceAllocator = IIssuanceAllocationDistribution(newIssuanceAllocator);
            emit IssuanceAllocatorSet(oldIssuanceAllocator, newIssuanceAllocator);
        }
    }

    /**
     * @inheritdoc IIssuanceTarget
     * @dev Ensures that all reward calculations are up-to-date with the current block
     * before any allocation changes take effect.
     *
     * This function can be called by anyone to update the rewards calculation state.
     * The IssuanceAllocator calls this function before changing a target's allocation to ensure
     * all issuance is properly accounted for with the current issuance rate before applying an
     * issuance allocation change.
     */
    function beforeIssuanceAllocationChange() external override {
        // Update rewards calculation with the current issuance rate
        updateAccRewardsPerSignal();
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Note that the rewards eligibility oracle can be set to the zero address to disable use of an oracle, in
     * which case no indexers will be denied rewards due to eligibility.
     */
    function setRewardsEligibilityOracle(address newRewardsEligibilityOracle) external override onlyGovernor {
        if (address(rewardsEligibilityOracle) != newRewardsEligibilityOracle) {
            // Check that the contract supports the IRewardsEligibility interface
            // Allow zero address to disable the oracle
            if (newRewardsEligibilityOracle != address(0)) {
                // solhint-disable-next-line gas-small-strings
                require(
                    IERC165(newRewardsEligibilityOracle).supportsInterface(type(IRewardsEligibility).interfaceId),
                    "Contract does not support IRewardsEligibility interface"
                );
            }

            address oldRewardsEligibilityOracle = address(rewardsEligibilityOracle);
            rewardsEligibilityOracle = IRewardsEligibility(newRewardsEligibilityOracle);
            emit RewardsEligibilityOracleSet(oldRewardsEligibilityOracle, newRewardsEligibilityOracle);
        }
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev bytes32(0) is reserved as an invalid reason to prevent accidental misconfiguration
     * and catch uninitialized reason identifiers.
     *
     * IMPORTANT: Changes take effect immediately and retroactively. All unclaimed rewards from
     * previous periods will be sent to the new reclaim address when they are eventually reclaimed,
     * regardless of which address was configured when the rewards were originally accrued.
     */
    function setReclaimAddress(bytes32 reason, address newAddress) external override onlyGovernor {
        // solhint-disable-next-line gas-small-strings
        require(reason != bytes32(0), "Cannot set reclaim address for (bytes32(0))");

        address oldAddress = reclaimAddresses[reason];

        if (oldAddress != newAddress) {
            reclaimAddresses[reason] = newAddress;
            emit ReclaimAddressSet(reason, oldAddress, newAddress);
        }
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function setDefaultReclaimAddress(address newAddress) external override onlyGovernor {
        address oldAddress = defaultReclaimAddress;

        if (oldAddress != newAddress) {
            defaultReclaimAddress = newAddress;
            emit DefaultReclaimAddressSet(oldAddress, newAddress);
        }
    }

    // -- Denylist --

    /**
     * @inheritdoc IRewardsManager
     * @dev Can only be called by the subgraph availability oracle
     */
    function setDenied(bytes32 subgraphDeploymentId, bool deny) external override onlySubgraphAvailabilityOracle {
        _setDenied(subgraphDeploymentId, deny);
    }

    /**
     * @notice Internal: Denies to claim rewards for a subgraph.
     * @dev Idempotent: redundant calls (deny when already denied, undeny when already allowed)
     * skip the denylist update and event emission (but still call `onSubgraphAllocationUpdate`).
     * This preserves the original deny block number on repeated deny calls.
     * @param subgraphDeploymentId Subgraph deployment ID
     * @param deny Whether to set the subgraph as denied for claiming rewards or not
     */
    function _setDenied(bytes32 subgraphDeploymentId, bool deny) private {
        onSubgraphAllocationUpdate(subgraphDeploymentId);

        bool stateChange = deny == (denylist[subgraphDeploymentId] == 0);
        if (stateChange) {
            uint256 sinceBlock = deny ? block.number : 0;
            denylist[subgraphDeploymentId] = sinceBlock;
            emit RewardsDenylistUpdated(subgraphDeploymentId, sinceBlock);
        }
    }

    /// @inheritdoc IRewardsManager
    function isDenied(bytes32 _subgraphDeploymentID) public view override returns (bool) {
        return denylist[_subgraphDeploymentID] > 0;
    }

    // -- Getters --

    /**
     * @inheritdoc IRewardsManager
     */
    function getAllocatedIssuancePerBlock() public view override returns (uint256) {
        return
            address(issuanceAllocator) != address(0)
                ? issuanceAllocator.getTargetIssuancePerBlock(address(this)).selfIssuanceRate
                : issuancePerBlock;
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function getRawIssuancePerBlock() external view override returns (uint256) {
        return issuancePerBlock;
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function getIssuanceAllocator() external view override returns (IIssuanceAllocationDistribution) {
        return issuanceAllocator;
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function getReclaimAddress(bytes32 reason) external view override returns (address) {
        return reclaimAddresses[reason];
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function getDefaultReclaimAddress() external view override returns (address) {
        return defaultReclaimAddress;
    }

    /**
     * @inheritdoc IRewardsManager
     */
    function getRewardsEligibilityOracle() external view override returns (IRewardsEligibility) {
        return rewardsEligibilityOracle;
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Linear formula: `x = r * t`
     *
     * Notation:
     * t: time steps are in blocks since last updated
     * x: newly accrued rewards tokens for the period `t`
     *
     * @return claimablePerSignal accrued rewards per signal since last update, scaled by FIXED_POINT_SCALING_FACTOR
     */
    function getNewRewardsPerSignal() public view override returns (uint256 claimablePerSignal) {
        (claimablePerSignal, ) = _getNewRewardsPerSignal();
    }

    /**
     * @notice Calculate new rewards per signal, split into claimable and unclaimable portions
     * @dev Linear formula: `x = r * t`
     *
     * Notation:
     * t: time steps are in blocks since last updated
     * x: newly accrued rewards tokens for the period `t`
     *
     * @return claimablePerSignal Rewards per signal when signal exists, scaled by FIXED_POINT_SCALING_FACTOR
     * @return unclaimableTokens Raw token amount that cannot be distributed due to zero signal
     */
    function _getNewRewardsPerSignal() private view returns (uint256 claimablePerSignal, uint256 unclaimableTokens) {
        // Calculate time steps
        uint256 t = block.number.sub(accRewardsPerSignalLastBlockUpdated);
        // Optimization to skip calculations if zero time steps elapsed
        if (t == 0) return (0, 0);

        uint256 rewardsIssuancePerBlock = getAllocatedIssuancePerBlock();

        if (rewardsIssuancePerBlock == 0) return (0, 0);

        uint256 x = rewardsIssuancePerBlock.mul(t);

        // Check signalled tokens
        uint256 signalledTokens = graphToken().balanceOf(address(curation()));
        if (signalledTokens == 0) return (0, x); // All unclaimable when no signal

        // Get the new issuance per signalled token
        // We multiply the decimals to keep the precision as fixed-point number
        return (x.mul(FIXED_POINT_SCALING_FACTOR).div(signalledTokens), 0);
    }

    /// @inheritdoc IRewardsManager
    function getAccRewardsPerSignal() public view override returns (uint256) {
        return accRewardsPerSignal.add(getNewRewardsPerSignal());
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Returns accumulated rewards for external callers.
     * New rewards are only included if the subgraph is claimable (neither denied nor below minimum signal).
     * Reclaim for non-claimable subgraphs is handled in `onSubgraphAllocationUpdate()`.
     */
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID) public view override returns (uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        (uint256 newRewards, , bytes32 condition) = _getSubgraphRewardsState(_subgraphDeploymentID);
        return subgraph.accRewardsForSubgraph.add(condition == RewardsCondition.NONE ? newRewards : 0);
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

        // There are two contributors to subgraph allocated tokens:
        // - the legacy allocations on the legacy staking contract
        // - the new allocations on the subgraph service
        uint256 subgraphAllocatedTokens = 0;
        address[2] memory rewardsIssuers = [address(staking()), address(subgraphService)];
        for (uint256 i = 0; i < rewardsIssuers.length; ++i) {
            if (rewardsIssuers[i] != address(0)) {
                subgraphAllocatedTokens += IRewardsIssuer(rewardsIssuers[i]).getSubgraphAllocatedTokens(
                    _subgraphDeploymentID
                );
            }
        }

        if (subgraphAllocatedTokens == 0) {
            return (0, accRewardsForSubgraph);
        }

        uint256 newRewardsPerAllocatedToken = newRewardsForSubgraph.mul(FIXED_POINT_SCALING_FACTOR).div(
            subgraphAllocatedTokens
        );
        return (subgraph.accRewardsPerAllocatedToken.add(newRewardsPerAllocatedToken), accRewardsForSubgraph);
    }

    // -- Internal Helpers --

    /**
     * @notice Calculate new rewards and claimability state for a subgraph
     * @dev Returns the new rewards based on signal and the condition indicating why rewards
     * may not be claimable (SUBGRAPH_DENIED, BELOW_MINIMUM_SIGNAL, or NONE if claimable).
     * @param _subgraphDeploymentID Subgraph deployment
     * @return newRewards The rewards that would accrue based on signal (may not be claimable)
     * @return signalledTokens The subgraph's current signal
     * @return condition The condition: NONE if claimable, otherwise the denial reason
     */
    function _getSubgraphRewardsState(
        bytes32 _subgraphDeploymentID
    ) private view returns (uint256 newRewards, uint256 signalledTokens, bytes32 condition) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        signalledTokens = curation().getCurationPoolTokens(_subgraphDeploymentID);
        uint256 accRewardsPerSignalDelta = getAccRewardsPerSignal().sub(subgraph.accRewardsPerSignalSnapshot);
        newRewards = accRewardsPerSignalDelta.mul(signalledTokens).div(FIXED_POINT_SCALING_FACTOR);

        if (isDenied(_subgraphDeploymentID)) {
            condition = RewardsCondition.SUBGRAPH_DENIED;
        } else if (signalledTokens < minimumSubgraphSignal) {
            condition = RewardsCondition.BELOW_MINIMUM_SIGNAL;
        } else {
            condition = RewardsCondition.NONE;
        }
    }

    /**
     * @notice Get total allocated tokens for a subgraph across all issuers
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Total tokens allocated to this subgraph
     */
    function _getSubgraphAllocatedTokens(bytes32 _subgraphDeploymentID) private view returns (uint256) {
        uint256 subgraphAllocatedTokens = 0;
        address[2] memory rewardsIssuers = [address(staking()), address(subgraphService)];
        for (uint256 i = 0; i < rewardsIssuers.length; ++i) {
            if (rewardsIssuers[i] != address(0)) {
                subgraphAllocatedTokens += IRewardsIssuer(rewardsIssuers[i]).getSubgraphAllocatedTokens(
                    _subgraphDeploymentID
                );
            }
        }
        return subgraphAllocatedTokens;
    }

    // -- Updates --

    /**
     * @inheritdoc IRewardsManager
     * @dev Must be called before `issuancePerBlock` or `total signalled GRT` changes.
     * Called from the Curation contract on mint() and burn()
     *
     * ## Zero Signal Handling
     *
     * When total signalled tokens is zero, issuance for the period is reclaimed
     * (if NO_SIGNAL reclaim address is configured) rather than being lost.
     */
    function updateAccRewardsPerSignal() public override returns (uint256) {
        (uint256 claimablePerSignal, uint256 unclaimableTokens) = _getNewRewardsPerSignal();
        if (claimablePerSignal == 0 && unclaimableTokens == 0) return accRewardsPerSignal;

        if (0 < unclaimableTokens)
            _reclaimRewards(RewardsCondition.NO_SIGNAL, unclaimableTokens, address(0), address(0), bytes32(0));

        accRewardsPerSignal = accRewardsPerSignal.add(claimablePerSignal);
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
     * @dev Hook called from the Staking contract on allocate() and close()
     *
     * ## Claimability Behavior
     *
     * When a subgraph is not claimable (denied or below minimum signal):
     * - `accRewardsPerAllocatedToken` is NOT updated (frozen)
     * - New rewards are reclaimed with the appropriate reason (SUBGRAPH_DENIED or BELOW_MINIMUM_SIGNAL)
     * - `accRewardsPerSignalSnapshot` is updated to prevent double-reclaim
     *
     * When claimable:
     * - `accRewardsForSubgraph` and `accRewardsPerAllocatedToken` are updated normally
     * - Allocations can claim their proportional share
     *
     * @return accRewardsPerAllocatedToken Current `accRewardsPerAllocatedToken` (frozen while subgraph is not claimable)
     */
    function onSubgraphAllocationUpdate(
        bytes32 _subgraphDeploymentID
    ) public override returns (uint256 accRewardsPerAllocatedToken) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        (uint256 newRewards, uint256 signalledTokens, bytes32 condition) = _getSubgraphRewardsState(
            _subgraphDeploymentID
        );
        subgraph.accRewardsPerSignalSnapshot = getAccRewardsPerSignal();
        accRewardsPerAllocatedToken = subgraph.accRewardsPerAllocatedToken;
        if (newRewards == 0) return accRewardsPerAllocatedToken;

        // Fallback: if denied but no reclaim address, try BELOW_MINIMUM_SIGNAL instead
        if (
            condition == RewardsCondition.SUBGRAPH_DENIED &&
            reclaimAddresses[condition] == address(0) &&
            signalledTokens < minimumSubgraphSignal
        ) {
            condition = RewardsCondition.BELOW_MINIMUM_SIGNAL;
        }

        if (condition != RewardsCondition.NONE) {
            _reclaimRewards(condition, newRewards, address(0), address(0), _subgraphDeploymentID);
            return accRewardsPerAllocatedToken;
        }

        uint256 subgraphAllocatedTokens = _getSubgraphAllocatedTokens(_subgraphDeploymentID);
        if (subgraphAllocatedTokens == 0) {
            _reclaimRewards(RewardsCondition.NO_ALLOCATION, newRewards, address(0), address(0), _subgraphDeploymentID);
            return accRewardsPerAllocatedToken;
        }

        subgraph.accRewardsForSubgraph = subgraph.accRewardsForSubgraph.add(newRewards);
        accRewardsPerAllocatedToken = subgraph.accRewardsPerAllocatedToken.add(
            newRewards.mul(FIXED_POINT_SCALING_FACTOR).div(subgraphAllocatedTokens)
        );
        subgraph.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        subgraph.accRewardsForSubgraphSnapshot = subgraph.accRewardsForSubgraph;
    }

    /// @inheritdoc IRewardsManager
    function getRewards(address _rewardsIssuer, address _allocationID) external view override returns (uint256) {
        require(
            _rewardsIssuer == address(staking()) || _rewardsIssuer == address(subgraphService),
            "Not a rewards issuer"
        );

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
     * @notice Calculate rewards for an allocation
     * @param rewardsIssuer Address of the rewards issuer calling the function
     * @param allocationID Address of the allocation
     * @return rewards Amount of rewards calculated
     * @return indexer Address of the indexer
     * @return subgraphDeploymentID Subgraph deployment ID
     */
    function _calcAllocationRewards(
        address rewardsIssuer,
        address allocationID
    ) private returns (uint256 rewards, address indexer, bytes32 subgraphDeploymentID) {
        (
            bool isActive,
            address _indexer,
            bytes32 _subgraphDeploymentID,
            uint256 tokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        ) = IRewardsIssuer(rewardsIssuer).getAllocationData(allocationID);

        uint256 updatedAccRewardsPerAllocatedToken = onSubgraphAllocationUpdate(_subgraphDeploymentID);

        rewards = isActive
            ? accRewardsPending.add(
                _calcRewards(tokens, accRewardsPerAllocatedToken, updatedAccRewardsPerAllocatedToken)
            )
            : 0;

        indexer = _indexer;
        subgraphDeploymentID = _subgraphDeploymentID;
    }

    /**
     * @notice Reclaim rewards to reason-specific address or default fallback
     * @param reason Reclaim reason identifier
     * @param rewards Amount of rewards to reclaim
     * @param indexer Address of the indexer
     * @param allocationId Address of the allocation
     * @param subgraphDeploymentId Subgraph deployment ID for the allocation
     * @return Amount reclaimed (0 if no target address configured)
     *
     * @dev ## Reclaim Priority
     *
     * 1. Try the reason-specific address
     * 2. If not configured, try defaultReclaimAddress
     * 3. If neither configured, rewards are dropped (not minted), returns 0
     */
    function _reclaimRewards(
        bytes32 reason,
        uint256 rewards,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId
    ) private returns (uint256) {
        if (rewards == 0) return 0;

        address target = reclaimAddresses[reason];
        if (target == address(0)) target = defaultReclaimAddress;
        if (target == address(0)) return 0; // Dropped, not reclaimed

        graphToken().mint(target, rewards);
        emit RewardsReclaimed(reason, rewards, indexer, allocationId, subgraphDeploymentId);
        return rewards;
    }

    /**
     * @notice Check if rewards should be denied and attempt to reclaim them
     * @param rewards Amount of rewards to check
     * @param indexer Address of the indexer
     * @param allocationID Address of the allocation
     * @param subgraphDeploymentID Subgraph deployment ID for the allocation
     * @return denied True if rewards are denied (either reclaimed or dropped), false if they should be minted
     * @dev Emits denial events, then attempts reclaim.
     * Prefers subgraph denial over indexer ineligibility as reason when both apply.
     * First configured applicable reclaim address is used.
     * If rewards denied but no specific address is configured, the default reclaim address is used.
     * If no applicable reclaim address is configured, rewards are not minted.
     */
    function _deniedRewards(
        uint256 rewards,
        address indexer,
        address allocationID,
        bytes32 subgraphDeploymentID
    ) private returns (bool denied) {
        bool isDeniedSubgraph = isDenied(subgraphDeploymentID);
        bool isIneligible = address(rewardsEligibilityOracle) != address(0) &&
            !rewardsEligibilityOracle.isEligible(indexer);
        if (!isDeniedSubgraph && !isIneligible) return false;

        if (isDeniedSubgraph) emit RewardsDenied(indexer, allocationID);
        if (isIneligible) emit RewardsDeniedDueToEligibility(indexer, allocationID, rewards);

        bytes32 reason = isDeniedSubgraph ? RewardsCondition.SUBGRAPH_DENIED : RewardsCondition.NONE;
        if (isIneligible && (!isDeniedSubgraph || reclaimAddresses[reason] == address(0)))
            reason = RewardsCondition.INDEXER_INELIGIBLE;

        _reclaimRewards(reason, rewards, indexer, allocationID, subgraphDeploymentID);
        return true;
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev This function can only be called by an authorized rewards issuer which are
     * the staking contract (for legacy allocations), and the subgraph service (for new allocations).
     * Mints 0 tokens if the allocation is not active.
     * @dev First successful reclaim wins - short-circuits on reclaim:
     * - If subgraph denied with reclaim address → reclaim to SUBGRAPH_DENIED address (eligibility NOT checked)
     * - If subgraph not denied OR denied without address, then check eligibility → reclaim to INDEXER_INELIGIBLE if configured
     * - Subsequent denial emitted only when earlier denial has no reclaim address
     * - Any denial without reclaim address drops rewards (no minting)
     */
    function takeRewards(address _allocationID) external override returns (uint256) {
        address rewardsIssuer = msg.sender;
        require(
            rewardsIssuer == address(staking()) || rewardsIssuer == address(subgraphService),
            "Caller must be a rewards issuer"
        );

        (uint256 rewards, address indexer, bytes32 subgraphDeploymentID) = _calcAllocationRewards(
            rewardsIssuer,
            _allocationID
        );

        if (rewards == 0) return 0;
        if (_deniedRewards(rewards, indexer, _allocationID, subgraphDeploymentID)) return 0;

        graphToken().mint(rewardsIssuer, rewards);
        emit HorizonRewardsAssigned(indexer, _allocationID, rewards);

        return rewards;
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev bytes32(0) as a reason is reserved as a no-op and will not be reclaimed.
     */
    function reclaimRewards(bytes32 reason, address allocationID) external override returns (uint256) {
        address rewardsIssuer = msg.sender;
        require(rewardsIssuer == address(subgraphService), "Not a rewards issuer");

        (uint256 rewards, address indexer, bytes32 subgraphDeploymentID) = _calcAllocationRewards(
            rewardsIssuer,
            allocationID
        );

        return _reclaimRewards(reason, rewards, indexer, allocationID, subgraphDeploymentID);
    }
}
