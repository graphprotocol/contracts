// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "../interfaces/internal/IHorizonStakingTypes.sol";

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
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract GraphPayments is Initializable, MulticallUpgradeable, GraphDirectory, IGraphPayments {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;
    uint256 public immutable PROTOCOL_PAYMENT_CUT;

    /**
     * @notice Constructor for the {GraphPayments} contract
     * @dev This contract is upgradeable however we still use the constructor to set
     * a few immutable variables.
     * @param controller The address of the Graph controller
     * @param protocolPaymentCut The protocol tax in PPM
     */
    constructor(address controller, uint256 protocolPaymentCut) GraphDirectory(controller) {
        require(PPMMath.isValidPPM(protocolPaymentCut), GraphPaymentsInvalidCut(protocolPaymentCut));
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
        uint256 dataServiceCut
    ) external {
        require(PPMMath.isValidPPM(dataServiceCut), GraphPaymentsInvalidCut(dataServiceCut));

        // Pull tokens from the sender
        _graphToken().pullTokens(msg.sender, tokens);

        // Calculate token amounts for each party
        // Order matters: protocol -> data service -> delegators -> receiver
        // Note the substractions should not underflow as we are only deducting a percentage of the remainder
        uint256 tokensRemaining = tokens;

        uint256 tokensProtocol = tokensRemaining.mulPPMRoundUp(PROTOCOL_PAYMENT_CUT);
        tokensRemaining = tokensRemaining - tokensProtocol;

        uint256 tokensDataService = tokensRemaining.mulPPMRoundUp(dataServiceCut);
        tokensRemaining = tokensRemaining - tokensDataService;

        uint256 tokensDelegationPool = 0;
        IHorizonStakingTypes.DelegationPool memory pool = _graphStaking().getDelegationPool(receiver, dataService);
        if (pool.shares > 0) {
            tokensDelegationPool = tokensRemaining.mulPPMRoundUp(
                _graphStaking().getDelegationFeeCut(receiver, dataService, paymentType)
            );
            tokensRemaining = tokensRemaining - tokensDelegationPool;
        }

        // Pay all parties
        _graphToken().burnTokens(tokensProtocol);

        _graphToken().pushTokens(dataService, tokensDataService);

        if (tokensDelegationPool > 0) {
            _graphToken().approve(address(_graphStaking()), tokensDelegationPool);
            _graphStaking().addToDelegationPool(receiver, dataService, tokensDelegationPool);
        }

        _graphToken().pushTokens(receiver, tokensRemaining);

        emit GraphPaymentCollected(
            paymentType,
            msg.sender,
            receiver,
            dataService,
            tokens,
            tokensProtocol,
            tokensDataService,
            tokensDelegationPool,
            tokensRemaining
        );
    }
}
