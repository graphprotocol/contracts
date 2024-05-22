// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "../interfaces/IGraphToken.sol";
import { IHorizonStaking } from "../interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { TokenUtils } from "../libraries/TokenUtils.sol";

import { GraphDirectory } from "../data-service/GraphDirectory.sol";
import { GraphPaymentsStorageV1Storage } from "./GraphPaymentsStorage.sol";

contract GraphPayments is Multicall, GraphDirectory, GraphPaymentsStorageV1Storage, IGraphPayments {
    using TokenUtils for IGraphToken;

    uint256 private immutable MAX_PPM = 1000000; // 100% in parts per million

    event GraphPaymentsCollected(
        address indexed sender,
        address indexed receiver,
        address indexed dataService,
        uint256 tokensReceiver,
        uint256 tokensDelegationPool,
        uint256 tokensDataService,
        uint256 tokensProtocol
    );

    // -- Errors --

    error GraphPaymentsNotThawing();
    error GraphPaymentsStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);
    error GraphPaymentsCollectorNotAuthorized(address sender, address dataService);
    error GraphPaymentsCollectorInsufficientAmount(uint256 available, uint256 required);

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

        // Pay protocol cut
        uint256 tokensProtocol = (tokens * PROTOCOL_PAYMENT_CUT) / MAX_PPM;
        _graphToken().burnTokens(tokensProtocol);

        // Pay data service cut
        _graphToken().pushTokens(dataService, tokensDataService);

        // Get delegation cut
        uint256 delegationFeeCut = _graphStaking().getDelegationFeeCut(receiver, dataService, uint8(paymentType));
        uint256 tokensDelegationPool = (tokens * delegationFeeCut) / MAX_PPM;
        if (tokensDelegationPool > 0) {
            _graphStaking().addToDelegationPool(receiver, dataService, tokensDelegationPool);
        }

        // Pay the rest to the receiver
        uint256 tokensReceiverRemaining = tokens - tokensProtocol - tokensDataService - tokensDelegationPool;
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
