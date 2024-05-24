// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "../libraries/PPMMath.sol";

import { GraphDirectory } from "../data-service/GraphDirectory.sol";
import { GraphPaymentsStorageV1Storage } from "./GraphPaymentsStorage.sol";

contract GraphPayments is Multicall, GraphDirectory, GraphPaymentsStorageV1Storage, IGraphPayments {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;

    event GraphPaymentsCollected(
        address indexed sender,
        address indexed receiver,
        address indexed dataService,
        uint256 tokensReceiver,
        uint256 tokensDelegationPool,
        uint256 tokensDataService,
        uint256 tokensProtocol
    );

    // -- Events --

    // -- Modifier --

    // -- Parameters --

    // -- Constructor --

    constructor(address controller, uint256 protocolPaymentCut) GraphDirectory(controller) {
        PROTOCOL_PAYMENT_CUT = protocolPaymentCut;
    }

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external {
        _graphToken().pullTokens(msg.sender, tokens);

        // Calculate cuts
        uint256 tokensProtocol = tokens.mulPPM(PROTOCOL_PAYMENT_CUT);
        uint256 delegationFeeCut = _graphStaking().getDelegationFeeCut(receiver, dataService, paymentType);
        uint256 tokensDelegationPool = tokens.mulPPM(delegationFeeCut);
        uint256 totalCut = tokensProtocol + tokensDataService + tokensDelegationPool;
        require(tokens >= totalCut, GraphPaymentsInsufficientTokens(tokens, totalCut));

        // Pay protocol cut
        _graphToken().burnTokens(tokensProtocol);

        // Pay data service cut
        _graphToken().pushTokens(dataService, tokensDataService);

        // Pay delegators
        if (tokensDelegationPool > 0) {
            _graphStaking().addToDelegationPool(receiver, dataService, tokensDelegationPool);
        }

        // Pay receiver
        uint256 tokensReceiverRemaining = tokens - totalCut;
        _graphToken().pushTokens(receiver, tokensReceiverRemaining);

        emit GraphPaymentsCollected(
            msg.sender,
            receiver,
            dataService,
            tokensReceiverRemaining,
            tokensDelegationPool,
            tokensDataService,
            tokensProtocol
        );
    }
}
