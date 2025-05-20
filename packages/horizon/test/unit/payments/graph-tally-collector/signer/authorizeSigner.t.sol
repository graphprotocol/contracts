// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IAuthorizable } from "../../../../../contracts/interfaces/IAuthorizable.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyAuthorizeSignerTest is GraphTallyTest {
    uint256 constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /*
     * TESTS
     */

    function testGraphTally_AuthorizeSigner(uint256 signerKey) public useGateway {
        signerKey = bound(signerKey, 1, SECP256K1_CURVE_ORDER - 1);
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerKey);
        _authorizeSigner(vm.addr(signerKey), proofDeadline, signerProof);
    }

    function testGraphTally_AuthorizeSigner_RevertWhen_Invalid() public useGateway {
        // Sign proof with payer
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);

        // Attempt to authorize delegator with payer's proof
        vm.expectRevert(IAuthorizable.AuthorizableInvalidSignerProof.selector);
        graphTallyCollector.authorizeSigner(users.delegator, proofDeadline, signerProof);
    }

    function testGraphTally_AuthorizeSigner_RevertWhen_AlreadyAuthroized() public useGateway {
        // Authorize signer
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        _authorizeSigner(signer, proofDeadline, signerProof);

        // Attempt to authorize signer again
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerAlreadyAuthorized.selector,
            users.gateway,
            signer,
            false
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.authorizeSigner(signer, proofDeadline, signerProof);
    }

    function testGraphTally_AuthorizeSigner_RevertWhen_AlreadyAuthroizedAfterRevoking() public useGateway {
        // Authorize signer
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        _authorizeSigner(signer, proofDeadline, signerProof);
        // Revoke signer
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _revokeAuthorizedSigner(signer);

        // Attempt to authorize signer again
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerAlreadyAuthorized.selector,
            users.gateway,
            signer,
            true
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.authorizeSigner(signer, proofDeadline, signerProof);
    }

    function testGraphTally_AuthorizeSigner_RevertWhen_ProofExpired() public useGateway {
        // Sign proof with payer
        uint256 proofDeadline = block.timestamp - 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);

        // Attempt to authorize delegator with expired proof
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableInvalidSignerProofDeadline.selector,
            proofDeadline,
            block.timestamp
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.authorizeSigner(users.delegator, proofDeadline, signerProof);
    }
}
