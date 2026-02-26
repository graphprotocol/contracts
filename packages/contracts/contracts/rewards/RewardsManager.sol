// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
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
     *
     * IMPORTANT: This function does not update existing subgraphs. When subgraphs are later
     * updated, the current threshold is applied to ALL pending rewards since their last update,
     * regardless of historical threshold values.
     *
     * ## Rewards Accounting Issue
     *
     * - Threshold increase: Pending rewards on previously eligible subgraphs are reclaimed
     * - Threshold decrease: Previously ineligible subgraphs retroactively accumulate pending rewards
     *
     * ## Mitigation
     *
     * 1. Communicate the planned threshold change with a specific future date
     * 2. Wait - notice period allows participants to adjust signal if desired
     * 3. Identify affected subgraphs off-chain (those crossing the threshold)
     * 4. Call onSubgraphSignalUpdate() for all affected subgraphs to accumulate pending rewards
     *    under current eligibility rules
     * 5. Execute threshold change via this function (promptly after step 4, ideally same block)
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
        require(reason != RewardsCondition.NONE, "Cannot set reclaim address for NONE");

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
     * @notice Sets the denied status for a subgraph.
     * @dev Idempotent: redundant calls skip the update but still call `onSubgraphAllocationUpdate`.
     * @param subgraphDeploymentId Subgraph deployment ID
     * @param deny True to deny rewards, false to allow
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

    /// @inheritdoc IRewardsManager
    function getNewRewardsPerSignal() public view override returns (uint256 claimablePerSignal) {
        (claimablePerSignal, ) = _getNewRewardsPerSignal();
    }

    /**
     * @notice Calculate new rewards per signal since last update
     * @dev Formula: `x = r * t` where t = blocks since last update.
     * @return claimablePerSignal Rewards per signal (scaled by FIXED_POINT_SCALING_FACTOR)
     * @return unclaimableTokens Tokens not distributed due to zero signal
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
     * Reclaim for non-claimable subgraphs is handled in `onSubgraphSignalUpdate()` and `onSubgraphAllocationUpdate()`.
     */
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID) public view override returns (uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        (uint256 newRewards, , bytes32 condition) = _getSubgraphRewardsState(_subgraphDeploymentID);
        return subgraph.accRewardsForSubgraph.add(condition == RewardsCondition.NONE ? newRewards : 0);
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev New rewards are only included via `getAccRewardsForSubgraph` when subgraph is claimable.
     * Pre-existing stored rewards are always shown as distributable (preserved for when conditions clear).
     * Does not check indexer eligibility - that can change and doesn't affect reward accrual.
     */
    function getAccRewardsPerAllocatedToken(
        bytes32 _subgraphDeploymentID
    ) public view override returns (uint256, uint256) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        // getAccRewardsForSubgraph already handles claimability: excludes new rewards when not claimable
        uint256 accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        uint256 newRewardsForSubgraph = MathUtils.diffOrZero(
            accRewardsForSubgraph,
            subgraph.accRewardsForSubgraphSnapshot
        );

        // Get total allocated tokens across all issuers
        uint256 subgraphAllocatedTokens = _getSubgraphAllocatedTokens(_subgraphDeploymentID);

        if (subgraphAllocatedTokens == 0) {
            // No allocations to distribute to, return stored value (no pending updates possible)
            return (subgraph.accRewardsPerAllocatedToken, accRewardsForSubgraph);
        }

        uint256 newRewardsPerAllocatedToken = newRewardsForSubgraph.mul(FIXED_POINT_SCALING_FACTOR).div(
            subgraphAllocatedTokens
        );
        return (subgraph.accRewardsPerAllocatedToken.add(newRewardsPerAllocatedToken), accRewardsForSubgraph);
    }

    // -- Internal Helpers --

    /**
     * @notice Get subgraph rewards state including effective reclaim condition
     * @dev Determines claimability with priority: SUBGRAPH_DENIED > BELOW_MINIMUM_SIGNAL > NO_ALLOCATED_TOKENS > NONE
     * When multiple conditions apply, prefers conditions with configured reclaim addresses.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return newRewards Rewards accumulated since last snapshot
     * @return subgraphAllocatedTokens Total tokens allocated to this subgraph
     * @return condition The effective condition for reclaim routing (NONE if claimable)
     */
    function _getSubgraphRewardsState(
        bytes32 _subgraphDeploymentID
    ) private view returns (uint256 newRewards, uint256 subgraphAllocatedTokens, bytes32 condition) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        uint256 signalledTokens = curation().getCurationPoolTokens(_subgraphDeploymentID);
        uint256 accRewardsPerSignalDelta = getAccRewardsPerSignal().sub(subgraph.accRewardsPerSignalSnapshot);
        newRewards = accRewardsPerSignalDelta.mul(signalledTokens).div(FIXED_POINT_SCALING_FACTOR);
        subgraphAllocatedTokens = _getSubgraphAllocatedTokens(_subgraphDeploymentID);

        condition = isDenied(_subgraphDeploymentID) ? RewardsCondition.SUBGRAPH_DENIED : RewardsCondition.NONE;
        if (
            signalledTokens < minimumSubgraphSignal &&
            (condition == RewardsCondition.NONE || reclaimAddresses[condition] == address(0))
        ) condition = RewardsCondition.BELOW_MINIMUM_SIGNAL;
        if (
            subgraphAllocatedTokens == 0 &&
            (condition == RewardsCondition.NONE || reclaimAddresses[condition] == address(0))
        ) condition = RewardsCondition.NO_ALLOCATED_TOKENS;
    }

    /**
     * @notice Get total allocated tokens for a subgraph across all issuers
     * @param _subgraphDeploymentID Subgraph deployment
     * @return subgraphAllocatedTokens Total tokens allocated to this subgraph
     */
    function _getSubgraphAllocatedTokens(
        bytes32 _subgraphDeploymentID
    ) private view returns (uint256 subgraphAllocatedTokens) {
        if (address(subgraphService) != address(0))
            subgraphAllocatedTokens += subgraphService.getSubgraphAllocatedTokens(_subgraphDeploymentID);
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
        if (accRewardsPerSignalLastBlockUpdated == block.number) return accRewardsPerSignal;

        (uint256 claimablePerSignal, uint256 unclaimableTokens) = _getNewRewardsPerSignal();

        if (0 < unclaimableTokens)
            _reclaimRewards(RewardsCondition.NO_SIGNAL, unclaimableTokens, address(0), address(0), bytes32(0));

        uint256 newAccRewardsPerSignal = accRewardsPerSignal.add(claimablePerSignal);
        accRewardsPerSignal = newAccRewardsPerSignal;
        accRewardsPerSignalLastBlockUpdated = block.number;
        return newAccRewardsPerSignal;
    }

    /**
     * @notice Internal function that updates subgraph reward accumulators.
     * Shared logic for both signal and allocation update hooks.
     *
     * @param subgraph Storage pointer to the subgraph
     * @param _subgraphDeploymentID The subgraph deployment ID
     * @param accRewardsPerSignal Current global rewards per signal
     * @param accRewardsForSubgraph Current subgraph accumulated rewards
     * @param accRewardsPerAllocatedToken Current rewards per allocated token
     * @return newAccRewardsForSubgraph Updated subgraph accumulated rewards
     * @return newAccRewardsPerAllocatedToken Updated rewards per allocated token
     */
    function _updateSubgraphRewards(
        Subgraph storage subgraph,
        bytes32 _subgraphDeploymentID,
        uint256 accRewardsPerSignal,
        uint256 accRewardsForSubgraph,
        uint256 accRewardsPerAllocatedToken
    ) internal returns (uint256 newAccRewardsForSubgraph, uint256 newAccRewardsPerAllocatedToken) {
        (
            uint256 rewardsSinceSignalSnapshot,
            uint256 subgraphAllocatedTokens,
            bytes32 condition
        ) = _getSubgraphRewardsState(_subgraphDeploymentID);
        subgraph.accRewardsPerSignalSnapshot = accRewardsPerSignal;

        // Calculate undistributed: rewards accumulated but not yet distributed to allocations.
        // Will be just rewards since last snapshot for subgraphs that have had onSubgraphSignalUpdate or
        // onSubgraphAllocationUpdate called since upgrade;
        // can include non-zero (original) accRewardsForSubgraph - accRewardsForSubgraphSnapshot for
        // subgraphs that have not had either hook called since upgrade.
        uint256 undistributedRewards = accRewardsForSubgraph.sub(subgraph.accRewardsForSubgraphSnapshot).add(
            rewardsSinceSignalSnapshot
        );

        if (condition != RewardsCondition.NONE) {
            _reclaimRewards(condition, undistributedRewards, address(0), address(0), _subgraphDeploymentID);
            undistributedRewards = 0;
            newAccRewardsForSubgraph = accRewardsForSubgraph;
        } else {
            newAccRewardsForSubgraph = accRewardsForSubgraph.add(rewardsSinceSignalSnapshot);
            subgraph.accRewardsForSubgraph = newAccRewardsForSubgraph;
        }

        subgraph.accRewardsForSubgraphSnapshot = newAccRewardsForSubgraph;

        newAccRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        if (undistributedRewards != 0) {
            newAccRewardsPerAllocatedToken = accRewardsPerAllocatedToken.add(
                undistributedRewards.mul(FIXED_POINT_SCALING_FACTOR).div(subgraphAllocatedTokens)
            );
            subgraph.accRewardsPerAllocatedToken = newAccRewardsPerAllocatedToken;
        }
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Must be called before `signalled GRT` on a subgraph changes.
     * Hook called from the Curation contract on mint() and burn()
     *
     * ## Claimability Behavior
     *
     * When a subgraph is not claimable (denied, below minimum signal, or no allocations):
     * - Rewards are reclaimed immediately with the appropriate reason
     * - `accRewardsForSubgraph` is NOT updated (rewards go to reclaim, not accumulator)
     *
     * When claimable (not denied, above minimum signal, has allocations):
     * - Rewards are added to `accRewardsForSubgraph` for later distribution via `onSubgraphAllocationUpdate`
     */
    function onSubgraphSignalUpdate(
        bytes32 _subgraphDeploymentID
    ) external override returns (uint256 accRewardsForSubgraph) {
        // Called since `total signalled GRT` will change
        uint256 accRewardsPerSignal = updateAccRewardsPerSignal();

        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];
        accRewardsForSubgraph = subgraph.accRewardsForSubgraph;

        if (subgraph.accRewardsPerSignalSnapshot == accRewardsPerSignal) return accRewardsForSubgraph;

        (accRewardsForSubgraph, ) = _updateSubgraphRewards(
            subgraph,
            _subgraphDeploymentID,
            accRewardsPerSignal,
            accRewardsForSubgraph,
            subgraph.accRewardsPerAllocatedToken
        );
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Hook called from the IRewardsIssuer contract on allocate() and close()
     *
     * ## Claimability Behavior
     *
     * When a subgraph is not claimable (denied, below minimum signal, or no allocations):
     * - Rewards are reclaimed immediately with the appropriate reason
     * - `accRewardsForSubgraph` is NOT updated (rewards go to reclaim, not accumulator)
     * - `accRewardsPerAllocatedToken` does NOT increase
     *
     * When claimable (not denied, above minimum signal, has allocations):
     * - Rewards are added to `accRewardsForSubgraph`
     * - `accRewardsPerAllocatedToken` increases (rewards distributable to allocations)
     *
     * @return accRewardsPerAllocatedToken Current `accRewardsPerAllocatedToken`
     */
    function onSubgraphAllocationUpdate(
        bytes32 _subgraphDeploymentID
    ) public override returns (uint256 accRewardsPerAllocatedToken) {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 accRewardsPerSignal = updateAccRewardsPerSignal();
        uint256 accRewardsForSubgraph = subgraph.accRewardsForSubgraph;
        accRewardsPerAllocatedToken = subgraph.accRewardsPerAllocatedToken;

        // Return early to save gas if both snapshots are up-to-date
        if (
            subgraph.accRewardsPerSignalSnapshot == accRewardsPerSignal &&
            subgraph.accRewardsForSubgraphSnapshot == accRewardsForSubgraph
        ) return accRewardsPerAllocatedToken;

        (, accRewardsPerAllocatedToken) = _updateSubgraphRewards(
            subgraph,
            _subgraphDeploymentID,
            accRewardsPerSignal,
            accRewardsForSubgraph,
            accRewardsPerAllocatedToken
        );
    }

    /**
     * @inheritdoc IRewardsManager
     * @dev Reflects the gap between the subgraph accumulator and the allocation's snapshot, plus
     * stored pending rewards. During exclusion (denied, below minimum signal, no allocations), the
     * accumulator is frozen: new rewards are excluded but the existing gap remains claimable when
     * conditions clear. Does not check indexer eligibility - that is verified at claim time via
     * takeRewards().
     */
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
        if (reason == RewardsCondition.NONE) return 0; // NONE cannot be used as reclaim reason

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
     * - the subgraph service (for allocations).
     * Mints 0 tokens if the allocation is not active.
     * @dev First successful reclaim wins - short-circuits on reclaim:
     * - If subgraph denied with reclaim address → reclaim to SUBGRAPH_DENIED address (eligibility NOT checked)
     * - If subgraph not denied OR denied without address, then check eligibility → reclaim to INDEXER_INELIGIBLE if configured
     * - Subsequent denial emitted only when earlier denial has no reclaim address
     * - Any denial without reclaim address drops rewards (no minting)
     */
    function takeRewards(address _allocationID) external override returns (uint256) {
        address rewardsIssuer = msg.sender;
        require(rewardsIssuer == address(subgraphService), "Caller must be a rewards issuer");

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
     * @dev bytes32(0) (NONE) cannot be used as a reclaim reason and will return 0.
     * Use specific RewardsCondition constants for reclaim reasons.
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
