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
 * @title L1GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 * This L1GNS variant includes some functions to allow migrating subgraphs to L2.
 */
contract L1GNS is GNS, L1GNSV1Storage, L1ArbitrumMessenger {
    using SafeMathUpgradeable for uint256;

    /// @dev Emitted when a subgraph was sent to L2 through the bridge
    event SubgraphSentToL2(uint256 indexed _subgraphID, address indexed _l2Owner);
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
     * @notice Send a subgraph's data and tokens to L2.
     * Use the Arbitrum SDK to estimate the L2 retryable ticket parameters.
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
        require(!subgraphMigratedToL2[_subgraphID], "ALREADY_DONE");

        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);
        // This is just like onlySubgraphAuth, but we want it to run after the subgraphMigratedToL2 check
        // to revert with a nicer message in that case:
        require(ownerOf(_subgraphID) == msg.sender, "GNS: Must be authorized");
        subgraphMigratedToL2[_subgraphID] = true;

        uint256 curationTokens = curation().burn(
            subgraphData.subgraphDeploymentID,
            subgraphData.vSignal,
            0
        );
        subgraphData.disabled = true;
        subgraphData.vSignal = 0;

        bytes memory extraData = _encodeSubgraphDataForL2(_subgraphID, _l2Owner, subgraphData);

        bytes memory data = abi.encode(_maxSubmissionCost, extraData);
        IGraphToken grt = graphToken();
        ITokenGateway gateway = graphTokenGateway();
        grt.approve(address(gateway), curationTokens);
        gateway.outboundTransfer{ value: msg.value }({
            _token: address(grt),
            _to: counterpartGNSAddress,
            _amount: curationTokens,
            _maxGas: _maxGas,
            _gasPriceBid: _gasPriceBid,
            _data: data
        });

        subgraphData.reserveRatioDeprecated = 0;
        _burnNFT(_subgraphID);
        emit SubgraphSentToL2(_subgraphID, _l2Owner);
    }

    /**
     * @notice Claim the balance for a curator's signal in a subgraph that was
     * migrated to L2, by sending a retryable ticket to the L2GNS.
     * The balance will be claimed for a beneficiary address, as this method can be
     * used by curators that use a contract address in L1 that may not exist in L2.
     * This will set the curator's signal on L1 to zero, so the caller must ensure
     * that the retryable ticket is redeemed before expiration, or the signal will be lost.
     * @dev Use the Arbitrum SDK to estimate the L2 retryable ticket parameters.
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
        require(subgraphMigratedToL2[_subgraphID], "!MIGRATED");

        // The Arbitrum bridge will check this too, we just check here for an early exit
        require(_maxSubmissionCost != 0, "NO_SUBMISSION_COST");

        L2GasParams memory gasParams = L2GasParams(_maxSubmissionCost, _maxGas, _gasPriceBid);

        uint256 curatorNSignal = getCuratorSignal(_subgraphID, msg.sender);
        require(curatorNSignal != 0, "NO_SIGNAL");
        bytes memory outboundCalldata = getClaimCuratorBalanceOutboundCalldata(
            _subgraphID,
            curatorNSignal,
            msg.sender,
            _beneficiary
        );

        // Similarly to withdrawing from a deprecated subgraph,
        // we remove the curator's signal from the subgraph.
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[msg.sender] = 0;
        subgraphData.nSignal = subgraphData.nSignal.sub(curatorNSignal);

        uint256 seqNum = sendTxToL2({
            _inbox: arbitrumInboxAddress,
            _to: counterpartGNSAddress,
            _user: msg.sender,
            _l1CallValue: msg.value,
            _l2CallValue: 0,
            _l2GasParams: gasParams,
            _data: outboundCalldata
        });

        return abi.encode(seqNum);
    }

    /**
     * @notice Get the outbound calldata that will be sent to L2
     * when calling claimCuratorBalanceToBeneficiaryOnL2.
     * This can be useful to estimate the L2 retryable ticket parameters.
     * @param _subgraphID Subgraph ID
     * @param _curatorNSignal Curator's signal in the subgraph
     * @param _curator Curator address
     * @param _beneficiary Address that will own the signal in L2
     */
    function getClaimCuratorBalanceOutboundCalldata(
        uint256 _subgraphID,
        uint256 _curatorNSignal,
        address _curator,
        address _beneficiary
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IL2GNS.claimL1CuratorBalanceToBeneficiary.selector,
                _subgraphID,
                _curator,
                _curatorNSignal,
                _beneficiary
            );
    }

    /**
     * @dev Encodes the subgraph data as callhook parameters
     * for the L2 migration.
     * @param _subgraphID Subgraph ID
     * @param _l2Owner Owner of the subgraph on L2
     * @param _subgraphData Subgraph data
     */
    function _encodeSubgraphDataForL2(
        uint256 _subgraphID,
        address _l2Owner,
        SubgraphData storage _subgraphData
    ) internal view returns (bytes memory) {
        return abi.encode(_subgraphID, _l2Owner, _subgraphData.nSignal);
    }
}
