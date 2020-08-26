pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../upgrades/GraphUpgradeable.sol";

import "./RewardsManagerStorage.sol";
import "./IRewardsManager.sol";

contract RewardsManager is RewardsManagerV1Storage, GraphUpgradeable, IRewardsManager {
    using SafeMath for uint256;

    uint256 private constant TOKEN_DECIMALS = 1e18;

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
     * @dev Emitted when rewards an indexer claims rewards.
     */
    event RewardsClaimed(address indexer, uint256 amount);

    /**
     * @dev Emitted when a subgraph is denied for claiming rewards.
     */
    event RewardsDenylistUpdated(bytes32 subgraphDeploymentID, uint256 sinceBlock);

    // -- Modifiers --

    modifier onlyEnforcer() {
        require(msg.sender == address(enforcer), "Caller must be the enforcer");
        _;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     * @param _controller Controller for this contract
     */
    function acceptProxy(IGraphProxy _proxy, address _controller) external {
        // Accept to be the implementation for this proxy
        _acceptUpgrade(_proxy);

        // Initialization
        RewardsManager(address(_proxy)).initialize(_controller);
    }

    /**
     * @dev Sets the issuance rate.
     * @param _issuanceRate Issuance rate
     */
    function setIssuanceRate(uint256 _issuanceRate) public override onlyGovernor {
        _setIssuanceRate(_issuanceRate);
    }

    /**
     * @dev Sets the issuance rate.
     * @param _issuanceRate Issuance rate
     */
    function _setIssuanceRate(uint256 _issuanceRate) internal {
        // Called since `issuance rate` will change
        updateAccRewardsPerSignal();

        issuanceRate = _issuanceRate;
        emit ParameterUpdated("issuanceRate");
    }

    /**
     * @dev Sets the enforcer for denegation of rewards to subgraphs.
     * @param _enforcer Address of the enforcer of denied subgraphs
     */
    function setEnforcer(address _enforcer) external override onlyGovernor {
        enforcer = _enforcer;
        emit ParameterUpdated("enforcer");
    }

    /**
     * @dev Sets the indexer as denied to claim rewards.
     * NOTE: Can only be called by the enforcer role
     * @param _subgraphDeploymentID Subgraph deployment ID to deny
     * @param _deny Whether to set the indexer as denied for claiming rewards or not
     */
    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external override onlyEnforcer {
        uint256 sinceBlock = _deny ? block.number : 0;
        denylist[_subgraphDeploymentID] = sinceBlock;
        emit RewardsDenylistUpdated(_subgraphDeploymentID, sinceBlock);
    }

    /**
     * @dev Tells if subgraph is in deny list
     * @param _subgraphDeploymentID Subgraph deployment ID to check
     */
    function isDenied(bytes32 _subgraphDeploymentID) public override returns (bool) {
        return denylist[_subgraphDeploymentID] > 0;
    }

    /**
     * @dev Gets the issuance of rewards per signal since last updated.
     *
     * Compound interest formula: `a = p(1 + r/n)^nt`
     * The formula is simplified with `n = 1` as we apply the interest once every time step.
     * The `r` is passed with +1 included. So for 10% instead of 0.1 it is 1.1
     * The simplified formula is `a = p * r^t`
     *
     * Notation:
     * t: time steps are in blocks since last updated
     * p: total supply of GRT tokens
     * a: inflated amount of total supply for the period `t` when interest `r` is applied
     * x: newly accrued rewards token for the period `t`
     *
     * @return newly accrued rewards per signal since last update
     */
    function getNewRewardsPerSignal() public override view returns (uint256) {
        // Calculate time steps
        uint256 t = block.number.sub(accRewardsPerSignalLastBlockUpdated);
        // Optimization to skip calculations if zero time steps elapsed
        if (t == 0) {
            return 0;
        }

        // Zero issuance
        if (issuanceRate == 0) {
            return 0;
        }

        // Zero issuance if no signalled tokens
        uint256 signalledTokens = curation().getTotalTokens();
        if (signalledTokens == 0) {
            return 0;
        }

        uint256 r = issuanceRate;
        uint256 p = graphToken().totalSupply();
        uint256 a = p.mul(_pow(r, t, TOKEN_DECIMALS)).div(TOKEN_DECIMALS);

        // New issuance per signal during time steps
        uint256 x = a.sub(p);

        // We multiply the decimals to keep the precision as fixed-point number
        return x.mul(TOKEN_DECIMALS).div(signalledTokens);
    }

    /**
     * @dev Gets the currently accumulated rewards per signal.
     */
    function getAccRewardsPerSignal() public override view returns (uint256) {
        return accRewardsPerSignal.add(getNewRewardsPerSignal());
    }

    /**
     * @dev Gets the accumulated rewards for the subgraph.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID)
        public
        override
        view
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 newAccrued = getAccRewardsPerSignal().sub(subgraph.accRewardsPerSignalSnapshot);
        uint256 subgraphSignalledTokens = curation().getCurationPoolTokens(_subgraphDeploymentID);

        uint256 newValue = newAccrued.mul(subgraphSignalledTokens).div(TOKEN_DECIMALS);
        return subgraph.accRewardsForSubgraph.add(newValue);
    }

    /**
     * @dev Gets the accumulated rewards per allocated token for the subgraph.
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for the subgraph
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsPerAllocatedToken(bytes32 _subgraphDeploymentID)
        public
        override
        view
        returns (uint256, uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphDeploymentID];

        uint256 accRewardsForSubgraph = getAccRewardsForSubgraph(_subgraphDeploymentID);
        uint256 newAccrued = accRewardsForSubgraph.sub(subgraph.accRewardsForSubgraphSnapshot);

        uint256 subgraphAllocatedTokens = staking().getSubgraphAllocatedTokens(
            _subgraphDeploymentID
        );
        if (subgraphAllocatedTokens == 0) {
            return (0, accRewardsForSubgraph);
        }

        uint256 newValue = newAccrued.mul(TOKEN_DECIMALS).div(subgraphAllocatedTokens);
        return (subgraph.accRewardsPerAllocatedToken.add(newValue), accRewardsForSubgraph);
    }

    /**
     * @dev Updates the accumulated rewards per signal and save checkpoint block number.
     * Must be called before `issuanceRate` or `total signalled GRT` changes
     * Called from the Curation contract on mint() and burn()
     * @return Accumulated rewards per signal
     */
    function updateAccRewardsPerSignal() public override notPaused returns (uint256) {
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
    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID)
        public
        override
        notPaused
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
     * NOTE: Hook called from the Staking contract on allocate() and settle()
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for a subgraph
     */
    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID)
        public
        override
        notPaused
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
    function getRewards(address _allocationID) public override view returns (uint256) {
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
    ) internal pure returns (uint256) {
        uint256 newAccrued = _endAccRewardsPerAllocatedToken.sub(_startAccRewardsPerAllocatedToken);
        return newAccrued.mul(_tokens).div(TOKEN_DECIMALS);
    }

    /**
     * @dev Assign rewards and make them available for claiming in the pool.
     * @param _allocationID Allocation
     * @return Assigned rewards amount
     */
    function assignRewards(address _allocationID) external override onlyStaking returns (uint256) {
        IStaking.Allocation memory alloc = staking().getAllocation(_allocationID);

        uint256 accRewardsPerAllocatedToken = onSubgraphAllocationUpdate(
            alloc.subgraphDeploymentID
        );

        // Do not do rewards on denied subgraph deployments ID
        uint256 rewards = 0;
        if (!isDenied(alloc.subgraphDeploymentID)) {
            // Calculate rewards and set apart for claiming
            rewards = _calcRewards(
                alloc.tokens,
                alloc.accRewardsPerAllocatedToken,
                accRewardsPerAllocatedToken
            );
            indexerRewards[alloc.indexer] = indexerRewards[alloc.indexer].add(rewards);
        }

        emit RewardsAssigned(alloc.indexer, _allocationID, alloc.settledAtEpoch, rewards);

        return rewards;
    }

    /**
     * @dev Claim accumulated rewards by indexer.
     * The contract mints tokens equivalent to the rewards.
     * @return Rewards amount
     */
    function claim(bool _restake) external override returns (uint256) {
        address indexer = msg.sender;

        uint256 rewards = indexerRewards[indexer];
        require(rewards > 0, "No rewards available for claiming");
        emit RewardsClaimed(indexer, rewards);

        // Mint rewards tokens
        if (_restake) {
            IStaking staking = staking();
            IGraphToken graphToken = graphToken();
            graphToken.mint(address(this), rewards);
            graphToken.approve(address(staking), rewards);
            staking.stakeTo(indexer, rewards);
        } else {
            graphToken().mint(indexer, rewards);
        }

        return rewards;
    }

    /**
     * @dev Raises x to the power of n with scaling factor of base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param x Base of the exponentation
     * @param n Exponent
     * @param base Scaling factor
     * @return z Exponential of n with base x
     */
    function _pow(
        uint256 x,
        uint256 n,
        uint256 base
    ) internal pure returns (uint256 z) {
        assembly {
            switch x
                case 0 {
                    switch n
                        case 0 {
                            z := base
                        }
                        default {
                            z := 0
                        }
                }
                default {
                    switch mod(n, 2)
                        case 0 {
                            z := base
                        }
                        default {
                            z := x
                        }
                    let half := div(base, 2) // for rounding.
                    for {
                        n := div(n, 2)
                    } n {
                        n := div(n, 2)
                    } {
                        let xx := mul(x, x)
                        if iszero(eq(div(xx, x), x)) {
                            revert(0, 0)
                        }
                        let xxRound := add(xx, half)
                        if lt(xxRound, xx) {
                            revert(0, 0)
                        }
                        x := div(xxRound, base)
                        if mod(n, 2) {
                            let zx := mul(z, x)
                            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                                revert(0, 0)
                            }
                            let zxRound := add(zx, half)
                            if lt(zxRound, zx) {
                                revert(0, 0)
                            }
                            z := div(zxRound, base)
                        }
                    }
                }
        }
    }
}
