pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./MultisigData.sol";
import "./MinimumViableMultisig.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../Staking.sol";

/// @title IndexerMultisigTransfer - Indexer variant
/// of the regular MultisigTransfer.
contract IndexerMultisigTransfer is MultisigData {

    address constant CONVENTION_FOR_ETH_TOKEN_ADDRESS = address(0x0);

    /// @notice Use this function for transfers of assets out of
    /// the multisig. It does some necessary internal bookkeeping.
    /// @param recipient the recipient of the transfer
    /// @param assetId the asset to be transferred; token address for ERC20, 0 for Ether
    /// @param amount the amount to be transferred

    function multisigTransfer(
        address payable recipient,
        address assetId,
        uint256 amount
    ) public {
        // Note, explicitly do NOT use safemath here. See discussion in: TODO
        totalAmountWithdrawn[assetId] += amount;

        (address node, address indexer) = getNodeAndIndexer();

        if (recipient == node) {

            if (assetId == CONVENTION_FOR_ETH_TOKEN_ADDRESS) {
                // note: send() is deliberately used instead of transfer() here
                // so that a revert does not stop the rest of the sends
                // solium-disable-next-line security/no-send
                recipient.send(amount);
            } else {
                IERC20(assetId).transfer(recipient, amount);
            }

        } else {

            // transfer to staking contract
            address staking = MinimumViableMultisig(masterCopy).INDEXER_STAKING_ADDRESS();
            require(
                IERC20(assetId).approve(staking, amount),
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
