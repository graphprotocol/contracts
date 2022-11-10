// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { GNS } from "./GNS.sol";

import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { L1ArbitrumMessenger } from "../arbitrum/L1ArbitrumMessenger.sol";
import { IL2GNS } from "../l2/discovery/IL2GNS.sol";
import { IGraphToken } from "../token/IGraphToken.sol";
import { L1GNSV1Storage } from "./L1GNSStorage.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract L1GNS is GNS, L1GNSV1Storage, L1ArbitrumMessenger {
    using SafeMathUpgradeable for uint256;

    /// @dev Emitted when a subgraph was locked as preparation to migrating it to L2
    event SubgraphLockedForMigrationToL2(uint256 _subgraphID);
    /// @dev Emitted when a subgraph was sent to L2 through the bridge
    event SubgraphSentToL2(uint256 _subgraphID);
    /// @dev Emitted when the address of the Arbitrum Inbox was updated
    event ArbitrumInboxAddressUpdated(address _inbox);

    /**
     * @dev sets the addresses for L1 inbox provided by Arbitrum
     * @param _inbox Address of the Inbox that is part of the Arbitrum Bridge
     */
    function setArbitrumInboxAddress(address _inbox) external onlyGovernor {
        arbitrumInboxAddress = _inbox;
        emit ArbitrumInboxAddressUpdated(_inbox);
    }

    /**
     * @notice Lock a subgraph for migration to L2.
     * This will lock the subgraph's curator balance and prevent any further
     * changes to the subgraph.
     * WARNING: After calling this function, the subgraph owner has 255 blocks
     * to call sendSubgraphToL2 to complete the migration; otherwise, the
     * subgraph will have to be deprecated using deprecateLockedSubgraph,
     * and the deployment to L2 will have to be manual (and curators will
     * have to manually move the signal over too).
     * @param _subgraphID Subgraph ID
     */
    function lockSubgraphForMigrationToL2(uint256 _subgraphID)
        external
        payable
        notPartialPaused
        onlySubgraphAuth(_subgraphID)
    {
        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];

        // Lock the subgraph so no more signal can be minted or burned.

        // Burn all version signal in the name pool for tokens (w/no slippage protection)
        // Sell all signal from the old deployment
        migrationData.tokens = curation().burn(
            subgraphData.subgraphDeploymentID,
            subgraphData.vSignal,
            0
        );

        subgraphData.disabled = true;
        subgraphData.vSignal = 0;

        migrationData.lockedAtBlock = block.number;
        emit SubgraphLockedForMigrationToL2(_subgraphID);
    }

    /**
     * @notice Send a subgraph's data and tokens to L2.
     * The subgraph must be locked using lockSubgraphForMigrationToL2 in a previous block
     * (less than 255 blocks ago).
     * Use the Arbitrum SDK to estimate the L2 retryable ticket parameters.
     * @param _subgraphID Subgraph ID
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function sendSubgraphToL2(
        uint256 _subgraphID,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable notPartialPaused {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];
        require(
            migrationData.lockedAtBlock > 0 && migrationData.lockedAtBlock < block.number,
            "!LOCKED"
        );
        require(migrationData.lockedAtBlock.add(255) >= block.number, "TOO_LATE");
        require(!migrationData.l1Done, "ALREADY_DONE");
        // This is just like onlySubgraphAuth, but we want it to run after the other checks
        // to revert with a nicer message in those cases:
        require(ownerOf(_subgraphID) == msg.sender, "GNS: Must be authorized");
        migrationData.l1Done = true;

        bytes memory extraData = _encodeSubgraphDataForL2(_subgraphID, migrationData, subgraphData);

        bytes memory data = abi.encode(_maxSubmissionCost, extraData);
        IGraphToken grt = graphToken();
        ITokenGateway gateway = ITokenGateway(_resolveContract(keccak256("GraphTokenGateway")));
        grt.approve(address(gateway), migrationData.tokens);
        gateway.outboundTransfer{ value: msg.value }(
            address(grt),
            counterpartGNSAddress,
            migrationData.tokens,
            _maxGas,
            _gasPriceBid,
            data
        );

        subgraphData.reserveRatio = 0;
        _burnNFT(_subgraphID);
        emit SubgraphSentToL2(_subgraphID);
    }

    /**
     * @notice Deprecate a subgraph locked more than 256 blocks ago.
     * This allows curators to recover their funds if the subgraph was locked
     * for a migration to L2 but the subgraph was never actually sent to L2.
     * @param _subgraphID Subgraph ID
     */
    function deprecateLockedSubgraph(uint256 _subgraphID) external notPartialPaused {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];
        require(migrationData.lockedAtBlock > 0, "!LOCKED");
        require(migrationData.lockedAtBlock.add(256) < block.number, "TOO_EARLY");
        require(!migrationData.l1Done, "ALREADY_DONE");
        migrationData.l1Done = true;
        migrationData.deprecated = true;
        subgraphData.withdrawableGRT = migrationData.tokens;
        subgraphData.reserveRatio = 0;

        // Burn the NFT
        _burnNFT(_subgraphID);

        emit SubgraphDeprecated(_subgraphID, subgraphData.withdrawableGRT);
    }

    /**
     * @notice Claim the balance for a curator's signal in a subgraph that was
     * migrated to L2, by sending a retryable ticket to the L2GNS.
     * The balance will be claimed for a beneficiary address, as this method can be
     * used by curators that use a contract address in L1 that may not exist in L2.
     * @param _subgraphID Subgraph ID
     * @param _beneficiary Address that will receive the tokens in L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     * @return The sequence ID for the retryable ticket, as returned by the Arbitrum inbox.
     */
    function claimCuratorBalanceToBeneficiaryOnL2(
        uint256 _subgraphID,
        address _beneficiary,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable notPartialPaused returns (bytes memory) {
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];

        require(migrationData.l1Done, "!MIGRATED");
        require(!migrationData.deprecated, "SUBGRAPH_DEPRECATED");

        require(_maxSubmissionCost > 0, "NO_SUBMISSION_COST");

        {
            // makes sure only sufficient ETH is supplied required for successful redemption on L2
            // if a user does not desire immediate redemption they should provide
            // a msg.value of AT LEAST _maxSubmissionCost
            uint256 expectedEth = _maxSubmissionCost + (_maxGas * _gasPriceBid);
            require(msg.value >= expectedEth, "WRONG_ETH_VALUE");
        }
        L2GasParams memory gasParams = L2GasParams(_maxSubmissionCost, _maxGas, _gasPriceBid);

        bytes memory outboundCalldata = abi.encodeWithSelector(
            IL2GNS.claimL1CuratorBalanceToBeneficiary.selector,
            _subgraphID,
            msg.sender,
            getCuratorSignal(_subgraphID, msg.sender),
            _beneficiary
        );

        uint256 seqNum = sendTxToL2(
            arbitrumInboxAddress,
            counterpartGNSAddress,
            msg.sender,
            msg.value,
            0,
            gasParams,
            outboundCalldata
        );

        return abi.encode(seqNum);
    }

    /**
     * @dev Encodes the subgraph data as callhook parameters
     * for the L2 migration.
     * @param _subgraphID Subgraph ID
     * @param _migrationData Subgraph L2 migration data
     * @param _subgraphData Subgraph data
     */
    function _encodeSubgraphDataForL2(
        uint256 _subgraphID,
        SubgraphL2MigrationData storage _migrationData,
        SubgraphData storage _subgraphData
    ) internal view returns (bytes memory) {
        return
            abi.encode(
                _subgraphID,
                ownerOf(_subgraphID),
                blockhash(_migrationData.lockedAtBlock),
                _subgraphData.nSignal
            );
    }
}
