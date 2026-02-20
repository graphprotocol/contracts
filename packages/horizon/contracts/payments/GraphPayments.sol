// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27 || 0.8.33;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable function-max-lines

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "../libraries/PPMMath.sol";

import { GraphDirectory } from "../utilities/GraphDirectory.sol";

/**
 * @title GraphPayments contract
 * @author Edge & Node
 * @notice This contract is part of the Graph Horizon payments protocol. It's designed
 * to pull funds (GRT) from the {PaymentsEscrow} and distribute them according to a
 * set of pre established rules.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract GraphPayments is Initializable, MulticallUpgradeable, GraphDirectory, IGraphPayments {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;

    /// @notice Protocol payment cut in PPM
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

    /// @inheritdoc IGraphPayments
    function initialize() external initializer {
        __Multicall_init();
    }

    /// @inheritdoc IGraphPayments
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination
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

        if (tokensRemaining > 0) {
            if (receiverDestination == address(0)) {
                _graphToken().approve(address(_graphStaking()), tokensRemaining);
                _graphStaking().stakeTo(receiver, tokensRemaining);
            } else {
                _graphToken().pushTokens(receiverDestination, tokensRemaining);
            }
        }

        emit GraphPaymentCollected(
            paymentType,
            msg.sender,
            receiver,
            dataService,
            tokens,
            tokensProtocol,
            tokensDataService,
            tokensDelegationPool,
            tokensRemaining,
            receiverDestination
        );
    }
}
