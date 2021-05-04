// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";

import "../governance/Governed.sol";
import "../staking/IStaking.sol";
import "../token/IGraphToken.sol";

/**
 * @title Allocation Exchange
 * @dev This contract holds tokens that anyone with a voucher signed by the
 * authority can redeem. The contract validates if the voucher presented is valid
 * and then sends tokens to the Staking contract by calling the collect() function
 * passing the voucher allocationID. The contract enforces that only one voucher for
 * an allocationID can be redeemed.
 * Only governance can change the authority.
 */
contract AllocationExchange is Governed {
    // An allocation voucher represents a signed message that allows
    // to redeem an amount of funds from this contract and collect
    // them as part of an allocation
    struct AllocationVoucher {
        address allocationId;
        uint256 amount;
        bytes signature; // 65 bytes
    }

    // -- Constants --

    uint256 private constant MAX_UINT256 = 2**256 - 1;

    // -- State --

    IStaking private immutable staking;
    IGraphToken private immutable graphToken;
    address public authority;
    mapping(address => bool) public allocationsRedeemed;

    // -- Events

    event AuthoritySet(address indexed account);
    event AllocationRedeemed(address indexed allocationID, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);

    // -- Functions

    constructor(
        IGraphToken _graphToken,
        IStaking _staking,
        address _governor,
        address _authority
    ) {
        Governed._initialize(_governor);

        graphToken = _graphToken;
        staking = _staking;
        authority = _authority;
    }

    function approveAll() external {
        graphToken.approve(address(staking), MAX_UINT256);
    }

    function withdraw(uint256 _amount, address _to) public onlyGovernor {
        require(graphToken.transfer(_to, _amount), "Exchange: cannot transfer");
        emit TokensWithdrawn(_to, _amount);
    }

    function setAuthority(address _authority) public onlyGovernor {
        require(_authority != address(0), "Exchange: empty authority");
        authority = _authority;
        emit AuthoritySet(authority);
    }

    function redeem(bytes calldata _msg) public {
        // Parse voucher
        AllocationVoucher memory voucher = abi.decode(_msg, (AllocationVoucher));

        // Already collected check
        require(
            !allocationsRedeemed[voucher.allocationId],
            "Collect: allocation already collected"
        );

        // Signature check
        bytes32 collectHash = keccak256(abi.encodePacked(voucher.amount, voucher.allocationId));
        require(
            authority == ECDSA.recover(collectHash, voucher.signature),
            "Collect: invalid signer"
        );

        // Mark allocation as collected
        allocationsRedeemed[voucher.allocationId] = true;

        // Make the staking contract collect funds from this contract
        staking.collect(voucher.amount, voucher.allocationId);

        emit AllocationRedeemed(voucher.allocationId, voucher.amount);
    }
}
