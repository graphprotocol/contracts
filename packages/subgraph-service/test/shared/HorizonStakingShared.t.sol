// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { SubgraphBaseTest } from "../SubgraphBaseTest.t.sol";

abstract contract HorizonStakingSharedTest is SubgraphBaseTest {

    /*
     * HELPERS
     */

    function _createProvision(
        address _indexer,
        uint256 _tokens,
        uint32 _maxSlashingPercentage,
        uint64 _disputePeriod
    ) internal {
        _stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, _maxSlashingPercentage, _disputePeriod);
    }

    function _addToProvision(address _indexer, uint256 _tokens) internal {
        _stakeTo(_indexer, _tokens);
        staking.addToProvision(_indexer, address(subgraphService), _tokens);
    }

    function _delegate(address _indexer, address _verifier, uint256 _tokens, uint256 _minSharesOut) internal {
        staking.delegate(_indexer, _verifier, _tokens, _minSharesOut);
    }

    function _setDelegationFeeCut(
        address _indexer,
        address _verifier,
        IGraphPayments.PaymentTypes _paymentType,
        uint256 _cut
    ) internal {
        staking.setDelegationFeeCut(_indexer, _verifier, _paymentType, _cut);
    }

    function _thawDeprovisionAndUnstake(address _indexer, address _verifier, uint256 _tokens) internal {
        // Initiate thaw request
        staking.thaw(_indexer, _verifier, _tokens);
        
        // Skip thawing period
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(_indexer, _verifier);
        skip(provision.thawingPeriod + 1);
        
        // Deprovision and unstake
        staking.deprovision(_indexer, _verifier, 0);
        staking.unstake(_tokens);
    }

    function _setProvisionParameters(
        address _indexer,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) internal {
        staking.setProvisionParameters(_indexer, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    /*
     * PRIVATE
     */

    function _stakeTo(address _indexer, uint256 _tokens) private {
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
    }
}
