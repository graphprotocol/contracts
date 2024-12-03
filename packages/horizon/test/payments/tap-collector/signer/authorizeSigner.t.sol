// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorAuthorizeSignerTest is TAPCollectorTest {

    uint256 constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /*
     * TESTS
     */

    function testTAPCollector_AuthorizeSigner(uint256 signerKey) public useGateway {
        signerKey = bound(signerKey, 1, SECP256K1_CURVE_ORDER - 1);
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerKey);
        _authorizeSigner(vm.addr(signerKey), proofDeadline, signerProof);
    }

    function testTAPCollector_AuthorizeSigner_RevertWhen_Invalid() public useGateway {
        // Sign proof with payer
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        
        // Attempt to authorize delegator with payer's proof
        bytes memory expectedError = abi.encodeWithSelector(ITAPCollector.TAPCollectorInvalidSignerProof.selector);
        vm.expectRevert(expectedError);
        tapCollector.authorizeSigner(users.delegator, proofDeadline, signerProof);
    }

    function testTAPCollector_AuthorizeSigner_RevertWhen_AlreadyAuthroized() public useGateway {
        // Authorize signer
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        _authorizeSigner(signer, proofDeadline, signerProof);

        // Attempt to authorize signer again
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerAlreadyAuthorized.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.authorizeSigner(signer, proofDeadline, signerProof);
    }

    function testTAPCollector_AuthorizeSigner_RevertWhen_AlreadyAuthroizedAfterRevoking() public useGateway {
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
            ITAPCollector.TAPCollectorSignerAlreadyAuthorized.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.authorizeSigner(signer, proofDeadline, signerProof);
    }

    function testTAPCollector_AuthorizeSigner_RevertWhen_ProofExpired() public useGateway {
        // Sign proof with payer
        uint256 proofDeadline = block.timestamp - 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        
        // Attempt to authorize delegator with expired proof
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorInvalidSignerProofDeadline.selector,
            proofDeadline,
            block.timestamp
        );
        vm.expectRevert(expectedError);
        tapCollector.authorizeSigner(users.delegator, proofDeadline, signerProof);
    }
}
