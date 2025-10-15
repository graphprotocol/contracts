// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events, gas-strict-inequalities
// solhint-disable named-parameters-mapping

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { L1ArbitrumMessenger } from "../arbitrum/L1ArbitrumMessenger.sol";
import { IBridge } from "../arbitrum/IBridge.sol";
import { IInbox } from "../arbitrum/IInbox.sol";
import { IOutbox } from "../arbitrum/IOutbox.sol";
import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { Managed } from "../governance/Managed.sol";
import { GraphTokenGateway } from "./GraphTokenGateway.sol";
import { IGraphToken } from "../token/IGraphToken.sol";

/**
 * @title L1 Graph Token Gateway Contract
 * @author Edge & Node
 * @notice Provides the L1 side of the Ethereum-Arbitrum GRT bridge. Sends GRT to the L2 chain
 * by escrowing them and sending a message to the L2 gateway, and receives tokens from L2 by
 * releasing them from escrow.
 * Based on Offchain Labs' reference implementation and Livepeer's arbitrum-lpt-bridge
 * (See: https://github.com/OffchainLabs/arbitrum/tree/master/packages/arb-bridge-peripherals/contracts/tokenbridge
 * and https://github.com/livepeer/arbitrum-lpt-bridge)
 */
contract L1GraphTokenGateway is Initializable, GraphTokenGateway, L1ArbitrumMessenger {
    using SafeMathUpgradeable for uint256;

    /// @notice Address of the Graph Token contract on L2
    address public l2GRT;
    /// @notice Address of the Arbitrum Inbox
    address public inbox;
    /// @notice Address of the Arbitrum Gateway Router on L1
    address public l1Router;
    /// @notice Address of the L2GraphTokenGateway on L2 that is the counterpart of this gateway
    address public l2Counterpart;
    /// @notice Address of the BridgeEscrow contract that holds the GRT in the bridge
    address public escrow;
    /// @notice Addresses for which this mapping is true are allowed to send callhooks in outbound transfers
    mapping(address => bool) public callhookAllowlist;
    /// @notice Total amount minted from L2
    uint256 public totalMintedFromL2;
    /// @notice Accumulated allowance for tokens minted from L2 at lastL2MintAllowanceUpdateBlock
    uint256 public accumulatedL2MintAllowanceSnapshot;
    /// @notice Block at which new L2 allowance starts accumulating
    uint256 public lastL2MintAllowanceUpdateBlock;
    /// @notice New L2 mint allowance per block
    uint256 public l2MintAllowancePerBlock;

    /**
     * @notice Emitted when an outbound transfer is initiated, i.e. tokens are deposited from L1 to L2
     * @param l1Token Address of the L1 token being transferred
     * @param from Address sending the tokens on L1
     * @param to Address receiving the tokens on L2
     * @param sequenceNumber Sequence number of the retryable ticket
     * @param amount Amount of tokens transferred
     */
    event DepositInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed sequenceNumber,
        uint256 amount
    );

    /**
     * @notice Emitted when an incoming transfer is finalized, i.e tokens are withdrawn from L2 to L1
     * @param l1Token Address of the L1 token being transferred
     * @param from Address sending the tokens on L2
     * @param to Address receiving the tokens on L1
     * @param exitNum Exit number (always 0 for this contract)
     * @param amount Amount of tokens transferred
     */
    event WithdrawalFinalized(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed exitNum,
        uint256 amount
    );

    /**
     * @notice Emitted when the Arbitrum Inbox and Gateway Router addresses have been updated
     * @param inbox Address of the Arbitrum Inbox
     * @param l1Router Address of the L1 Gateway Router
     */
    event ArbitrumAddressesSet(address inbox, address l1Router);

    /**
     * @notice Emitted when the L2 GRT address has been updated
     * @param l2GRT Address of the L2 GRT contract
     */
    event L2TokenAddressSet(address l2GRT);

    /**
     * @notice Emitted when the counterpart L2GraphTokenGateway address has been updated
     * @param l2Counterpart Address of the L2 counterpart gateway
     */
    event L2CounterpartAddressSet(address l2Counterpart);
    /**
     * @notice Emitted when the escrow address has been updated
     * @param escrow Address of the escrow contract
     */
    event EscrowAddressSet(address escrow);

    /**
     * @notice Emitted when an address is added to the callhook allowlist
     * @param newAllowlisted Address added to the allowlist
     */
    event AddedToCallhookAllowlist(address newAllowlisted);

    /**
     * @notice Emitted when an address is removed from the callhook allowlist
     * @param notAllowlisted Address removed from the allowlist
     */
    event RemovedFromCallhookAllowlist(address notAllowlisted);

    /**
     * @notice Emitted when the L2 mint allowance per block is updated
     * @param accumulatedL2MintAllowanceSnapshot Accumulated allowance snapshot at update block
     * @param l2MintAllowancePerBlock New allowance per block
     * @param lastL2MintAllowanceUpdateBlock Block number when allowance was updated
     */
    event L2MintAllowanceUpdated(
        uint256 accumulatedL2MintAllowanceSnapshot,
        uint256 l2MintAllowancePerBlock,
        uint256 lastL2MintAllowanceUpdateBlock
    );

    /**
     * @notice Emitted when tokens are minted due to an incoming transfer from L2
     * @param amount Amount of tokens minted
     */
    event TokensMintedFromL2(uint256 amount);

    /**
     * @dev Allows a function to be called only by the gateway's L2 counterpart.
     * The message will actually come from the Arbitrum Bridge, but the Outbox
     * can tell us who the sender from L2 is.
     */
    modifier onlyL2Counterpart() {
        require(inbox != address(0), "INBOX_NOT_SET");
        require(l2Counterpart != address(0), "L2_COUNTERPART_NOT_SET");

        // a message coming from the counterpart gateway was executed by the bridge
        IBridge bridge = IInbox(inbox).bridge();
        require(msg.sender == address(bridge), "NOT_FROM_BRIDGE");

        // and the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = IOutbox(bridge.activeOutbox()).l2ToL1Sender();
        require(l2ToL1Sender == l2Counterpart, "ONLY_COUNTERPART_GATEWAY");
        _;
    }

    /**
     * @notice Initialize the L1GraphTokenGateway contract.
     * @dev The contract will be paused.
     * Note some parameters have to be set separately as they are generally
     * not expected to be available at initialization time:
     * - inbox  and l1Router using setArbitrumAddresses
     * - l2GRT using setL2TokenAddress
     * - l2Counterpart using setL2CounterpartAddress
     * - escrow using setEscrowAddress
     * - allowlisted callhook callers using addToCallhookAllowlist
     * - pauseGuardian using setPauseGuardian
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl initializer {
        Managed._initialize(_controller);
        _paused = true;
    }

    /**
     * @notice Sets the addresses for L1 contracts provided by Arbitrum
     * @param _inbox Address of the Inbox that is part of the Arbitrum Bridge
     * @param _l1Router Address of the Gateway Router
     */
    function setArbitrumAddresses(address _inbox, address _l1Router) external onlyGovernor {
        require(_inbox != address(0), "INVALID_INBOX");
        require(_l1Router != address(0), "INVALID_L1_ROUTER");
        require(!callhookAllowlist[_l1Router], "ROUTER_CANT_BE_ALLOWLISTED");
        require(AddressUpgradeable.isContract(_inbox), "INBOX_MUST_BE_CONTRACT");
        require(AddressUpgradeable.isContract(_l1Router), "ROUTER_MUST_BE_CONTRACT");
        inbox = _inbox;
        l1Router = _l1Router;
        emit ArbitrumAddressesSet(_inbox, _l1Router);
    }

    /**
     * @notice Sets the address of the L2 Graph Token
     * @param _l2GRT Address of the GRT contract on L2
     */
    function setL2TokenAddress(address _l2GRT) external onlyGovernor {
        require(_l2GRT != address(0), "INVALID_L2_GRT");
        l2GRT = _l2GRT;
        emit L2TokenAddressSet(_l2GRT);
    }

    /**
     * @notice Sets the address of the counterpart gateway on L2
     * @param _l2Counterpart Address of the corresponding L2GraphTokenGateway on Arbitrum
     */
    function setL2CounterpartAddress(address _l2Counterpart) external onlyGovernor {
        require(_l2Counterpart != address(0), "INVALID_L2_COUNTERPART");
        l2Counterpart = _l2Counterpart;
        emit L2CounterpartAddressSet(_l2Counterpart);
    }

    /**
     * @notice Sets the address of the escrow contract on L1
     * @param _escrow Address of the BridgeEscrow
     */
    function setEscrowAddress(address _escrow) external onlyGovernor {
        require(_escrow != address(0), "INVALID_ESCROW");
        require(AddressUpgradeable.isContract(_escrow), "MUST_BE_CONTRACT");
        escrow = _escrow;
        emit EscrowAddressSet(_escrow);
    }

    /**
     * @notice Adds an address to the callhook allowlist.
     * This address will be allowed to include callhooks when transferring tokens.
     * @param _newAllowlisted Address to add to the allowlist
     */
    function addToCallhookAllowlist(address _newAllowlisted) external onlyGovernor {
        require(_newAllowlisted != address(0), "INVALID_ADDRESS");
        require(_newAllowlisted != l1Router, "CANT_ALLOW_ROUTER");
        require(AddressUpgradeable.isContract(_newAllowlisted), "MUST_BE_CONTRACT");
        require(!callhookAllowlist[_newAllowlisted], "ALREADY_ALLOWLISTED");
        callhookAllowlist[_newAllowlisted] = true;
        emit AddedToCallhookAllowlist(_newAllowlisted);
    }

    /**
     * @notice Removes an address from the callhook allowlist.
     * This address will no longer be allowed to include callhooks when transferring tokens.
     * @param _notAllowlisted Address to remove from the allowlist
     */
    function removeFromCallhookAllowlist(address _notAllowlisted) external onlyGovernor {
        require(_notAllowlisted != address(0), "INVALID_ADDRESS");
        require(callhookAllowlist[_notAllowlisted], "NOT_ALLOWLISTED");
        callhookAllowlist[_notAllowlisted] = false;
        emit RemovedFromCallhookAllowlist(_notAllowlisted);
    }

    /**
     * @notice Updates the L2 mint allowance per block
     * It is meant to be called _after_ the issuancePerBlock is updated in L2.
     * The caller should provide the new issuance per block and the block at which it was updated,
     * the function will automatically compute the values so that the bridge's mint allowance
     * correctly tracks the maximum rewards minted in L2.
     * @param _l2IssuancePerBlock New issuancePerBlock that has been set in L2
     * @param _updateBlockNum L1 Block number at which issuancePerBlock was updated in L2
     */
    function updateL2MintAllowance(uint256 _l2IssuancePerBlock, uint256 _updateBlockNum) external onlyGovernor {
        require(_updateBlockNum < block.number, "BLOCK_MUST_BE_PAST");
        require(_updateBlockNum > lastL2MintAllowanceUpdateBlock, "BLOCK_MUST_BE_INCREMENTING");
        accumulatedL2MintAllowanceSnapshot = accumulatedL2MintAllowanceAtBlock(_updateBlockNum);
        lastL2MintAllowanceUpdateBlock = _updateBlockNum;
        l2MintAllowancePerBlock = _l2IssuancePerBlock;
        emit L2MintAllowanceUpdated(
            accumulatedL2MintAllowanceSnapshot,
            l2MintAllowancePerBlock,
            lastL2MintAllowanceUpdateBlock
        );
    }

    /**
     * @notice Manually sets the parameters used to compute the L2 mint allowance
     * The use of this function is not recommended, use updateL2MintAllowance instead;
     * this one is only meant to be used as a backup recovery if a previous call to
     * updateL2MintAllowance was done with incorrect values.
     * @param _accumulatedL2MintAllowanceSnapshot Accumulated L2 mint allowance at L1 block _lastL2MintAllowanceUpdateBlock
     * @param _l2MintAllowancePerBlock L2 issuance per block since block number _lastL2MintAllowanceUpdateBlock
     * @param _lastL2MintAllowanceUpdateBlock L1 Block number at which issuancePerBlock was last updated in L2
     */
    function setL2MintAllowanceParametersManual(
        uint256 _accumulatedL2MintAllowanceSnapshot,
        uint256 _l2MintAllowancePerBlock,
        uint256 _lastL2MintAllowanceUpdateBlock
    ) external onlyGovernor {
        require(_lastL2MintAllowanceUpdateBlock < block.number, "BLOCK_MUST_BE_PAST");
        accumulatedL2MintAllowanceSnapshot = _accumulatedL2MintAllowanceSnapshot;
        l2MintAllowancePerBlock = _l2MintAllowancePerBlock;
        lastL2MintAllowanceUpdateBlock = _lastL2MintAllowanceUpdateBlock;
        emit L2MintAllowanceUpdated(
            accumulatedL2MintAllowanceSnapshot,
            l2MintAllowancePerBlock,
            lastL2MintAllowanceUpdateBlock
        );
    }

    /**
     * @inheritdoc ITokenGateway
     * @dev maxGas and gasPriceBid must be set using Arbitrum's NodeInterface.estimateRetryableTicket method.
     * Also note that allowlisted senders (some protocol contracts) can include additional calldata
     * for a callhook to be executed on the L2 side when the tokens are received. In this case, the L2 transaction
     * can revert if the callhook reverts, potentially locking the tokens on the bridge if the callhook
     * never succeeds. This requires extra care when adding contracts to the allowlist, but is necessary to ensure that
     * the tickets can be retried in the case of a temporary failure, and to ensure the atomicity of callhooks
     * with token transfers.
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
        require(_amount != 0, "INVALID_ZERO_AMOUNT");
        require(_l1Token == address(token), "TOKEN_NOT_GRT");
        require(_to != address(0), "INVALID_DESTINATION");

        // nested scopes to avoid stack too deep errors
        address from;
        uint256 seqNum;
        {
            uint256 maxSubmissionCost;
            bytes memory outboundCalldata;
            {
                bytes memory extraData;
                (from, maxSubmissionCost, extraData) = _parseOutboundData(_data);
                require(extraData.length == 0 || callhookAllowlist[msg.sender] == true, "CALL_HOOK_DATA_NOT_ALLOWED");
                require(maxSubmissionCost != 0, "NO_SUBMISSION_COST");
                outboundCalldata = getOutboundCalldata(_l1Token, from, _to, _amount, extraData);
            }
            {
                L2GasParams memory gasParams = L2GasParams(maxSubmissionCost, _maxGas, _gasPriceBid);
                // transfer tokens to escrow
                token.transferFrom(from, escrow, _amount);
                seqNum = sendTxToL2(inbox, l2Counterpart, from, msg.value, 0, gasParams, outboundCalldata);
            }
        }
        emit DepositInitiated(_l1Token, from, _to, seqNum, _amount);

        return abi.encode(seqNum);
    }

    /**
     * @inheritdoc ITokenGateway
     * @dev can only accept transactions coming from the L2 GRT Gateway.
     * The last parameter is unused but kept for compatibility with Arbitrum gateways,
     * and the encoded exitNum is assumed to be 0.
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata // _data, contains exitNum, unused by this contract
    ) external payable override notPaused onlyL2Counterpart {
        IGraphToken token = graphToken();
        require(_l1Token == address(token), "TOKEN_NOT_GRT");

        uint256 escrowBalance = token.balanceOf(escrow);
        if (_amount > escrowBalance) {
            // This will revert if trying to mint more than allowed
            _mintFromL2(_amount.sub(escrowBalance));
        }
        token.transferFrom(escrow, _to, _amount);

        emit WithdrawalFinalized(_l1Token, _from, _to, 0, _amount);
    }

    /**
     * @inheritdoc ITokenGateway
     * @dev In our case, this would only work for GRT.
     */
    function calculateL2TokenAddress(address _l1ERC20) external view override returns (address) {
        IGraphToken token = graphToken();
        if (_l1ERC20 != address(token)) {
            return address(0);
        }
        return l2GRT;
    }

    /**
     * @notice Get the address of the L2GraphTokenGateway
     * @dev This is added for compatibility with the Arbitrum Router's
     * gateway registration process.
     * @return Address of the L2 gateway connected to this gateway
     */
    function counterpartGateway() external view returns (address) {
        return l2Counterpart;
    }

    /**
     * @notice Creates calldata required to create a retryable ticket
     * @dev encodes the target function with its params which
     * will be called on L2 when the retryable ticket is redeemed
     * @param _l1Token Address of the Graph token contract on L1
     * @param _from Address on L1 from which we're transferring tokens
     * @param _to Address on L2 to which we're transferring tokens
     * @param _amount Amount of GRT to transfer
     * @param _data Additional call data for the L2 transaction, which must be empty unless the caller is allowlisted
     * @return Encoded calldata (including function selector) for the L2 transaction
     */
    function getOutboundCalldata(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ITokenGateway.finalizeInboundTransfer.selector,
                _l1Token,
                _from,
                _to,
                _amount,
                _data
            );
    }

    /// @inheritdoc GraphTokenGateway
    // solhint-disable-next-line use-natspec
    function _checksBeforeUnpause() internal view override {
        require(inbox != address(0), "INBOX_NOT_SET");
        require(l1Router != address(0), "ROUTER_NOT_SET");
        require(l2Counterpart != address(0), "L2_COUNTERPART_NOT_SET");
        require(escrow != address(0), "ESCROW_NOT_SET");
    }

    /**
     * @notice Decodes calldata required for transfer of tokens to L2
     * @dev Data must include maxSubmissionCost, extraData can be left empty. When the router
     * sends an outbound message, data also contains the from address.
     * @param _data encoded callhook data
     * @return Sender of the tx
     * @return Base ether value required to keep retryable ticket alive
     * @return Additional data sent to L2
     */
    function _parseOutboundData(bytes calldata _data) private view returns (address, uint256, bytes memory) {
        address from;
        uint256 maxSubmissionCost;
        bytes memory extraData;
        if (msg.sender == l1Router) {
            // Data encoded by the Gateway Router includes the sender address
            (from, extraData) = abi.decode(_data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = _data;
        }
        // User-encoded data contains the max retryable ticket submission cost
        // and additional L2 calldata
        (maxSubmissionCost, extraData) = abi.decode(extraData, (uint256, bytes));
        return (from, maxSubmissionCost, extraData);
    }

    /**
     * @notice Get the accumulated L2 mint allowance at a particular block number
     * @param _blockNum Block at which allowance will be computed
     * @return The accumulated GRT amount that can be minted from L2 at the specified block
     */
    function accumulatedL2MintAllowanceAtBlock(uint256 _blockNum) public view returns (uint256) {
        require(_blockNum >= lastL2MintAllowanceUpdateBlock, "INVALID_BLOCK_FOR_MINT_ALLOWANCE");
        return
            accumulatedL2MintAllowanceSnapshot.add(
                l2MintAllowancePerBlock.mul(_blockNum.sub(lastL2MintAllowanceUpdateBlock))
            );
    }

    /**
     * @notice Mint new L1 tokens coming  from L2
     * This will check if the amount to mint is within the L2's mint allowance, and revert otherwise.
     * The tokens will be sent to the bridge escrow (from where they will then be sent to the destinatary
     * of the current inbound transfer).
     * @param _amount Number of tokens to mint
     */
    function _mintFromL2(uint256 _amount) internal {
        // If we're trying to mint more than allowed, something's gone terribly wrong
        // (either the L2 issuance is wrong, or the Arbitrum bridge has been compromised)
        require(_l2MintAmountAllowed(_amount), "INVALID_L2_MINT_AMOUNT");
        totalMintedFromL2 = totalMintedFromL2.add(_amount);
        graphToken().mint(escrow, _amount);
        emit TokensMintedFromL2(_amount);
    }

    /**
     * @notice Check if minting a certain amount of tokens from L2 is within allowance
     * @param _amount Number of tokens that would be minted
     * @return true if minting those tokens is allowed, or false if it would be over allowance
     */
    function _l2MintAmountAllowed(uint256 _amount) internal view returns (bool) {
        return (totalMintedFromL2.add(_amount) <= accumulatedL2MintAllowanceAtBlock(block.number));
    }
}
