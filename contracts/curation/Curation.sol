// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../bancor/BancorFormula.sol";
import "../upgrades/GraphUpgradeable.sol";

import "./CurationStorage.sol";
import "./ICuration.sol";
import "./GraphCurationToken.sol";

/**
 * @title Curation contract
 * @dev Allows curators to signal on subgraph deployments that might be relevant to indexers by
 * staking Graph Tokens (GRT). Additionally, curators earn fees from the Query Market related to the
 * subgraph deployment they curate.
 * A curators deposit goes to a curation pool along with the deposits of other curators,
 * only one such pool exists for each subgraph deployment.
 * The contract mints Graph Curation Shares (GCS) according to a bonding curve for each individual
 * curation pool where GRT is deposited.
 * Holders can burn GCS using this contract to get GRT tokens back according to the
 * bonding curve.
 */
contract Curation is CurationV1Storage, GraphUpgradeable, ICuration {
    using SafeMath for uint256;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    // Amount of signal you get with your minimum token deposit
    uint256 private constant SIGNAL_PER_MINIMUM_DEPOSIT = 1e18; // 1 signal as 18 decimal number

    // -- Events --

    /**
     * @dev Emitted when `curator` deposited `tokens` on `subgraphDeploymentID` as curation signal.
     * The `curator` receives `signal` amount according to the curation pool bonding curve.
     * An amount of `curationTax` will be collected and burned.
     */
    event Signalled(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 signal,
        uint256 curationTax
    );

    /**
     * @dev Emitted when `curator` burned `signal` for a `subgraphDeploymentID`.
     * The curator will receive `tokens` according to the value of the bonding curve.
     */
    event Burned(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 signal
    );

    /**
     * @dev Emitted when `tokens` amount were collected for `subgraphDeploymentID` as part of fees
     * distributed by an indexer from query fees received from state channels.
     */
    event Collected(bytes32 indexed subgraphDeploymentID, uint256 tokens);

    /**
     * @dev Initialize this contract.
     */
    function initialize(
        address _controller,
        address _bondingCurve,
        uint32 _defaultReserveRatio,
        uint32 _curationTaxPercentage,
        uint256 _minimumCurationDeposit
    ) external onlyImpl {
        Managed._initialize(_controller);

        require(_bondingCurve != address(0), "Bonding curve must be set");
        bondingCurve = _bondingCurve;

        // Settings
        _setDefaultReserveRatio(_defaultReserveRatio);
        _setCurationTaxPercentage(_curationTaxPercentage);
        _setMinimumCurationDeposit(_minimumCurationDeposit);
    }

    /**
     * @dev Set the default reserve ratio percentage for a curation pool.
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint32 _defaultReserveRatio) external override onlyGovernor {
        _setDefaultReserveRatio(_defaultReserveRatio);
    }

    /**
     * @dev Internal: Set the default reserve ratio percentage for a curation pool.
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function _setDefaultReserveRatio(uint32 _defaultReserveRatio) private {
        // Reserve Ratio must be within 0% to 100% (inclusive, in PPM)
        require(_defaultReserveRatio > 0, "Default reserve ratio must be > 0");
        require(
            _defaultReserveRatio <= MAX_PPM,
            "Default reserve ratio cannot be higher than MAX_PPM"
        );

        defaultReserveRatio = _defaultReserveRatio;
        emit ParameterUpdated("defaultReserveRatio");
    }

    /**
     * @dev Set the minimum deposit amount for curators.
     * @notice Update the minimum deposit amount to `_minimumCurationDeposit`
     * @param _minimumCurationDeposit Minimum amount of tokens required deposit
     */
    function setMinimumCurationDeposit(uint256 _minimumCurationDeposit)
        external
        override
        onlyGovernor
    {
        _setMinimumCurationDeposit(_minimumCurationDeposit);
    }

    /**
     * @dev Internal: Set the minimum deposit amount for curators.
     * @notice Update the minimum deposit amount to `_minimumCurationDeposit`
     * @param _minimumCurationDeposit Minimum amount of tokens required deposit
     */
    function _setMinimumCurationDeposit(uint256 _minimumCurationDeposit) private {
        require(_minimumCurationDeposit > 0, "Minimum curation deposit cannot be 0");

        minimumCurationDeposit = _minimumCurationDeposit;
        emit ParameterUpdated("minimumCurationDeposit");
    }

    /**
     * @dev Set the curation tax percentage to charge when a curator deposits GRT tokens.
     * @param _percentage Curation tax percentage charged when depositing GRT tokens
     */
    function setCurationTaxPercentage(uint32 _percentage) external override onlyGovernor {
        _setCurationTaxPercentage(_percentage);
    }

    /**
     * @dev Internal: Set the curation tax percentage to charge when a curator deposits GRT tokens.
     * @param _percentage Curation tax percentage charged when depositing GRT tokens
     */
    function _setCurationTaxPercentage(uint32 _percentage) private {
        require(
            _percentage <= MAX_PPM,
            "Curation tax percentage must be below or equal to MAX_PPM"
        );

        _curationTaxPercentage = _percentage;
        emit ParameterUpdated("curationTaxPercentage");
    }

    /**
     * @dev Assign Graph Tokens collected as curation fees to the curation pool reserve.
     * This function can only be called by the Staking contract and will do the bookeeping of
     * transferred tokens into this contract.
     * @param _subgraphDeploymentID SubgraphDeployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external override {
        // Only Staking contract is authorized as caller
        require(msg.sender == address(staking()), "Caller must be the staking contract");

        // Must be curated to accept tokens
        require(
            isCurated(_subgraphDeploymentID),
            "Subgraph deployment must be curated to collect fees"
        );

        // Collect new funds into reserve
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        curationPool.tokens = curationPool.tokens.add(_tokens);

        emit Collected(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Deposit Graph Tokens in exchange for signal of a SubgraphDeployment curation pool.
     * @param _subgraphDeploymentID Subgraph deployment pool from where to mint signal
     * @param _tokensIn Amount of Graph Tokens to deposit
     * @param _signalOutMin Expected minimum amount of signal to receive
     * @return Signal minted and deposit tax
     */
    function mint(
        bytes32 _subgraphDeploymentID,
        uint256 _tokensIn,
        uint256 _signalOutMin
    ) external override notPartialPaused returns (uint256, uint256) {
        // Need to deposit some funds
        require(_tokensIn > 0, "Cannot deposit zero tokens");

        // Exchange GRT tokens for GCS of the subgraph pool
        (uint256 signalOut, uint256 curationTax) = tokensToSignal(_subgraphDeploymentID, _tokensIn);

        // Slippage protection
        require(signalOut >= _signalOutMin, "Slippage protection");

        address curator = msg.sender;
        CurationPool storage curationPool = pools[_subgraphDeploymentID];

        // If it hasn't been curated before then initialize the curve
        if (!isCurated(_subgraphDeploymentID)) {
            // Initialize
            curationPool.reserveRatio = defaultReserveRatio;

            // If no signal token for the pool - create one
            if (address(curationPool.gcs) == address(0)) {
                // TODO: Use a minimal proxy to reduce gas cost
                // https://github.com/graphprotocol/contracts/issues/405
                // --abarmat-- 20201113
                curationPool.gcs = IGraphCurationToken(
                    address(new GraphCurationToken(address(this)))
                );
            }
        }

        // Trigger update rewards calculation snapshot
        _updateRewards(_subgraphDeploymentID);

        // Transfer tokens from the curator to this contract
        // This needs to happen after _updateRewards snapshot as that function
        // is using balanceOf(curation)
        IGraphToken graphToken = graphToken();
        require(
            graphToken.transferFrom(curator, address(this), _tokensIn),
            "Cannot transfer tokens to deposit"
        );

        // Burn withdrawal fees
        if (curationTax > 0) {
            graphToken.burn(curationTax);
        }

        // Update curation pool
        curationPool.tokens = curationPool.tokens.add(_tokensIn.sub(curationTax));
        curationPool.gcs.mint(curator, signalOut);

        emit Signalled(curator, _subgraphDeploymentID, _tokensIn, signalOut, curationTax);

        return (signalOut, curationTax);
    }

    /**
     * @dev Return an amount of signal to get tokens back.
     * @notice Burn _signal from the SubgraphDeployment curation pool
     * @param _subgraphDeploymentID SubgraphDeployment the curator is returning signal
     * @param _signalIn Amount of signal to return
     * @param _tokensOutMin Expected minimum amount of tokens to receive
     * @return Tokens returned
     */
    function burn(
        bytes32 _subgraphDeploymentID,
        uint256 _signalIn,
        uint256 _tokensOutMin
    ) external override notPartialPaused returns (uint256) {
        address curator = msg.sender;

        // Validations
        require(_signalIn > 0, "Cannot burn zero signal");
        require(
            getCuratorSignal(curator, _subgraphDeploymentID) >= _signalIn,
            "Cannot burn more signal than you own"
        );

        // Get the amount of tokens to refund based on returned signal
        uint256 tokensOut = signalToTokens(_subgraphDeploymentID, _signalIn);

        // Slippage protection
        require(tokensOut >= _tokensOutMin, "Slippage protection");

        // Trigger update rewards calculation
        _updateRewards(_subgraphDeploymentID);

        // Update curation pool
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        curationPool.tokens = curationPool.tokens.sub(tokensOut);
        curationPool.gcs.burnFrom(curator, _signalIn);

        // If all signal burnt delete the curation pool
        if (getCurationPoolSignal(_subgraphDeploymentID) == 0) {
            delete pools[_subgraphDeploymentID];
        }

        // Return the tokens to the curator
        require(graphToken().transfer(curator, tokensOut), "Error sending curator tokens");

        emit Burned(curator, _subgraphDeploymentID, tokensOut, _signalIn);

        return tokensOut;
    }

    /**
     * @dev Check if any GRT tokens are deposited for a SubgraphDeployment.
     * @param _subgraphDeploymentID SubgraphDeployment to check if curated
     * @return True if curated
     */
    function isCurated(bytes32 _subgraphDeploymentID) public view override returns (bool) {
        return pools[_subgraphDeploymentID].tokens > 0;
    }

    /**
     * @dev Get the amount of signal a curator has in a curation pool.
     * @param _curator Curator owning the signal tokens
     * @param _subgraphDeploymentID Subgraph deployment curation pool
     * @return Amount of signal owned by a curator for the subgraph deployment
     */
    function getCuratorSignal(address _curator, bytes32 _subgraphDeploymentID)
        public
        view
        override
        returns (uint256)
    {
        if (address(pools[_subgraphDeploymentID].gcs) == address(0)) {
            return 0;
        }
        return pools[_subgraphDeploymentID].gcs.balanceOf(_curator);
    }

    /**
     * @dev Get the amount of signal in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment curation poool
     * @return Amount of signal minted for the subgraph deployment
     */
    function getCurationPoolSignal(bytes32 _subgraphDeploymentID)
        public
        view
        override
        returns (uint256)
    {
        if (address(pools[_subgraphDeploymentID].gcs) == address(0)) {
            return 0;
        }
        return pools[_subgraphDeploymentID].gcs.totalSupply();
    }

    /**
     * @dev Get the amount of token reserves in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment curation poool
     * @return Amount of token reserves in the curation pool
     */
    function getCurationPoolTokens(bytes32 _subgraphDeploymentID)
        external
        view
        override
        returns (uint256)
    {
        return pools[_subgraphDeploymentID].tokens;
    }

    /**
     * @dev Get curation tax percentage
     * @return Amount the curation tax percentage in PPM
     */
    function curationTaxPercentage() external view override returns (uint32) {
        return _curationTaxPercentage;
    }

    /**
     * @dev Calculate amount of signal that can be bought with tokens in a curation pool.
     * This function considers and excludes the deposit tax.
     * @param _subgraphDeploymentID Subgraph deployment to mint signal
     * @param _tokensIn Amount of tokens used to mint signal
     * @return Amount of signal that can be bought and tokens subtracted for the tax
     */
    function tokensToSignal(bytes32 _subgraphDeploymentID, uint256 _tokensIn)
        public
        view
        override
        returns (uint256, uint256)
    {
        uint256 curationTax = _tokensIn.mul(uint256(_curationTaxPercentage)).div(MAX_PPM);
        uint256 signalOut = _tokensToSignal(_subgraphDeploymentID, _tokensIn.sub(curationTax));
        return (signalOut, curationTax);
    }

    /**
     * @dev Calculate amount of signal that can be bought with tokens in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment to mint signal
     * @param _tokensIn Amount of tokens used to mint signal
     * @return Amount of signal that can be bought with tokens
     */
    function _tokensToSignal(bytes32 _subgraphDeploymentID, uint256 _tokensIn)
        private
        view
        returns (uint256)
    {
        // Get curation pool tokens and signal
        CurationPool memory curationPool = pools[_subgraphDeploymentID];

        // Init curation pool
        if (curationPool.tokens == 0) {
            require(
                _tokensIn >= minimumCurationDeposit,
                "Curation deposit is below minimum required"
            );
            return
                BancorFormula(bondingCurve)
                    .calculatePurchaseReturn(
                        SIGNAL_PER_MINIMUM_DEPOSIT,
                        minimumCurationDeposit,
                        defaultReserveRatio,
                        _tokensIn.sub(minimumCurationDeposit)
                    )
                    .add(SIGNAL_PER_MINIMUM_DEPOSIT);
        }

        return
            BancorFormula(bondingCurve).calculatePurchaseReturn(
                getCurationPoolSignal(_subgraphDeploymentID),
                curationPool.tokens,
                curationPool.reserveRatio,
                _tokensIn
            );
    }

    /**
     * @dev Calculate number of tokens to get when burning signal from a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment to burn signal
     * @param _signalIn Amount of signal to burn
     * @return Amount of tokens to get for an amount of signal
     */
    function signalToTokens(bytes32 _subgraphDeploymentID, uint256 _signalIn)
        public
        view
        override
        returns (uint256)
    {
        CurationPool memory curationPool = pools[_subgraphDeploymentID];
        uint256 curationPoolSignal = getCurationPoolSignal(_subgraphDeploymentID);
        require(
            curationPool.tokens > 0,
            "Subgraph deployment must be curated to perform calculations"
        );
        require(
            curationPoolSignal >= _signalIn,
            "Signal must be above or equal to signal issued in the curation pool"
        );

        return
            BancorFormula(bondingCurve).calculateSaleReturn(
                curationPoolSignal,
                curationPool.tokens,
                curationPool.reserveRatio,
                _signalIn
            );
    }

    /**
     * @dev Triggers an update of rewards due to a change in signal.
     * @param _subgraphDeploymentID Subgraph deployment updated
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) private {
        IRewardsManager rewardsManager = rewardsManager();
        if (address(rewardsManager) != address(0)) {
            rewardsManager.onSubgraphSignalUpdate(_subgraphDeploymentID);
        }
    }
}
