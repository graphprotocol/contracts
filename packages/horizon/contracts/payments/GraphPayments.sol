// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "../libraries/PPMMath.sol";

import { GraphDirectory } from "../utilities/GraphDirectory.sol";

/**
 * @title GraphPayments contract
 * @notice This contract is part of the Graph Horizon payments protocol. It's designed
 * to pull funds (GRT) from the {PaymentsEscrow} and distribute them according to a
 * set of pre established rules.
 */
contract GraphPayments is Initializable, MulticallUpgradeable, GraphDirectory, IGraphPayments {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;
    uint256 public immutable PROTOCOL_PAYMENT_CUT;

    /**
     * @notice Constructor for the {GraphPayments} contract
     * @dev This contract is upgradeable however we stil use the constructor to set
     * a few immutable variables.
     * @param controller The address of the Graph controller
     * @param protocolPaymentCut The protocol tax in PPM
     */
    constructor(address controller, uint256 protocolPaymentCut) GraphDirectory(controller) {
        require(PPMMath.isValidPPM(protocolPaymentCut), GraphPaymentsInvalidProtocolPaymentCut(protocolPaymentCut));
        PROTOCOL_PAYMENT_CUT = protocolPaymentCut;
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     */
    function initialize() external initializer {
        __Multicall_init();
    }

    /**
     * @notice See {IGraphPayments-collect}
     */
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
            _graphToken().approve(address(_graphStaking()), tokensDelegationPool);
            _graphStaking().addToDelegationPool(receiver, dataService, tokensDelegationPool);
        }

        // Pay receiver
        uint256 tokensReceiverRemaining = tokens - totalCut;
        _graphToken().pushTokens(receiver, tokensReceiverRemaining);

        emit PaymentCollected(
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
