// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { SubgraphBaseTest } from "../SubgraphBaseTest.t.sol";

abstract contract HorizonStakingSharedTest is SubgraphBaseTest {

    /*
     * HELPERS
     */

    function _createProvision(address _indexer, uint256 _tokens, uint32 _maxSlashingPercentage, uint64 _disputePeriod) internal {
        _stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, _maxSlashingPercentage, _disputePeriod);
    }

    function _addToProvision(address _indexer, uint256 _tokens) internal {
        _stakeTo(_indexer, _tokens);
        staking.addToProvision(_indexer, address(subgraphService), _tokens);
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

    /*
     * PRIVATE
     */

    function _stakeTo(address _indexer, uint256 _tokens) private {
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
    }
}
