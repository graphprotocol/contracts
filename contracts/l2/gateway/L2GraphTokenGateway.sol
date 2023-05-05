// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { L2ArbitrumMessenger } from "../../arbitrum/L2ArbitrumMessenger.sol";
import { AddressAliasHelper } from "../../arbitrum/AddressAliasHelper.sol";
import { ITokenGateway } from "../../arbitrum/ITokenGateway.sol";
import { Managed } from "../../governance/Managed.sol";
import { GraphTokenGateway } from "../../gateway/GraphTokenGateway.sol";
import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";
import { L2GraphToken } from "../token/L2GraphToken.sol";

/**
 * @title L2 Graph Token Gateway Contract
 * @dev Provides the L2 side of the Ethereum-Arbitrum GRT bridge. Receives GRT from the L1 chain
 * and mints them on the L2 side. Sends GRT back to L1 by burning them on the L2 side.
 * Based on Offchain Labs' reference implementation and Livepeer's arbitrum-lpt-bridge
 * (See: https://github.com/OffchainLabs/arbitrum/tree/master/packages/arb-bridge-peripherals/contracts/tokenbridge
 * and https://github.com/livepeer/arbitrum-lpt-bridge)
 */
contract L2GraphTokenGateway is GraphTokenGateway, L2ArbitrumMessenger, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;

    /// Address of the Graph Token contract on L1
    address public l1GRT;
    /// Address of the L1GraphTokenGateway that is the counterpart of this gateway on L1
    address public l1Counterpart;
    /// Address of the Arbitrum Gateway Router on L2
    address public l2Router;

    /// @dev Calldata included in an outbound transfer, stored as a structure for convenience and stack depth
    struct OutboundCalldata {
        address from;
        bytes extraData;
    }

    /// Emitted when an incoming transfer is finalized, i.e. tokens were deposited from L1 to L2
    event DepositFinalized(
        address indexed l1Token,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /// Emitted when an outbound transfer is initiated, i.e. tokens are being withdrawn from L2 back to L1
    event WithdrawalInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed l2ToL1Id,
        uint256 exitNum,
        uint256 amount
    );

    /// Emitted when the Arbitrum Gateway Router address on L2 has been updated
    event L2RouterSet(address l2Router);
    /// Emitted when the L1 Graph Token address has been updated
    event L1TokenAddressSet(address l1GRT);
    /// Emitted when the address of the counterpart gateway on L1 has been updated
    event L1CounterpartAddressSet(address l1Counterpart);

    /**
     * @dev Checks that the sender is the L2 alias of the counterpart
     * gateway on L1.
     */
    modifier onlyL1Counterpart() {
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1Counterpart),
            "ONLY_COUNTERPART_GATEWAY"
        );
        _;
    }

    /**
     * @notice Initialize the L2GraphTokenGateway contract.
     * @dev The contract will be paused.
     * Note some parameters have to be set separately as they are generally
     * not expected to be available at initialization time:
     * - l2Router using setL2Router
     * - l1GRT using setL1TokenAddress
     * - l1Counterpart using setL1CounterpartAddress
     * - pauseGuardian using setPauseGuardian
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl initializer {
        Managed._initialize(_controller);
        _paused = true;
        __ReentrancyGuard_init();
    }

    /**
     * @notice Sets the address of the Arbitrum Gateway Router on L2
     * @param _l2Router Address of the L2 Router (provided by Arbitrum)
     */
    function setL2Router(address _l2Router) external onlyGovernor {
        require(_l2Router != address(0), "INVALID_L2_ROUTER");
        l2Router = _l2Router;
        emit L2RouterSet(_l2Router);
    }

    /**
     * @notice Sets the address of the Graph Token on L1
     * @param _l1GRT L1 address of the Graph Token contract
     */
    function setL1TokenAddress(address _l1GRT) external onlyGovernor {
        require(_l1GRT != address(0), "INVALID_L1_GRT");
        l1GRT = _l1GRT;
        emit L1TokenAddressSet(_l1GRT);
    }

    /**
     * @notice Sets the address of the counterpart gateway on L1
     * @param _l1Counterpart Address of the L1GraphTokenGateway on L1
     */
    function setL1CounterpartAddress(address _l1Counterpart) external onlyGovernor {
        require(_l1Counterpart != address(0), "INVALID_L1_COUNTERPART");
        l1Counterpart = _l1Counterpart;
        emit L1CounterpartAddressSet(_l1Counterpart);
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
        return outboundTransfer(_l1Token, _to, _amount, 0, 0, _data);
    }

    /**
     * @notice Receives token amount from L1 and mints the equivalent tokens to the receiving address
     * @dev Only accepts transactions from the L1 GRT Gateway.
     * The function is payable for ITokenGateway compatibility, but msg.value must be zero.
     * Note that allowlisted senders (some protocol contracts) can include additional calldata
     * for a callhook to be executed on the L2 side when the tokens are received. In this case, the L2 transaction
     * can revert if the callhook reverts, potentially locking the tokens on the bridge if the callhook
     * never succeeds. This requires extra care when adding contracts to the allowlist, but is necessary to ensure that
     * the tickets can be retried in the case of a temporary failure, and to ensure the atomicity of callhooks
     * with token transfers.
     * @param _l1Token L1 Address of GRT
     * @param _from Address of the sender on L1
     * @param _to Recipient address on L2
     * @param _amount Amount of tokens transferred
     * @param _data Extra callhook data, only used when the sender is allowlisted
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable override nonReentrant notPaused onlyL1Counterpart {
        require(_l1Token == l1GRT, "TOKEN_NOT_GRT");
        require(msg.value == 0, "INVALID_NONZERO_VALUE");

        L2GraphToken(calculateL2TokenAddress(l1GRT)).bridgeMint(_to, _amount);

        if (_data.length > 0) {
            ICallhookReceiver(_to).onTokenTransfer(_from, _amount, _data);
        }

        emit DepositFinalized(_l1Token, _from, _to, _amount);
    }

    /**
     * @notice Burns L2 tokens and initiates a transfer to L1.
     * The tokens will be available on L1 only after the wait period (7 days) is over,
     * and will require an Outbox.executeTransaction to finalize.
     * Note that the caller must previously allow the gateway to spend the specified amount of GRT.
     * @dev no additional callhook data is allowed. The two unused params are needed
     * for compatibility with Arbitrum's gateway router.
     * The function is payable for ITokenGateway compatibility, but msg.value must be zero.
     * @param _l1Token L1 Address of GRT (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L1
     * @param _amount Amount of tokens to burn
     * @param _data Contains sender and additional data (always empty) to send to L1
     * @return ID of the withdraw transaction
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256, // unused on L2
        uint256, // unused on L2
        bytes calldata _data
    ) public payable override nonReentrant notPaused returns (bytes memory) {
        require(_l1Token == l1GRT, "TOKEN_NOT_GRT");
        require(_amount != 0, "INVALID_ZERO_AMOUNT");
        require(msg.value == 0, "INVALID_NONZERO_VALUE");
        require(_to != address(0), "INVALID_DESTINATION");

        OutboundCalldata memory outboundCalldata;

        (outboundCalldata.from, outboundCalldata.extraData) = _parseOutboundData(_data);
        require(outboundCalldata.extraData.length == 0, "CALL_HOOK_DATA_NOT_ALLOWED");

        // from needs to approve this contract to burn the amount first
        L2GraphToken(calculateL2TokenAddress(l1GRT)).bridgeBurn(outboundCalldata.from, _amount);

        uint256 id = sendTxToL1(
            0,
            outboundCalldata.from,
            l1Counterpart,
            getOutboundCalldata(
                _l1Token,
                outboundCalldata.from,
                _to,
                _amount,
                outboundCalldata.extraData
            )
        );

        // we don't need to track exitNums (b/c we have no fast exits) so we always use 0
        emit WithdrawalInitiated(_l1Token, outboundCalldata.from, _to, id, 0, _amount);

        return abi.encode(id);
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
        return address(graphToken());
    }

    /**
     * @notice Creates calldata required to send tx to L1
     * @dev encodes the target function with its params which
     * will be called on L1 when the message is received on L1
     * @param _token Address of the token on L1
     * @param _from Address of the token sender on L2
     * @param _to Address to which we're sending tokens on L1
     * @param _amount Amount of GRT to transfer
     * @param _data Additional calldata for the transaction
     * @return Calldata for a transaction sent to L1
     */
    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ITokenGateway.finalizeInboundTransfer.selector,
                _token,
                _from,
                _to,
                _amount,
                abi.encode(0, _data) // we don't need to track exitNums (b/c we have no fast exits) so we always use 0
            );
    }

    /**
     * @dev Runs state validation before unpausing, reverts if
     * something is not set properly
     */
    function _checksBeforeUnpause() internal view override {
        require(l2Router != address(0), "L2_ROUTER_NOT_SET");
        require(l1Counterpart != address(0), "L1_COUNTERPART_NOT_SET");
        require(l1GRT != address(0), "L1_GRT_NOT_SET");
    }

    /**
     * @notice Decodes calldata required for transfer of tokens to L1
     * @dev extraData can be left empty
     * @param _data Encoded callhook data
     * @return Sender of the tx
     * @return Any other data sent to L1
     */
    function _parseOutboundData(bytes calldata _data) private view returns (address, bytes memory) {
        address from;
        bytes memory extraData;
        if (msg.sender == l2Router) {
            (from, extraData) = abi.decode(_data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = _data;
        }
        return (from, extraData);
    }
}
