// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@statechannels/nitro-protocol/contracts/ERC20AssetHolder.sol";

import "../governance/IController.sol";
import "../staking/IStaking.sol";

/// @title GRTAssetHolder - Container for funds used to pay an indexer off-chain
contract GRTAssetHolder is ERC20AssetHolder {
    uint256 private constant MAX_UINT256 = 2**256 - 1;

    IController public Controller;

    constructor(
        address _AdjudicatorAddress,
        address _TokenAddress,
        IController _Controller
    ) ERC20AssetHolder(_AdjudicatorAddress, _TokenAddress) {
        AdjudicatorAddress = _AdjudicatorAddress;
        Controller = _Controller;
    }

    function staking() public view returns (IStaking) {
        return IStaking(Controller.getContractProxy(keccak256("Staking")));
    }

    function approveAll() external {
        require(
            Token.approve(address(staking()), MAX_UINT256),
            "GRTAssetHolder: Token approval failed"
        );
    }

    function _transferAsset(address payable destination, uint256 amount) internal override {
        IStaking _staking = staking();

        if (_staking.isAllocation(destination)) {
            _staking.collect(amount, destination);
            return;
        }

        require(Token.transfer(destination, amount), "GRTAssetHolder: transferring tokens failed");
    }
}
