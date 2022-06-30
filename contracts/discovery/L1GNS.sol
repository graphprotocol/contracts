// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./GNS.sol";
import "./GNSStorage.sol";
import "./L1GNSStorage.sol";

import "../arbitrum/ITokenGateway.sol";
import "../arbitrum/L1ArbitrumMessenger.sol";
import "../l2/discovery/L2GNS.sol";

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
    using SafeMath for uint256;

    event SubgraphLockedForMigrationToL2(uint256 _subgraphID);
    event SubgraphSentToL2(uint256 _subgraphID);
    event ArbitrumInboxAddressUpdated(address _inbox);

    /**
     * @dev sets the addresses for L1 inbox provided by Arbitrum
     * @param _inbox Address of the Inbox that is part of the Arbitrum Bridge
     */
    function setArbitrumInboxAddress(address _inbox) external onlyGovernor {
        arbitrumInboxAddress = _inbox;
        emit ArbitrumInboxAddressUpdated(_inbox);
    }

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
        // This can only be done for subgraphs that have nonzero signal.
        require(subgraphData.nSignal > 0, "!SIGNAL");

        // Burn all version signal in the name pool for tokens (w/no slippage protection)
        // Sell all signal from the old deployment
        migrationData.tokens = curation().burn(
            subgraphData.subgraphDeploymentID,
            subgraphData.vSignal,
            1 // We do check that the output must be nonzero...
        );

        subgraphData.disabled = true;
        subgraphData.vSignal = 0;

        migrationData.lockedAtBlock = block.number;
        emit SubgraphLockedForMigrationToL2(_subgraphID);
    }

    /**
     * @dev Send a subgraph's data and tokens to L2.
     * The subgraph must be locked using lockSubgraphForMigrationToL2 in a previous block
     * (less than 256 blocks ago).
     */
    function sendSubgraphToL2(
        uint256 _subgraphID,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable notPartialPaused onlySubgraphAuth(_subgraphID) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];
        require(
            migrationData.lockedAtBlock > 0 &&
                migrationData.lockedAtBlock >= block.number.sub(255) &&
                migrationData.lockedAtBlock < block.number,
            "!LOCKED"
        );
        require(!migrationData.l1Done, "ALREADY_DONE");
        migrationData.l1Done = true;

        bytes memory extraData = encodeSubgraphMetadataForL2(
            _subgraphID,
            migrationData,
            subgraphData
        );

        bytes memory data = abi.encode(maxSubmissionCost, extraData);
        IGraphToken grt = graphToken();
        ITokenGateway gateway = ITokenGateway(_resolveContract(keccak256("GraphTokenGateway")));
        grt.approve(address(gateway), migrationData.tokens);
        gateway.outboundTransfer{ value: msg.value }(
            address(grt),
            counterpartGNSAddress,
            migrationData.tokens,
            maxGas,
            gasPriceBid,
            data
        );

        subgraphData.reserveRatio = 0;
        _burnNFT(_subgraphID);
        emit SubgraphSentToL2(_subgraphID);
    }

    function encodeSubgraphMetadataForL2(
        uint256 _subgraphID,
        SubgraphL2MigrationData storage migrationData,
        SubgraphData storage subgraphData
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                L2GNS.receiveSubgraphFromL1.selector,
                _subgraphID,
                ownerOf(_subgraphID),
                migrationData.tokens,
                blockhash(migrationData.lockedAtBlock),
                subgraphData.nSignal,
                subgraphData.reserveRatio,
                subgraphNFT.getSubgraphMetadata(_subgraphID)
            );
    }

    /**
     * @dev Deprecate a subgraph locked more than 256 blocks ago.
     * This allows curators to recover their funds if the subgraph was locked
     * for a migration to L2 but the subgraph was never actually sent to L2.
     */
    function deprecateLockedSubgraph(uint256 _subgraphID) external notPartialPaused {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];
        require(
            migrationData.lockedAtBlock > 0 && migrationData.lockedAtBlock < block.number.sub(256),
            "!LOCKED"
        );
        require(!migrationData.l1Done, "ALREADY_DONE");
        migrationData.l1Done = true;

        subgraphData.withdrawableGRT = migrationData.tokens;
        subgraphData.reserveRatio = 0;

        // Burn the NFT
        _burnNFT(_subgraphID);

        emit SubgraphDeprecated(_subgraphID, subgraphData.withdrawableGRT);
    }

    function claimCuratorBalanceToBeneficiaryOnL2(
        uint256 _subgraphID,
        address _beneficiary,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable notPartialPaused returns (bytes memory) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        SubgraphL2MigrationData storage migrationData = subgraphL2MigrationData[_subgraphID];

        require(migrationData.l1Done, "!MIGRATED");
        require(subgraphData.withdrawableGRT == 0, "DEPRECATED");

        require(_maxSubmissionCost > 0, "NO_SUBMISSION_COST");

        {
            // makes sure only sufficient ETH is supplied required for successful redemption on L2
            // if a user does not desire immediate redemption they should provide
            // a msg.value of AT LEAST maxSubmissionCost
            uint256 expectedEth = _maxSubmissionCost + (_maxGas * _gasPriceBid);
            require(msg.value == expectedEth, "WRONG_ETH_VALUE");
        }
        L2GasParams memory gasParams = L2GasParams(_maxSubmissionCost, _maxGas, _gasPriceBid);

        bytes memory outboundCalldata = abi.encodeWithSelector(
            L2GNS.claimL1CuratorBalanceToBeneficiary.selector,
            _subgraphID,
            msg.sender,
            subgraphData.curatorNSignal[msg.sender],
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
}
