// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ITokenGateway } from "../arbitrum//ITokenGateway.sol";

/**
 * @title L1 Token Gateway mock contract
 * @dev Used for testing purposes, DO NOT USE IN PRODUCTION
 */
contract L1TokenGatewayMock is Ownable {
    using SafeMath for uint256;
    /// Next sequence number to return when outboundTransfer is called
    uint256 public nextSeqNum;

    /// @dev Emitted when a (fake) retryable ticket is created
    event FakeTxToL2(
        address from,
        uint256 value,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost,
        bytes outboundCalldata
    );

    /// @dev Emitted when an outbound transfer is initiated, i.e. tokens are deposited from L1 to L2
    event DepositInitiated(
        address l1Token,
        address indexed from,
        address indexed to,
        uint256 indexed sequenceNumber,
        uint256 amount
    );

    /**
     * @notice L1 Token Gateway Contract Constructor.
     */
    constructor() {}

    /**
     * @notice Creates and sends a fake retryable ticket to transfer GRT to L2.
     * This mock will actually just emit an event with parameters equivalent to what the real L1GraphTokenGateway
     * would send to L2.
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _to Recipient address on L2
     * @param _amount Amount of tokens to tranfer
     * @param _maxGas Gas limit for L2 execution of the ticket
     * @param _gasPriceBid Price per gas on L2
     * @param _data Encoded maxSubmissionCost and sender address along with additional calldata
     * @return Sequence number of the retryable ticket created by Inbox (always )
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory) {
        require(_amount > 0, "INVALID_ZERO_AMOUNT");
        require(_to != address(0), "INVALID_DESTINATION");

        // nested scopes to avoid stack too deep errors
        address from;
        uint256 seqNum = nextSeqNum;
        nextSeqNum += 1;
        {
            uint256 maxSubmissionCost;
            bytes memory outboundCalldata;
            {
                bytes memory extraData;
                (from, maxSubmissionCost, extraData) = _parseOutboundData(_data);
                require(maxSubmissionCost > 0, "NO_SUBMISSION_COST");

                {
                    // makes sure only sufficient ETH is supplied as required for successful redemption on L2
                    // if a user does not desire immediate redemption they should provide
                    // a msg.value of AT LEAST maxSubmissionCost
                    uint256 expectedEth = maxSubmissionCost.add(_maxGas.mul(_gasPriceBid));
                    require(msg.value >= expectedEth, "WRONG_ETH_VALUE");
                }
                outboundCalldata = getOutboundCalldata(_l1Token, from, _to, _amount, extraData);
            }
            {
                // transfer tokens to escrow
                IERC20(_l1Token).transferFrom(from, address(this), _amount);

                emit FakeTxToL2(from, msg.value, _maxGas, _gasPriceBid, maxSubmissionCost, outboundCalldata);
            }
        }
        emit DepositInitiated(_l1Token, from, _to, seqNum, _amount);

        return abi.encode(seqNum);
    }

    /**
     * @notice (Mock) Receives withdrawn tokens from L2
     * Actually does nothing, just keeping it here as its useful to define the expected
     * calldata for the outgoing transfer in tests.
     * @param _l1Token L1 Address of the GRT contract (needed for compatibility with Arbitrum Gateway Router)
     * @param _from Address of the sender
     * @param _to Recepient address on L1
     * @param _amount Amount of tokens transferred
     * @param _data Additional calldata
     */
    function finalizeInboundTransfer(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable {}

    /**
     * @notice Creates calldata required to create a retryable ticket
     * @dev encodes the target function with its params which
     * will be called on L2 when the retryable ticket is redeemed
     * @param _l1Token Address of the Graph token contract on L1
     * @param _from Address on L1 from which we're transferring tokens
     * @param _to Address on L2 to which we're transferring tokens
     * @param _amount Amount of GRT to transfer
     * @param _data Additional call data for the L2 transaction, which must be empty unless the caller is whitelisted
     * @return Encoded calldata (including function selector) for the L2 transaction
     */
    function getOutboundCalldata(
        address _l1Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public pure returns (bytes memory) {
        bytes memory emptyBytes;

        return
            abi.encodeWithSelector(
                ITokenGateway.finalizeInboundTransfer.selector,
                _l1Token,
                _from,
                _to,
                _amount,
                abi.encode(emptyBytes, _data)
            );
    }

    /**
     * @notice Decodes calldata required for transfer of tokens to L2
     * @dev Data must include maxSubmissionCost, extraData can be left empty. When the router
     * sends an outbound message, data also contains the from address, but this mock
     * doesn't consider this case
     * @param _data Encoded callhook data containing maxSubmissionCost and extraData
     * @return Sender of the tx
     * @return Max ether value used to submit the retryable ticket
     * @return Additional data sent to L2
     */
    function _parseOutboundData(bytes memory _data) private view returns (address, uint256, bytes memory) {
        address from;
        uint256 maxSubmissionCost;
        bytes memory extraData;
        from = msg.sender;
        // User-encoded data contains the max retryable ticket submission cost
        // and additional L2 calldata
        (maxSubmissionCost, extraData) = abi.decode(_data, (uint256, bytes));
        return (from, maxSubmissionCost, extraData);
    }
}
