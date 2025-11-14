// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-calldata-parameters, gas-increment-by-one, gas-indexed-events, gas-small-strings
// solhint-disable named-parameters-mapping

import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Governed } from "../governance/Governed.sol";
import { IStaking } from "@graphprotocol/interfaces/contracts/contracts/staking/IStaking.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";

/**
 * @title Allocation Exchange
 * @author Edge & Node
 * @notice This contract holds tokens that anyone with a voucher signed by the
 * authority can redeem. The contract validates if the voucher presented is valid
 * and then sends tokens to the Staking contract by calling the collect() function
 * passing the voucher allocationID. The contract enforces that only one voucher for
 * an allocationID can be redeemed.
 * Only governance can change the authority.
 */
contract AllocationExchange is Governed {
    /**
     * @dev An allocation voucher represents a signed message that allows
     * redeeming an amount of funds from this contract and collect
     * them as part of an allocation
     * @param allocationID Address of the allocation
     * @param amount Amount of tokens to redeem
     * @param signature Signature from the authority (65 bytes)
     */
    struct AllocationVoucher {
        address allocationID;
        uint256 amount;
        bytes signature; // 65 bytes
    }

    // -- Constants --

    /// @dev Maximum uint256 value used for unlimited token approvals
    uint256 private constant MAX_UINT256 = 2 ** 256 - 1;
    /// @dev Expected length of ECDSA signatures
    uint256 private constant SIGNATURE_LENGTH = 65;

    // -- State --

    /// @dev Reference to the Staking contract
    IStaking private immutable STAKING;
    /// @dev Reference to the Graph Token contract
    IGraphToken private immutable GRAPH_TOKEN;
    /// @notice Mapping of authorized accounts that can redeem allocations
    mapping(address => bool) public authority;
    /// @notice Mapping of allocations that have been redeemed
    mapping(address => bool) public allocationsRedeemed;

    // -- Events

    /**
     * @notice Emitted when an authority is set or unset
     * @param account Address of the authority
     * @param authorized Whether the authority is authorized
     */
    event AuthoritySet(address indexed account, bool authorized);

    /**
     * @notice Emitted when an allocation voucher is redeemed
     * @param allocationID Address of the allocation
     * @param amount Amount of tokens redeemed
     */
    event AllocationRedeemed(address indexed allocationID, uint256 amount);

    /**
     * @notice Emitted when tokens are withdrawn from the contract
     * @param to Address that received the tokens
     * @param amount Amount of tokens withdrawn
     */
    event TokensWithdrawn(address indexed to, uint256 amount);

    // -- Functions

    /**
     * @notice Contract constructor.
     * @param _graphToken Address of the GRT token
     * @param _staking Address of the protocol Staking contract
     * @param _governor Account capable of withdrawing funds and setting the authority
     * @param _authority Account that can sign the vouchers that this contract will redeem
     */
    constructor(IGraphToken _graphToken, IStaking _staking, address _governor, address _authority) {
        require(_governor != address(0), "Exchange: governor must be set");
        Governed._initialize(_governor);

        GRAPH_TOKEN = _graphToken;
        STAKING = _staking;
        _setAuthority(_authority, true);
    }

    /**
     * @notice Approve the staking contract to pull any amount of tokens from this contract.
     * @dev Increased gas efficiency instead of approving on each voucher redeem
     */
    function approveAll() external {
        GRAPH_TOKEN.approve(address(STAKING), MAX_UINT256);
    }

    /**
     * @notice Withdraw tokens held in the contract.
     * @dev Only the governor can withdraw
     * @param _to Destination to send the tokens
     * @param _amount Amount of tokens to withdraw
     */
    function withdraw(address _to, uint256 _amount) external onlyGovernor {
        require(_to != address(0), "Exchange: empty destination");
        require(_amount != 0, "Exchange: empty amount");
        require(GRAPH_TOKEN.transfer(_to, _amount), "Exchange: cannot transfer");
        emit TokensWithdrawn(_to, _amount);
    }

    /**
     * @notice Set the authority allowed to sign vouchers.
     * @dev Only the governor can set the authority
     * @param _authority Address of the signing authority
     * @param _authorized True if the authority is authorized to sign vouchers, false to unset
     */
    function setAuthority(address _authority, bool _authorized) external onlyGovernor {
        _setAuthority(_authority, _authorized);
    }

    /**
     * @notice Set the authority allowed to sign vouchers.
     * @param _authority Address of the signing authority
     * @param _authorized True if the authority is authorized to sign vouchers, false to unset
     */
    function _setAuthority(address _authority, bool _authorized) private {
        require(_authority != address(0), "Exchange: empty authority");
        // This will help catch some operational errors but not all.
        // The validation will fail under the following conditions:
        // - a contract in construction
        // - an address where a contract will be created
        // - an address where a contract lived, but was destroyed
        require(!Address.isContract(_authority), "Exchange: authority must be EOA");
        authority[_authority] = _authorized;
        emit AuthoritySet(_authority, _authorized);
    }

    /**
     * @notice Redeem a voucher signed by the authority. No voucher double spending is allowed.
     * @dev The voucher must be signed using an Ethereum signed message
     * @param _voucher Voucher data
     */
    function redeem(AllocationVoucher memory _voucher) external {
        _redeem(_voucher);
    }

    /**
     * @notice Redeem multiple vouchers.
     * @dev Each voucher must be signed using an Ethereum signed message
     * @param _vouchers An array of vouchers
     */
    function redeemMany(AllocationVoucher[] memory _vouchers) external {
        for (uint256 i = 0; i < _vouchers.length; i++) {
            _redeem(_vouchers[i]);
        }
    }

    /**
     * @notice Redeem a voucher signed by the authority. No voucher double spending is allowed.
     * @dev The voucher must be signed using an Ethereum signed message
     * @param _voucher Voucher data
     */
    function _redeem(AllocationVoucher memory _voucher) private {
        require(_voucher.amount > 0, "Exchange: zero tokens voucher");
        require(_voucher.signature.length == SIGNATURE_LENGTH, "Exchange: invalid signature");

        // Already redeemed check
        require(!allocationsRedeemed[_voucher.allocationID], "Exchange: allocation already redeemed");

        // Signature check
        bytes32 messageHash = keccak256(abi.encodePacked(_voucher.allocationID, _voucher.amount));
        address voucherSigner = ECDSA.recover(messageHash, _voucher.signature);
        require(authority[voucherSigner], "Exchange: invalid signer");

        // Mark allocation as collected
        allocationsRedeemed[_voucher.allocationID] = true;

        // Make the staking contract collect funds from this contract
        // The Staking contract will validate if the allocation is valid
        STAKING.collect(_voucher.amount, _voucher.allocationID);

        emit AllocationRedeemed(_voucher.allocationID, _voucher.amount);
    }
}
