// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../arbitrum/L2ArbitrumMessenger.sol";
import "../../gateway/GraphTokenGateway.sol";
import "../token/L2GraphToken.sol";

/**
 * @title L2 Graph Token Gateway Contract
 * @dev Provides the L2 side of the Ethereum-Arbitrum GRT bridge. Receives GRT from the L1 chain
 * and mints them on the L2 side. Sending GRT back to L1 by burning them on the L2 side.
 * Based on Offchain Labs' reference implementation and Livepeer's arbitrum-lpt-bridge
 * (See: https://github.com/OffchainLabs/arbitrum/tree/master/packages/arb-bridge-peripherals/contracts/tokenbridge
 * and https://github.com/livepeer/arbitrum-lpt-bridge)
 */
contract L2GraphTokenGateway is GraphTokenGateway, L2ArbitrumMessenger {
    using SafeMath for uint256;

    // Offset applied by the bridge to L1 addresses sending messages to L2
    uint160 internal constant L2_ADDRESS_OFFSET =
        uint160(0x1111000000000000000000000000000000001111);

    // Address of the Graph Token contract on L1
    address public l1GRT;
    // Address of the L1GraphTokenGateway that is the counterpart of this gateway on L1
    address public l1Counterpart;
    // Address of the Arbitrum Gateway Router on L2
    address public l2Router;
    // Addresses in L1 that are whitelisted to have callhooks on transfers
    mapping(address => bool) public callhookWhitelist;
    // Calldata included in an outbound transfer, stored as a structure for convenience and stack depth
    struct OutboundCalldata {
        address from;
        bytes extraData;
    }

    // Emitted when an incoming transfer is finalized, i.e. tokens were deposited from L1 to L2
    event DepositFinalized(
        address indexed l1Token,
        address indexed _from,
        address indexed _to,
        uint256 _amount
    );

    // Emitted when an outbound transfer is initiated, i.e. tokens are being withdrawn from L2 back to L1
    event WithdrawalInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _l2ToL1Id,
        uint256 _exitNum,
        uint256 _amount
    );

    // Emitted when the Arbitrum Gateway Router address on L2 has been updated
    event L2RouterSet(address _l2Router);
    // Emitted when the L1 Graph Token address has been updated
    event L1TokenAddressSet(address _l1GRT);
    // Emitted when the address of the counterpart gateway on L1 has been updated
    event L1CounterpartAddressSet(address _l1Counterpart);
    // Emitted when an address is added to the callhook whitelist
    event AddedToCallhookWhitelist(address newWhitelisted);
    // Emitted when an address is removed from the callhook whitelist
    event RemovedFromCallhookWhitelist(address notWhitelisted);
    // Emitted when a callhook call failed
    event CallhookFailed(address destination);

    /**
     * @dev Checks that the sender is the L2 alias of the counterpart
     * gateway on L1.
     */
    modifier onlyL1Counterpart() {
        require(msg.sender == l1ToL2Alias(l1Counterpart), "ONLY_COUNTERPART_GATEWAY");
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
     * @dev Sets the address of the Arbitrum Gateway Router on L2
     * @param _l2Router Address of the L2 Router (provided by Arbitrum)
     */
    function setL2Router(address _l2Router) external onlyGovernor {
        l2Router = _l2Router;
        emit L2RouterSet(_l2Router);
    }

    /**
     * @dev Sets the address of the Graph Token on L1
     * @param _l1GRT L1 address of the Graph Token contract
     */
    function setL1TokenAddress(address _l1GRT) external onlyGovernor {
        l1GRT = _l1GRT;
        emit L1TokenAddressSet(_l1GRT);
    }

    /**
     * @dev Sets the address of the counterpart gateway on L1
     * @param _l1Counterpart Address of the L1GraphTokenGateway on L1
     */
    function setL1CounterpartAddress(address _l1Counterpart) external onlyGovernor {
        l1Counterpart = _l1Counterpart;
        emit L1CounterpartAddressSet(_l1Counterpart);
    }

    /**
     * @dev Adds an L1 address to the callhook whitelist.
     * This address will be allowed to include callhooks when transferring tokens.
     * @param newWhitelisted Address to add to the whitelist
     */
    function addToCallhookWhitelist(address newWhitelisted) external onlyGovernor {
        callhookWhitelist[newWhitelisted] = true;
        emit AddedToCallhookWhitelist(newWhitelisted);
    }

    /**
     * @dev Removes an L1 address from the callhook whitelist.
     * This address will no longer be allowed to include callhooks when transferring tokens.
     * @param notWhitelisted Address to remove from the whitelist
     */
    function removeFromCallhookWhitelist(address notWhitelisted) external onlyGovernor {
        callhookWhitelist[notWhitelisted] = false;
        emit RemovedFromCallhookWhitelist(notWhitelisted);
    }

    /**
     * @notice Burns L2 tokens and initiates a transfer to L1.
     * The tokens will be available on L1 only after the wait period (7 days) is over,
     * and will require an Outbox.executeTransaction to finalize.
     * @dev no additional callhook data is allowed. The two unused params are needed
     * for compatibility with Arbitrum's gateway router.
     * The function is payable for ITokenGateway compatibility, but msg.value must be zero.
     * @param _l1Token L1 Address of GRT (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L1
     * @param _amount Amount of tokens to burn
     * @param _data Contains sender and additional data (always zero) to send to L1
     * @return ID of the withdraw transaction
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256, // unused on L2
        uint256, // unused on L2
        bytes calldata _data
    ) public payable override notPaused returns (bytes memory) {
        require(_l1Token == l1GRT, "TOKEN_NOT_GRT");
        require(_amount > 0, "INVALID_ZERO_AMOUNT");
        require(msg.value == 0, "INVALID_NONZERO_VALUE");

        OutboundCalldata memory s;

        (s.from, s.extraData) = parseOutboundData(_data);
        require(s.extraData.length == 0, "CALL_HOOK_DATA_NOT_ALLOWED");

        // from needs to approve this contract to burn the amount first
        L2GraphToken(this.calculateL2TokenAddress(l1GRT)).bridgeBurn(s.from, _amount);

        uint256 id = sendTxToL1(
            0,
            s.from,
            l1Counterpart,
            getOutboundCalldata(_l1Token, s.from, _to, _amount, s.extraData)
        );

        // we don't need to track exitNums (b/c we have no fast exits) so we always use 0
        emit WithdrawalInitiated(_l1Token, s.from, _to, id, 0, _amount);

        return abi.encode(id);
    }

    /**
     * @notice Burns L2 tokens and initiates a transfer to L1.
     * The tokens will be received on L1 only after the wait period (7 days) is over,
     * and will require an Outbox.executeTransaction to finalize.
     * @dev no additional callhook data is allowed
     * @param _l1Token L1 Address of GRT (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L1
     * @param _amount Amount of tokens to burn
     * @param _data Contains sender and additional data to send to L1
     * @return ID of the withdraw tx
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes memory) {
        return outboundTransfer(_l1Token, _to, _amount, uint256(0), uint256(0), _data);
    }

    /**
     * @notice Calculate the L2 address of a bridged token
     * @dev In our case, this would only work for GRT.
     * @param l1ERC20 address of L1 GRT contract
     * @return L2 address of the bridged GRT token
     */
    function calculateL2TokenAddress(address l1ERC20) public view override returns (address) {
        if (l1ERC20 != l1GRT) {
            return address(0);
        }
        return Managed._resolveContract(keccak256("GraphToken"));
    }

    /**
     * @notice Receives token amount from L1 and mints the equivalent tokens to the receiving address
     * @dev Only accepts transactions from the L1 GRT Gateway
     * data param is unused because no additional data is allowed from L1.
     * The function is payable for ITokenGateway compatibility, but msg.value must be zero.
     * @param _l1Token L1 Address of GRT
     * @param _from Address of the sender on L1
     * @param _to Recipient address on L2
     * @param _amount Amount of tokens transferred
     * @param _data Extra callhook data, only used when the sender is whitelisted
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable override notPaused onlyL1Counterpart {
        require(_l1Token == l1GRT, "TOKEN_NOT_GRT");
        require(msg.value == 0, "INVALID_NONZERO_VALUE");

        if (_data.length > 0 && callhookWhitelist[_from] == true) {
            bytes memory callhookData;
            {
                bytes memory gatewayData;
                (gatewayData, callhookData) = abi.decode(_data, (bytes, bytes));
            }
            bool success;
            // solhint-disable-next-line avoid-low-level-calls
            (success, ) = _to.call(callhookData);
            // Callhooks shouldn't revert, but if they do:
            // we revert, so that the retryable ticket can be re-attempted
            // later.
            if (!success) {
                revert("CALLHOOK_FAILED");
            }
        }

        L2GraphToken(calculateL2TokenAddress(l1GRT)).bridgeMint(_to, _amount);

        emit DepositFinalized(_l1Token, _from, _to, _amount);
    }

    /**
     * @notice Creates calldata required to send tx to L1
     * @dev encodes the target function with its params which
     * will be called on L1 when the message is received on L1
     * @param token Address of the token on L1
     * @param from Address of the token sender on L2
     * @param to Address to which we're sending tokens on L1
     * @param amount Amount of GRT to transfer
     * @param data Additional calldata for the transaction
     */
    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public pure returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            token,
            from,
            to,
            amount,
            abi.encode(0, data) // we don't need to track exitNums (b/c we have no fast exits) so we always use 0
        );
    }

    /**
     * @notice Decodes calldata required for migration of tokens
     * @dev extraData can be left empty
     * @param data Encoded callhook data
     * @return from Sender of the tx
     * @return extraData Any other data sent to L1
     */
    function parseOutboundData(bytes memory data)
        private
        view
        returns (address from, bytes memory extraData)
    {
        if (msg.sender == l2Router) {
            (from, extraData) = abi.decode(data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = data;
        }
    }

    /**
     * @notice Converts L1 address to its L2 alias used when sending messages
     * @dev The Arbitrum bridge adds an offset to addresses when sending messages,
     * so we need to apply it to check any L1 address from a message in L2
     * @param _l1Address The L1 address
     * @return _l2Address the L2 alias of _l1Address
     */
    function l1ToL2Alias(address _l1Address) internal pure returns (address _l2Address) {
        _l2Address = address(uint160(_l1Address) + L2_ADDRESS_OFFSET);
    }
}
