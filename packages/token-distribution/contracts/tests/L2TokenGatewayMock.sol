// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ITokenGateway } from "../arbitrum//ITokenGateway.sol";
import { GraphTokenMock } from "./GraphTokenMock.sol";
import { ICallhookReceiver } from "../ICallhookReceiver.sol";

/**
 * @title L2 Token Gateway mock contract
 * @dev Used for testing purposes, DO NOT USE IN PRODUCTION
 */
contract L2TokenGatewayMock is Ownable {
    /// Address of the L1 GRT contract
    address public immutable l1Token;
    /// Address of the L2 GRT contract
    address public immutable l2Token;
    /// Next ID to return when sending an outboundTransfer
    uint256 public nextId;

    /// @dev Emitted when a (fake) transaction to L1 is created
    event FakeTxToL1(address from, bytes outboundCalldata);
    /// @dev Emitted when a (fake) retryable ticket is received from L1
    event DepositFinalized(address token, address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when an outbound transfer is initiated, i.e. tokens are withdrawn to L1 from L2
    event WithdrawalInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed sequenceNumber,
        uint256 amount
    );

    /**
     * @notice L2 Token Gateway Contract Constructor.
     * @param _l1Token Address of the L1 GRT contract
     * @param _l2Token Address of the L2 GRT contract
     */
    constructor(address _l1Token, address _l2Token) {
        l1Token = _l1Token;
        l2Token = _l2Token;
    }

    /**
     * @notice Creates and sends a (fake) transfer of GRT to L1.
     * This mock will actually just emit an event with parameters equivalent to what the real L2GraphTokenGateway
     * would send to L1.
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L2
     * @param _amount Amount of tokens to tranfer
     * @param _data Encoded maxSubmissionCost and sender address along with additional calldata
     * @return ID of the L2-L1 message (incrementing on every call)
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256,
        uint256,
        bytes calldata _data
    ) external payable returns (bytes memory) {
        require(_l1Token == l1Token, "INVALID_L1_TOKEN");
        require(_amount > 0, "INVALID_ZERO_AMOUNT");
        require(_to != address(0), "INVALID_DESTINATION");

        // nested scopes to avoid stack too deep errors
        address from;
        uint256 id = nextId;
        nextId += 1;
        {
            bytes memory outboundCalldata;
            {
                bytes memory extraData;
                (from, extraData) = _parseOutboundData(_data);

                require(msg.value == 0, "!value");
                require(extraData.length == 0, "!extraData");
                outboundCalldata = getOutboundCalldata(_l1Token, from, _to, _amount, extraData);
            }
            {
                // burn tokens from the sender, they will be released from escrow in L1
                GraphTokenMock(l2Token).bridgeBurn(from, _amount);

                emit FakeTxToL1(from, outboundCalldata);
            }
        }
        emit WithdrawalInitiated(_l1Token, from, _to, id, _amount);

        return abi.encode(id);
    }

    /**
     * @notice (Mock) Receives withdrawn tokens from L1
     * Implements calling callhooks if data is non-empty.
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _from Address of the sender
     * @param _to Recipient address on L1
     * @param _amount Amount of tokens transferred
     * @param _data Additional calldata, will trigger an onTokenTransfer call if non-empty
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable {
        require(_l1Token == l1Token, "TOKEN_NOT_GRT");
        require(msg.value == 0, "INVALID_NONZERO_VALUE");

        GraphTokenMock(l2Token).bridgeMint(_to, _amount);

        if (_data.length > 0) {
            ICallhookReceiver(_to).onTokenTransfer(_from, _amount, _data);
        }

        emit DepositFinalized(_l1Token, _from, _to, _amount);
    }

    /**
     * @notice Calculate the L2 address of a bridged token
     * @dev In our case, this would only work for GRT.
     * @param l1ERC20 address of L1 GRT contract
     * @return L2 address of the bridged GRT token
     */
    function calculateL2TokenAddress(address l1ERC20) public view returns (address) {
        if (l1ERC20 != l1Token) {
            return address(0);
        }
        return l2Token;
    }

    /**
     * @notice Creates calldata required to create a tx to L1
     * @param _l1Token Address of the Graph token contract on L1
     * @param _from Address on L2 from which we're transferring tokens
     * @param _to Address on L1 to which we're transferring tokens
     * @param _amount Amount of GRT to transfer
     * @param _data Additional call data for the L1 transaction, which must be empty
     * @return Encoded calldata (including function selector) for the L1 transaction
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
                abi.encode(0, _data)
            );
    }

    /**
     * @dev Decodes calldata required for transfer of tokens to L1.
     * extraData can be left empty
     * @param _data Encoded callhook data
     * @return Sender of the tx
     * @return Any other data sent to L1
     */
    function _parseOutboundData(bytes calldata _data) private view returns (address, bytes memory) {
        address from;
        bytes memory extraData;
        // The mock doesn't take messages from the Router
        from = msg.sender;
        extraData = _data;
        return (from, extraData);
    }
}
