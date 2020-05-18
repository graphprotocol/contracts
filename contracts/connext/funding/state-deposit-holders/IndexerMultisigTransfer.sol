pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./MultisigData.sol";
import "./MinimumViableMultisig.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../Staking.sol";

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
        address payable recipient,
        address assetId,
        uint256 amount
    ) public {
        address staking = MinimumViableMultisig(masterCopy).INDEXER_STAKING_ADDRESS();
        address token = address(Staking(staking).token());

        if (assetId != token) { return; }

        // Note, explicitly do NOT use safemath here. See discussion in: TODO
        totalAmountWithdrawn[assetId] += amount;

        (address node, address indexer) = getNodeAndIndexer();

        if (recipient == node) {

            IERC20(token).transfer(node, amount);

        } else {

            // transfer to staking contract
            require(
                IERC20(token).approve(staking, amount),
                "IndexerMultisigTransfer: approving tokens to staking contract failed"
            );
            Staking(staking).settle(indexer, amount);

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
