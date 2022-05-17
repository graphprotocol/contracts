// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../arbitrum/L1ArbitrumMessenger.sol";
import "./GraphTokenGateway.sol";

/**
 * @title L1 Graph Token Gateway Contract
 * @dev Provides the L1 side of the Ethereum-Arbitrum GRT bridge. Sends GRT to the L2 chain
 * by escrowing them and sending a message to the L2 gateway, and receives tokens from L2 by
 * releasing them from escrow.
 * Based on Offchain Labs' reference implementation and Livepeer's arbitrum-lpt-bridge
 * (See: https://github.com/OffchainLabs/arbitrum/tree/master/packages/arb-bridge-peripherals/contracts/tokenbridge
 * and https://github.com/livepeer/arbitrum-lpt-bridge)
 */
contract L1GraphTokenGateway is GraphTokenGateway, L1ArbitrumMessenger {
    using SafeMath for uint256;

    // Address of the Graph Token contract on L2
    address public l2GRT;
    // Address of the Arbitrum Inbox
    address public inbox;
    // Address of the Arbitrum Gateway Router on L1
    address public l1Router;
    // Address of the L2GraphTokenGateway on L2 that is the counterpart of this gateway
    address public l2Counterpart;
    // Address of the BridgeEscrow contract that holds the GRT in the bridge
    address public escrow;
    // Address of the L1 Reservoir that is the only sender allowed to send extra data
    mapping(address => bool) public callhookWhitelist;

    // Emitted when an outbound transfer is initiated, i.e. tokens are deposited from L1 to L2
    event DepositInitiated(
        address _l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );

    // Emitted when an incoming transfer is finalized, i.e tokens are withdrawn from L2 to L1
    event WithdrawalFinalized(
        address _l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _exitNum,
        uint256 _amount
    );

    // Emitted when the Arbitrum Inbox and Gateway Router addresses have been updated
    event ArbitrumAddressesSet(address _inbox, address _l1Router);
    // Emitted when the L2 GRT address has been updated
    event L2TokenAddressSet(address _l2GRT);
    // Emitted when the counterpart L2GraphTokenGateway address has been updated
    event L2CounterpartAddressSet(address _l2Counterpart);
    // Emitted when the escrow address has been updated
    event EscrowAddressSet(address _escrow);
    // Emitted when an address is added to the callhook whitelist
    event AddedToCallhookWhitelist(address newWhitelisted);
    // Emitted when an address is removed from the callhook whitelist
    event RemovedFromCallhookWhitelist(address notWhitelisted);

    /**
     * @dev Allows a function to be called only by the gateway's L2 counterpart.
     * The message will actually come from the Arbitrum Bridge, but the Outbox
     * can tell us who the sender from L2 is.
     */
    modifier onlyL2Counterpart() {
        // a message coming from the counterpart gateway was executed by the bridge
        IBridge bridge = IInbox(inbox).bridge();
        require(msg.sender == address(bridge), "NOT_FROM_BRIDGE");

        // and the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = IOutbox(bridge.activeOutbox()).l2ToL1Sender();
        require(l2ToL1Sender == l2Counterpart, "ONLY_COUNTERPART_GATEWAY");
        _;
    }

    /**
     * @dev Initialize this contract.
     * The contract will be paused.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
        _paused = true;
    }

    /**
     * @dev sets the addresses for L1 contracts provided by Arbitrum
     * @param _inbox Address of the Inbox that is part of the Arbitrum Bridge
     * @param _l1Router Address of the Gateway Router
     */
    function setArbitrumAddresses(address _inbox, address _l1Router) external onlyGovernor {
        inbox = _inbox;
        l1Router = _l1Router;
        emit ArbitrumAddressesSet(_inbox, _l1Router);
    }

    /**
     * @dev Sets the address of the L2 Graph Token
     * @param _l2GRT Address of the GRT contract on L2
     */
    function setL2TokenAddress(address _l2GRT) external onlyGovernor {
        l2GRT = _l2GRT;
        emit L2TokenAddressSet(_l2GRT);
    }

    /**
     * @dev Sets the address of the counterpart gateway on L2
     * @param _l2Counterpart Address of the corresponding L2GraphTokenGateway on Arbitrum
     */
    function setL2CounterpartAddress(address _l2Counterpart) external onlyGovernor {
        l2Counterpart = _l2Counterpart;
        emit L2CounterpartAddressSet(_l2Counterpart);
    }

    /**
     * @dev Sets the address of the escrow contract on L1
     * @param _escrow Address of the BridgeEscrow
     */
    function setEscrowAddress(address _escrow) external onlyGovernor {
        escrow = _escrow;
        emit EscrowAddressSet(_escrow);
    }

    /**
     * @dev Adds an address to the callhook whitelist.
     * This address will be allowed to include callhooks when transferring tokens.
     * @param newWhitelisted Address to add to the whitelist
     */
    function addToCallhookWhitelist(address newWhitelisted) external onlyGovernor {
        callhookWhitelist[newWhitelisted] = true;
        emit AddedToCallhookWhitelist(newWhitelisted);
    }

    /**
     * @dev Removes an address from the callhook whitelist.
     * This address will no longer be allowed to include callhooks when transferring tokens.
     * @param notWhitelisted Address to remove from the whitelist
     */
    function removeFromCallhookWhitelist(address notWhitelisted) external onlyGovernor {
        callhookWhitelist[notWhitelisted] = false;
        emit RemovedFromCallhookWhitelist(notWhitelisted);
    }

    /**
     * @notice Creates and sends a retryable ticket to transfer GRT to L2 using the Arbitrum Inbox.
     * The tokens are escrowed by the gateway until they are withdrawn back to L1.
     * The ticket must be redeemed on L2 to receive tokens at the specified address.
     * @dev maxGas and gasPriceBid must be set using Arbitrum's NodeInterface.estimateRetryableTicket method.
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L2
     * @param _amount Amount of tokens to tranfer
     * @param _maxGas Gas limit for L2 execution of the ticket
     * @param _gasPriceBid Price per gas on L2
     * @param _data Encoded maxSubmissionCost and sender address along with additional calldata
     * @return Sequence number of the retryable ticket created by Inbox
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable override notPaused returns (bytes memory) {
        IGraphToken token = graphToken();
        require(_l1Token == address(token), "TOKEN_NOT_GRT");
        require(_amount > 0, "INVALID_ZERO_AMOUNT");

        // nested scopes to avoid stack too deep errors
        address from;
        uint256 seqNum;
        {
            uint256 maxSubmissionCost;
            bytes memory outboundCalldata;
            {
                bytes memory extraData;
                (from, maxSubmissionCost, extraData) = parseOutboundData(_data);
                require(
                    extraData.length == 0 || callhookWhitelist[msg.sender] == true,
                    "CALL_HOOK_DATA_NOT_ALLOWED"
                );
                require(maxSubmissionCost > 0, "NO_SUBMISSION_COST");

                {
                    // makes sure only sufficient ETH is supplied required for successful redemption on L2
                    // if a user does not desire immediate redemption they should provide
                    // a msg.value of AT LEAST maxSubmissionCost
                    uint256 expectedEth = maxSubmissionCost + (_maxGas * _gasPriceBid);
                    require(msg.value == expectedEth, "WRONG_ETH_VALUE");
                }
                outboundCalldata = getOutboundCalldata(_l1Token, from, _to, _amount, extraData);
            }
            {
                L2GasParams memory gasParams = L2GasParams(
                    maxSubmissionCost,
                    _maxGas,
                    _gasPriceBid
                );
                // transfer tokens to escrow
                token.transferFrom(from, escrow, _amount);
                seqNum = sendTxToL2(
                    inbox,
                    l2Counterpart,
                    from,
                    msg.value,
                    0,
                    gasParams,
                    outboundCalldata
                );
            }
        }
        emit DepositInitiated(_l1Token, from, _to, seqNum, _amount);

        return abi.encode(seqNum);
    }

    /**
     * @notice Receives withdrawn tokens from L2
     * The equivalent tokens are released from escrow and sent to the destination.
     * @dev can only accept transactions coming from the L2 GRT Gateway
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _from Address of the sender
     * @param _to Recepient address on L1
     * @param _amount Amount of tokens transferred
     * @param _data Contains exitNum which is always set to 0
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable override notPaused onlyL2Counterpart {
        IGraphToken token = graphToken();
        require(_l1Token == address(token), "TOKEN_NOT_GRT");
        (uint256 exitNum, ) = abi.decode(_data, (uint256, bytes));

        uint256 escrowBalance = token.balanceOf(escrow);
        // If the bridge doesn't have enough tokens, something's very wrong!
        require(_amount <= escrowBalance, "BRIDGE_OUT_OF_FUNDS");
        token.transferFrom(escrow, _to, _amount);

        emit WithdrawalFinalized(_l1Token, _from, _to, exitNum, _amount);
    }

    /**
     * @notice decodes calldata required for migration of tokens
     * @dev data must include maxSubmissionCost, extraData can be left empty. When the router
     * sends an outbound message, data also contains the from address.
     * @param data encoded callhook data
     * @return from sender of the tx
     * @return maxSubmissionCost base ether value required to keep retyrable ticket alive
     * @return extraData any other data sent to L2
     */
    function parseOutboundData(bytes memory data)
        private
        view
        returns (
            address from,
            uint256 maxSubmissionCost,
            bytes memory extraData
        )
    {
        if (msg.sender == l1Router) {
            // Data encoded by the Gateway Router includes the sender address
            (from, extraData) = abi.decode(data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = data;
        }
        // User-encoded data contains the max retryable ticket submission cost
        // and additional L2 calldata
        (maxSubmissionCost, extraData) = abi.decode(extraData, (uint256, bytes));
    }

    /**
     * @notice Creates calldata required to create a retryable ticket
     * @dev encodes the target function with its params which
     * will be called on L2 when the retryable ticket is redeemed
     * @param l1Token Address of the Graph token contract on L1
     * @param from Address on L1 from which we're transferring tokens
     * @param to Address on L2 to which we're transferring tokens
     * @param amount Amount of GRT to transfer
     * @param data Additional call data for the L2 transaction, which must be empty
     * @return outboundCalldata Encoded calldata (including function selector) for the L2 transaction
     */
    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public pure returns (bytes memory outboundCalldata) {
        bytes memory emptyBytes;

        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            l1Token,
            from,
            to,
            amount,
            abi.encode(emptyBytes, data)
        );
    }

    /**
     * @notice Calculate the L2 address of a bridged token
     * @dev In our case, this would only work for GRT.
     * @param l1ERC20 address of L1 GRT contract
     * @return L2 address of the bridged GRT token
     */
    function calculateL2TokenAddress(address l1ERC20) external view override returns (address) {
        IGraphToken token = graphToken();
        if (l1ERC20 != address(token)) {
            return address(0);
        }
        return l2GRT;
    }
}
