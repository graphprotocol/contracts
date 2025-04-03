// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { Authorizable } from "../../../contracts/utilities/Authorizable.sol";
import { IAuthorizable } from "../../../contracts/interfaces/IAuthorizable.sol";
import { Bounder } from "../utils/Bounder.t.sol";

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract AuthorizableImp is Authorizable {
    constructor(uint256 _revokeAuthorizationThawingPeriod) Authorizable(_revokeAuthorizationThawingPeriod) {}
}

contract AuthorizableTest is Test, Bounder {
    AuthorizableImp public authorizable;
    AuthorizableHelper authHelper;

    modifier withFuzzyThaw(uint256 _thawPeriod) {
        // Max thaw period is 1 year to allow for thawing tests
        _thawPeriod = bound(_thawPeriod, 1, 60 * 60 * 24 * 365);
        setupAuthorizable(new AuthorizableImp(_thawPeriod));
        _;
    }

    function setUp() public virtual {
        setupAuthorizable(new AuthorizableImp(0));
    }

    function setupAuthorizable(AuthorizableImp _authorizable) internal {
        authorizable = _authorizable;
        authHelper = new AuthorizableHelper(authorizable);
    }

    function test_AuthorizeSigner(uint256 _unboundedKey, address _authorizer) public {
        vm.assume(_authorizer != address(0));
        uint256 signerKey = boundKey(_unboundedKey);

        authHelper.authorizeSignerWithChecks(_authorizer, signerKey);
    }

    function test_AuthorizeSigner_Revert_WhenAlreadyAuthorized(
        uint256[] memory _unboundedAuthorizers,
        uint256 _unboundedKey
    ) public {
        vm.assume(_unboundedAuthorizers.length > 1);
        address[] memory authorizers = new address[](_unboundedAuthorizers.length);
        for (uint256 i = 0; i < authorizers.length; i++) {
            authorizers[i] = boundAddr(_unboundedAuthorizers[i]);
        }
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);

        address validAuthorizer = authorizers[0];
        authHelper.authorizeSignerWithChecks(validAuthorizer, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerAlreadyAuthorized.selector,
            validAuthorizer,
            signer,
            false
        );

        for (uint256 i = 0; i < authorizers.length; i++) {
            vm.expectRevert(expectedErr);
            vm.prank(authorizers[i]);
            authorizable.authorizeSigner(signer, 0, "");
        }
    }

    function test_AuthorizeSigner_Revert_WhenInvalidProofDeadline(uint256 _proofDeadline, uint256 _now) public {
        _proofDeadline = bound(_proofDeadline, 0, _now);
        vm.warp(_now);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableInvalidSignerProofDeadline.selector,
            _proofDeadline,
            _now
        );
        vm.expectRevert(expectedErr);
        authorizable.authorizeSigner(address(0), _proofDeadline, "");
    }

    function test_AuthorizeSigner_Revert_WhenAuthorizableInvalidSignerProof(
        uint256 _now,
        uint256 _unboundedAuthorizer,
        uint256 _unboundedKey,
        uint256 _proofDeadline,
        uint256 _chainid,
        uint256 _wrong
    ) public {
        _now = bound(_now, 0, type(uint256).max - 1);
        address authorizer = boundAddr(_unboundedAuthorizer);
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);
        _proofDeadline = boundTimestampMin(_proofDeadline, _now + 1);
        vm.assume(_wrong != _proofDeadline);
        _chainid = boundChainId(_chainid);
        vm.assume(_wrong != _chainid);
        (uint256 wrongKey, address wrongAddress) = boundAddrAndKey(_wrong);
        vm.assume(wrongKey != signerKey);
        vm.assume(wrongAddress != authorizer);

        vm.chainId(_chainid);
        vm.warp(_now);

        bytes memory validProof = authHelper.generateAuthorizationProof(
            _chainid,
            address(authorizable),
            _proofDeadline,
            authorizer,
            signerKey
        );
        bytes[5] memory proofs = [
            authHelper.generateAuthorizationProof(_wrong, address(authorizable), _proofDeadline, authorizer, signerKey),
            authHelper.generateAuthorizationProof(_chainid, wrongAddress, _proofDeadline, authorizer, signerKey),
            authHelper.generateAuthorizationProof(_chainid, address(authorizable), _wrong, authorizer, signerKey),
            authHelper.generateAuthorizationProof(
                _chainid,
                address(authorizable),
                _proofDeadline,
                wrongAddress,
                signerKey
            ),
            authHelper.generateAuthorizationProof(_chainid, address(authorizable), _proofDeadline, authorizer, wrongKey)
        ];

        for (uint256 i = 0; i < proofs.length; i++) {
            vm.expectRevert(IAuthorizable.AuthorizableInvalidSignerProof.selector);
            vm.prank(authorizer);
            authorizable.authorizeSigner(signer, _proofDeadline, proofs[i]);
        }

        vm.prank(authorizer);
        authorizable.authorizeSigner(signer, _proofDeadline, validProof);
        authHelper.assertAuthorized(authorizer, signer);
    }

    function test_ThawSigner(address _authorizer, uint256 _unboundedKey, uint256 _thaw) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        uint256 signerKey = boundKey(_unboundedKey);

        authHelper.authorizeAndThawSignerWithChecks(_authorizer, signerKey);
    }

    function test_ThawSigner_Revert_WhenNotAuthorized(address _authorizer, address _signer) public {
        vm.assume(_authorizer != address(0));
        vm.assume(_signer != address(0));

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            _signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.thawSigner(_signer);
    }

    function test_ThawSigner_Revert_WhenAuthorizationRevoked(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);
        authHelper.authorizeAndRevokeSignerWithChecks(_authorizer, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.thawSigner(signer);
    }

    function test_CancelThawSigner(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);

        authHelper.authorizeAndThawSignerWithChecks(_authorizer, signerKey);
        vm.expectEmit(address(authorizable));
        emit IAuthorizable.SignerThawCanceled(_authorizer, signer, authorizable.getThawEnd(signer));
        vm.prank(_authorizer);
        authorizable.cancelThawSigner(signer);

        authHelper.assertAuthorized(_authorizer, signer);
    }

    function test_CancelThawSigner_Revert_When_NotAuthorized(address _authorizer, address _signer) public {
        vm.assume(_authorizer != address(0));
        vm.assume(_signer != address(0));

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            _signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.cancelThawSigner(_signer);
    }

    function test_CancelThawSigner_Revert_WhenAuthorizationRevoked(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);
        authHelper.authorizeAndRevokeSignerWithChecks(_authorizer, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.cancelThawSigner(signer);
    }

    function test_CancelThawSigner_Revert_When_NotThawing(address _authorizer, uint256 _unboundedKey) public {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);

        authHelper.authorizeSignerWithChecks(_authorizer, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(IAuthorizable.AuthorizableSignerNotThawing.selector, signer);
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.cancelThawSigner(signer);
    }

    function test_RevokeAuthorizedSigner(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        uint256 signerKey = boundKey(_unboundedKey);

        authHelper.authorizeAndRevokeSignerWithChecks(_authorizer, signerKey);
    }

    function test_RevokeAuthorizedSigner_Revert_WhenNotAuthorized(address _authorizer, address _signer) public {
        vm.assume(_authorizer != address(0));
        vm.assume(_signer != address(0));

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            _signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.revokeAuthorizedSigner(_signer);
    }

    function test_RevokeAuthorizedSigner_Revert_WhenAuthorizationRevoked(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);
        authHelper.authorizeAndRevokeSignerWithChecks(_authorizer, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            _authorizer,
            signer
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.revokeAuthorizedSigner(signer);
    }

    function test_RevokeAuthorizedSigner_Revert_WhenNotThawing(address _authorizer, uint256 _unboundedKey) public {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);

        authHelper.authorizeSignerWithChecks(_authorizer, signerKey);
        bytes memory expectedErr = abi.encodeWithSelector(IAuthorizable.AuthorizableSignerNotThawing.selector, signer);
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.revokeAuthorizedSigner(signer);
    }

    function test_RevokeAuthorizedSigner_Revert_WhenStillThawing(
        address _authorizer,
        uint256 _unboundedKey,
        uint256 _thaw,
        uint256 _skip
    ) public withFuzzyThaw(_thaw) {
        vm.assume(_authorizer != address(0));
        (uint256 signerKey, address signer) = boundAddrAndKey(_unboundedKey);

        authHelper.authorizeAndThawSignerWithChecks(_authorizer, signerKey);

        _skip = bound(_skip, 0, authorizable.REVOKE_AUTHORIZATION_THAWING_PERIOD() - 1);
        skip(_skip);
        bytes memory expectedErr = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerStillThawing.selector,
            block.timestamp,
            block.timestamp - _skip + authorizable.REVOKE_AUTHORIZATION_THAWING_PERIOD()
        );
        vm.expectRevert(expectedErr);
        vm.prank(_authorizer);
        authorizable.revokeAuthorizedSigner(signer);
    }

    function test_IsAuthorized_Revert_WhenZero(address signer) public view {
        authHelper.assertNotAuthorized(address(0), signer);
    }
}

contract AuthorizableHelper is Test {
    AuthorizableImp internal authorizable;

    constructor(AuthorizableImp _authorizable) {
        authorizable = _authorizable;
    }

    function authorizeAndThawSignerWithChecks(address _authorizer, uint256 _signerKey) public {
        address signer = vm.addr(_signerKey);
        authorizeSignerWithChecks(_authorizer, _signerKey);

        uint256 thawEndTimestamp = block.timestamp + authorizable.REVOKE_AUTHORIZATION_THAWING_PERIOD();
        vm.expectEmit(address(authorizable));
        emit IAuthorizable.SignerThawing(_authorizer, signer, thawEndTimestamp);
        vm.prank(_authorizer);
        authorizable.thawSigner(signer);

        assertAuthorized(_authorizer, signer);
    }

    function authorizeAndRevokeSignerWithChecks(address _authorizer, uint256 _signerKey) public {
        address signer = vm.addr(_signerKey);
        authorizeAndThawSignerWithChecks(_authorizer, _signerKey);
        skip(authorizable.REVOKE_AUTHORIZATION_THAWING_PERIOD() + 1);
        vm.expectEmit(address(authorizable));
        emit IAuthorizable.SignerRevoked(_authorizer, signer);
        vm.prank(_authorizer);
        authorizable.revokeAuthorizedSigner(signer);

        assertNotAuthorized(_authorizer, signer);
    }

    function authorizeSignerWithChecks(address _authorizer, uint256 _signerKey) public {
        address signer = vm.addr(_signerKey);
        assertNotAuthorized(_authorizer, signer);

        uint256 proofDeadline = block.timestamp + 1;
        bytes memory proof = generateAuthorizationProof(
            block.chainid,
            address(authorizable),
            proofDeadline,
            _authorizer,
            _signerKey
        );
        vm.expectEmit(address(authorizable));
        emit IAuthorizable.SignerAuthorized(_authorizer, signer);
        vm.prank(_authorizer);
        authorizable.authorizeSigner(signer, proofDeadline, proof);

        assertAuthorized(_authorizer, signer);
    }

    function assertNotAuthorized(address _authorizer, address _signer) public view {
        assertFalse(authorizable.isAuthorized(_authorizer, _signer), "Should not be authorized");
    }

    function assertAuthorized(address _authorizer, address _signer) public view {
        assertTrue(authorizable.isAuthorized(_authorizer, _signer), "Should be authorized");
    }

    function generateAuthorizationProof(
        uint256 _chainId,
        address _verifyingContract,
        uint256 _proofDeadline,
        address _authorizer,
        uint256 _signerPrivateKey
    ) public pure returns (bytes memory) {
        // Generate the message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(_chainId, _verifyingContract, "authorizeSignerProof", _proofDeadline, _authorizer)
        );

        // Generate the digest to sign
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, digest);

        // Encode the signature
        return abi.encodePacked(r, s, v);
    }
}
