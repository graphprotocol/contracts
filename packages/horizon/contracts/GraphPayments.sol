// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { GraphDirectory } from "./GraphDirectory.sol";
import { GraphPaymentsStorageV1Storage } from "./GraphPaymentsStorage.sol";

contract GraphPayments is IGraphPayments, GraphPaymentsStorageV1Storage, GraphDirectory {
    // -- Errors --

    error GraphPaymentsNotThawing();
    error GraphPaymentsStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);
    error GraphPaymentsCollectorNotAuthorized(address sender, address dataService);

    // -- Events --

    event AuthorizedCollector(address indexed sender, address indexed dataService);
    event ThawCollector(address indexed sender, address indexed dataService);
    event CancelThawCollector(address indexed sender, address indexed dataService);
    event RevokeCollector(address indexed sender, address indexed dataService);

    // -- Modifier --

    // -- Parameters --

    uint256 private immutable MAX_PPM = 1000000; // 100% in parts per million

    // -- Constructor --

    constructor(
        address _controller,
        uint256 _revokeCollectorThawingPeriod,
        uint256 _protocolPaymentCut
    ) GraphDirectory(_controller) {
        revokeCollectorThawingPeriod = _revokeCollectorThawingPeriod;
        protocolPaymentCut = _protocolPaymentCut;
    }

    // approve a data service to collect funds
    function approveCollector(address dataService) external {
        authorizedCollectors[msg.sender][dataService].authorized = true;
        emit AuthorizedCollector(msg.sender, dataService);
    }

    // thaw a data service's collector authorization
    function thawCollector(address dataService) external {
        authorizedCollectors[msg.sender][dataService].thawEndTimestamp = block.timestamp + revokeCollectorThawingPeriod;
        emit ThawCollector(msg.sender, dataService);
    }

    // cancel thawing a data service's collector authorization
    function cancelThawCollector(address dataService) external {
        authorizedCollectors[msg.sender][dataService].thawEndTimestamp = 0;
        emit CancelThawCollector(msg.sender, dataService);
    }

    // revoke authorized collector
    function revokeCollector(address dataService) external {
        Collector storage collector = authorizedCollectors[msg.sender][dataService];

        if (collector.thawEndTimestamp == 0) {
            revert GraphPaymentsNotThawing();
        }

        if (collector.thawEndTimestamp > block.timestamp) {
            revert GraphPaymentsStillThawing(block.timestamp, collector.thawEndTimestamp);
        }

        delete authorizedCollectors[msg.sender][dataService];
        emit RevokeCollector(msg.sender, dataService);
    }

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address sender,
        address receiver, // serviceProvider
        uint256 amount,
        IGraphPayments.PaymentType paymentType,
        uint256 dataServiceCut
    ) external {
        Collector storage collector = authorizedCollectors[sender][msg.sender];

        if (!collector.authorized) {
            revert GraphPaymentsCollectorNotAuthorized(sender, msg.sender);
        }

        // Collect tokens from GraphEscrow
        graphEscrow.collect(sender, receiver, amount);

        // Pay protocol cut
        uint256 protocolCut = (amount * protocolPaymentCut) / MAX_PPM;
        graphToken.burn(protocolCut);

        // Pay data service cut
        uint256 dataServicePayment = (amount * dataServiceCut) / MAX_PPM;
        graphToken.transfer(msg.sender, dataServicePayment);

        // Get delegation cut
        (address delegatorAddress, uint256 delegatorCut) = graphStaking.getDelegatorCut(receiver, uint256(paymentType));
        uint256 delegatorPayment = (amount * delegatorCut) / MAX_PPM;
        graphToken.transfer(delegatorAddress, delegatorPayment);

        // Pay the rest to the receiver
        uint256 receiverPayment = amount - protocolCut - dataServicePayment - delegatorPayment;
        graphToken.transfer(receiver, receiverPayment);
    }
}
