pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@statechannels/nitro-protocol/contracts/ERC20AssetHolder.sol";

import "../staking/Staking.sol";
import "../token/IGraphToken.sol";

/// @title GRTAssetHolder - Container for funds used to pay an indexer off-chain
contract GRTAssetHolder is ERC20AssetHolder {
    address StakingAddress;

    constructor(
        address _AdjudicatorAddress,
        address _StakingAddress
    ) public {
        AdjudicatorAddress = _AdjudicatorAddress;
        Token = IERC20(_TokenAddress);
        StakingAddress = _StakingAddress;
    }

    function _transferAsset(
        address payable destination,
        uint256 amount
    ) internal override {
        Staking staking = Staking(StakingAddress);

        if (staking.isChannel(destination)) {
            require(
                staking.collect(destination, amount),
                "GRTAssetHolder: collecting payments failed"
            );
        } else {
            require(
                token.transfer(node, amount),
                "GRTAssetHolder: transferring tokens failed"
            );
        }
    }
}
