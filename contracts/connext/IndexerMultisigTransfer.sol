pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "../staking/Staking.sol";
import "../token/IGraphToken.sol";

import "./MultisigData.sol";
import "./MinimumViableMultisig.sol";

/// @title IndexerMultisigTransfer - Indexer variant
/// of the regular MultisigTransfer.
contract IndexerMultisigTransfer is MultisigData {
    /// @notice Use this function for transfers of assets out of
    /// the multisig.
    /// @param recipient the recipient of the transfer -- unless this is the node's
    /// address, the funds will be transferred to the staking contract on the indexer's behalf
    /// @param assetId the asset to be transferred; must be the Graph token
    /// @param amount the amount to be transferred

    function multisigTransfer(
        address recipient,
        address assetId,
        uint256 amount
    ) public {
        Staking staking = Staking(MinimumViableMultisig(masterCopy).INDEXER_STAKING_ADDRESS());
        IGraphToken token = staking.token();

        if (assetId != address(token)) {
            return;
        }

        // Note, explicitly do NOT use safemath here. See discussion in: TODO
        totalAmountWithdrawn[assetId] += amount;

        (address node, address indexer) = getNodeAndIndexer();

        if (recipient == node) {
            require(
                token.transfer(node, amount),
                "IndexerMultisigTransfer: transferring tokens to node failed"
            );
        } else {
            // transfer to staking contract
            require(
                token.approve(address(staking), amount),
                "IndexerMultisigTransfer: approving tokens to staking contract failed"
            );
            staking.collect(amount, indexer);
        }
    }

    function getNodeAndIndexer() public view returns (address, address) {
        if (_owners[0] == MinimumViableMultisig(masterCopy).NODE_ADDRESS()) {
            return (_owners[0], _owners[1]);
        } else {
            return (_owners[1], _owners[0]);
        }
    }
}
