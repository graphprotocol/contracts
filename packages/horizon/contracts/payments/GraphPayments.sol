// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "../interfaces/IGraphToken.sol";
import { IHorizonStaking } from "../interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { GraphDirectory } from "../GraphDirectory.sol";
import { GraphPaymentsStorageV1Storage } from "./GraphPaymentsStorage.sol";
import { TokenUtils } from "../libraries/TokenUtils.sol";

contract GraphPayments is IGraphPayments, GraphPaymentsStorageV1Storage, GraphDirectory {
    uint256 private immutable MAX_PPM = 1000000; // 100% in parts per million
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
        protocolPaymentCut = protocolPaymentCut;
    }

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address receiver, // serviceProvider
        address dataService,
        uint256 amount,
        IGraphPayments.PaymentTypes paymentType,
        uint256 tokensDataService
    ) external {
        IGraphToken graphToken = IGraphToken(GRAPH_TOKEN);
        IHorizonStaking staking = IHorizonStaking(STAKING);
        TokenUtils.pullTokens(graphToken, msg.sender, amount);

        // Pay protocol cut
        uint256 tokensProtocol = (amount * PROTOCOL_PAYMENT_CUT) / MAX_PPM;
        TokenUtils.burnTokens(graphToken, tokensProtocol);

        // Pay data service cut
        TokenUtils.pushTokens(graphToken, dataService, tokensDataService);

        // Get delegation cut
        uint256 delegationFeeCut = staking.getDelegationFeeCut(receiver, dataService, uint8(paymentType));
        uint256 tokensDelegationPool = (amount * delegationFeeCut) / MAX_PPM;
        staking.addToDelegationPool(receiver, dataService, tokensDelegationPool);

        // Pay the rest to the receiver
        uint256 tokensReceiver = amount - tokensProtocol - tokensDataService - tokensDelegationPool;
        TokenUtils.pushTokens(graphToken, receiver, tokensReceiver);
    }
}
