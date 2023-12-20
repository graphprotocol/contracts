// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { GNS } from "./GNS.sol";

import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { IL2GNS } from "../l2/discovery/IL2GNS.sol";
import { IGraphToken } from "../token/IGraphToken.sol";
import { L1GNSV1Storage } from "./L1GNSStorage.sol";

/**
 * @title L1GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 * This L1GNS variant includes some functions to allow transferring subgraphs to L2.
 */
contract L1GNS is GNS, L1GNSV1Storage {
    using SafeMathUpgradeable for uint256;

    /// @dev Emitted when a subgraph was sent to L2 through the bridge
    event SubgraphSentToL2(
        uint256 indexed _subgraphID,
        address indexed _l1Owner,
        address indexed _l2Owner,
        uint256 _tokens
    );

    /// @dev Emitted when a curator's balance for a subgraph was sent to L2
    event CuratorBalanceSentToL2(
        uint256 indexed _subgraphID,
        address indexed _l1Curator,
        address indexed _l2Beneficiary,
        uint256 _tokens
    );

    /**
     * @notice Send a subgraph's data and tokens to L2.
     * Use the Arbitrum SDK to estimate the L2 retryable ticket parameters.
     * Note that any L2 gas/fee refunds will be lost, so the function only accepts
     * the exact amount of ETH to cover _maxSubmissionCost + _maxGas * _gasPriceBid.
     * @param _subgraphID Subgraph ID
     * @param _l2Owner Address that will own the subgraph in L2 (could be the L1 owner, but could be different if the L1 owner is an L1 contract)
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function sendSubgraphToL2(
        uint256 _subgraphID,
        address _l2Owner,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable notPartialPaused {
        require(!subgraphTransferredToL2[_subgraphID], "ALREADY_DONE");
        require(
            msg.value == _maxSubmissionCost.add(_maxGas.mul(_gasPriceBid)),
            "INVALID_ETH_VALUE"
        );

        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);
        // This is just like onlySubgraphAuth, but we want it to run after the subgraphTransferredToL2 check
        // to revert with a nicer message in that case:
        require(ownerOf(_subgraphID) == msg.sender, "GNS: Must be authorized");
        subgraphTransferredToL2[_subgraphID] = true;

        uint256 curationTokens = curation().burn(
            subgraphData.subgraphDeploymentID,
            subgraphData.vSignal,
            0
        );
        subgraphData.disabled = true;
        subgraphData.vSignal = 0;

        // We send only the subgraph owner's tokens and nsignal to L2,
        // and for everyone else we set the withdrawableGRT so that they can choose
        // to withdraw or transfer their signal.
        uint256 ownerNSignal = subgraphData.curatorNSignal[msg.sender];
        uint256 totalSignal = subgraphData.nSignal;

        // Get owner share of tokens to be sent to L2
        uint256 tokensForL2 = ownerNSignal.mul(curationTokens).div(totalSignal);
        // This leaves the subgraph as if it was deprecated,
        // so other curators can withdraw:
        subgraphData.curatorNSignal[msg.sender] = 0;
        subgraphData.nSignal = totalSignal.sub(ownerNSignal);
        subgraphData.withdrawableGRT = curationTokens.sub(tokensForL2);

        bytes memory extraData = abi.encode(
            uint8(IL2GNS.L1MessageCodes.RECEIVE_SUBGRAPH_CODE),
            _subgraphID,
            _l2Owner
        );

        _sendTokensAndMessageToL2GNS(
            tokensForL2,
            _maxGas,
            _gasPriceBid,
            _maxSubmissionCost,
            extraData
        );

        subgraphData.__DEPRECATED_reserveRatio = 0;
        _burnNFT(_subgraphID);
        emit SubgraphSentToL2(_subgraphID, msg.sender, _l2Owner, tokensForL2);
    }

    /**
     * @notice Send the balance for a curator's signal in a subgraph that was
     * transferred to L2, using the L1GraphTokenGateway.
     * The balance will be claimed for a beneficiary address, as this method can be
     * used by curators that use a contract address in L1 that may not exist in L2.
     * This will set the curator's signal on L1 to zero, so the caller must ensure
     * that the retryable ticket is redeemed before expiration, or the signal will be lost.
     * It is up to the caller to verify that the subgraph transfer was finished in L2,
     * but if it wasn't, the tokens will be sent to the beneficiary in L2.
     * Note that any L2 gas/fee refunds will be lost, so the function only accepts
     * the exact amount of ETH to cover _maxSubmissionCost + _maxGas * _gasPriceBid.
     * @dev Use the Arbitrum SDK to estimate the L2 retryable ticket parameters.
     * @param _subgraphID Subgraph ID
     * @param _beneficiary Address that will receive the tokens in L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function sendCuratorBalanceToBeneficiaryOnL2(
        uint256 _subgraphID,
        address _beneficiary,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable notPartialPaused {
        require(subgraphTransferredToL2[_subgraphID], "!TRANSFERRED");
        require(
            msg.value == _maxSubmissionCost.add(_maxGas.mul(_gasPriceBid)),
            "INVALID_ETH_VALUE"
        );
        // The Arbitrum bridge will check this too, we just check here for an early exit
        require(_maxSubmissionCost != 0, "NO_SUBMISSION_COST");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        uint256 curatorNSignal = subgraphData.curatorNSignal[msg.sender];
        require(curatorNSignal != 0, "NO_SIGNAL");
        uint256 subgraphNSignal = subgraphData.nSignal;
        require(subgraphNSignal != 0, "NO_SUBGRAPH_SIGNAL");

        uint256 withdrawableGRT = subgraphData.withdrawableGRT;
        uint256 tokensForL2 = curatorNSignal.mul(withdrawableGRT).div(subgraphNSignal);
        bytes memory extraData = abi.encode(
            uint8(IL2GNS.L1MessageCodes.RECEIVE_CURATOR_BALANCE_CODE),
            _subgraphID,
            _beneficiary
        );

        // Set the subgraph as if the curator had withdrawn their tokens
        subgraphData.curatorNSignal[msg.sender] = 0;
        subgraphData.nSignal = subgraphNSignal.sub(curatorNSignal);
        subgraphData.withdrawableGRT = withdrawableGRT.sub(tokensForL2);

        // Send the tokens and data to L2 using the L1GraphTokenGateway
        _sendTokensAndMessageToL2GNS(
            tokensForL2,
            _maxGas,
            _gasPriceBid,
            _maxSubmissionCost,
            extraData
        );
        emit CuratorBalanceSentToL2(_subgraphID, msg.sender, _beneficiary, tokensForL2);
    }

    /**
     * @notice Sends a message to the L2GNS with some extra data,
     * also sending some tokens, using the L1GraphTokenGateway.
     * @param _tokens Amount of tokens to send to L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     * @param _extraData Extra data for the callhook on L2GNS
     */
    function _sendTokensAndMessageToL2GNS(
        uint256 _tokens,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        bytes memory _extraData
    ) internal {
        bytes memory data = abi.encode(_maxSubmissionCost, _extraData);
        IGraphToken grt = graphToken();
        ITokenGateway gateway = graphTokenGateway();
        grt.approve(address(gateway), _tokens);
        gateway.outboundTransfer{ value: msg.value }(
            address(grt),
            counterpartGNSAddress,
            _tokens,
            _maxGas,
            _gasPriceBid,
            data
        );
    }
}
