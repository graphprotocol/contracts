// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IGraphTallyCollector } from "@graphprotocol/interfaces/contracts/horizon/IGraphTallyCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAuthorizable } from "@graphprotocol/interfaces/contracts/horizon/IAuthorizable.sol";
import { PPMMath } from "../../../../contracts/libraries/PPMMath.sol";

import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../../shared/payments-escrow/PaymentsEscrowShared.t.sol";

contract GraphTallyTest is HorizonStakingSharedTest, PaymentsEscrowSharedTest {
    using PPMMath for uint256;

    address signer;
    uint256 signerPrivateKey;

    /*
     * MODIFIERS
     */

    modifier useSigner() {
        uint256 proofDeadline = block.timestamp + 1;
        bytes memory signerProof = _getSignerProof(proofDeadline, signerPrivateKey);
        _authorizeSigner(signer, proofDeadline, signerProof);
        _;
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
        vm.label({ account: signer, newLabel: "signer" });
    }

    /*
     * HELPERS
     */

    function _getSignerProof(uint256 _proofDeadline, uint256 _signer) internal returns (bytes memory) {
        (, address msgSender, ) = vm.readCallers();
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                block.chainid,
                address(graphTallyCollector),
                "authorizeSignerProof",
                _proofDeadline,
                msgSender
            )
        );
        bytes32 proofToDigest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signer, proofToDigest);
        return abi.encodePacked(r, s, v);
    }

    /*
     * ACTIONS
     */

    function _authorizeSigner(address _signer, uint256 _proofDeadline, bytes memory _proof) internal {
        (, address msgSender, ) = vm.readCallers();

        vm.expectEmit(address(graphTallyCollector));
        emit IAuthorizable.SignerAuthorized(msgSender, _signer);

        graphTallyCollector.authorizeSigner(_signer, _proofDeadline, _proof);
        assertTrue(graphTallyCollector.isAuthorized(msgSender, _signer));
        assertEq(graphTallyCollector.getThawEnd(_signer), 0);
    }

    function _thawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEndTimestamp = block.timestamp + REVOKE_SIGNER_THAWING_PERIOD;

        vm.expectEmit(address(graphTallyCollector));
        emit IAuthorizable.SignerThawing(msgSender, _signer, expectedThawEndTimestamp);

        graphTallyCollector.thawSigner(_signer);

        assertTrue(graphTallyCollector.isAuthorized(msgSender, _signer));
        assertEq(graphTallyCollector.getThawEnd(_signer), expectedThawEndTimestamp);
    }

    function _cancelThawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        vm.expectEmit(address(graphTallyCollector));
        emit IAuthorizable.SignerThawCanceled(msgSender, _signer, graphTallyCollector.getThawEnd(_signer));

        graphTallyCollector.cancelThawSigner(_signer);

        assertTrue(graphTallyCollector.isAuthorized(msgSender, _signer));
        assertEq(graphTallyCollector.getThawEnd(_signer), 0);
    }

    function _revokeAuthorizedSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        assertTrue(graphTallyCollector.isAuthorized(msgSender, _signer));
        assertLt(graphTallyCollector.getThawEnd(_signer), block.timestamp);

        vm.expectEmit(address(graphTallyCollector));
        emit IAuthorizable.SignerRevoked(msgSender, _signer);

        graphTallyCollector.revokeAuthorizedSigner(_signer);

        assertFalse(graphTallyCollector.isAuthorized(msgSender, _signer));
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data) internal {
        _collectRav(_paymentType, _data, 0);
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data, uint256 _tokensToCollect) internal {
        _collectRav(_paymentType, _data, _tokensToCollect);
    }

    function _collectRav(
        IGraphPayments.PaymentTypes _paymentType,
        bytes memory _data,
        uint256 _tokensToCollect
    ) internal {
        (IGraphTallyCollector.SignedRAV memory signedRav, ) = abi.decode(
            _data,
            (IGraphTallyCollector.SignedRAV, uint256)
        );
        uint256 tokensAlreadyCollected = graphTallyCollector.tokensCollected(
            signedRav.rav.dataService,
            signedRav.rav.collectionId,
            signedRav.rav.serviceProvider,
            signedRav.rav.payer
        );
        uint256 tokensToCollect = _tokensToCollect == 0
            ? signedRav.rav.valueAggregate - tokensAlreadyCollected
            : _tokensToCollect;

        vm.expectEmit(address(graphTallyCollector));
        emit IPaymentsCollector.PaymentCollected(
            _paymentType,
            signedRav.rav.collectionId,
            signedRav.rav.payer,
            signedRav.rav.serviceProvider,
            signedRav.rav.dataService,
            tokensToCollect
        );
        vm.expectEmit(address(graphTallyCollector));
        emit IGraphTallyCollector.RAVCollected(
            signedRav.rav.collectionId,
            signedRav.rav.payer,
            signedRav.rav.serviceProvider,
            signedRav.rav.dataService,
            signedRav.rav.timestampNs,
            signedRav.rav.valueAggregate,
            signedRav.rav.metadata,
            signedRav.signature
        );
        uint256 tokensCollected = _tokensToCollect == 0
            ? graphTallyCollector.collect(_paymentType, _data)
            : graphTallyCollector.collect(_paymentType, _data, _tokensToCollect);

        uint256 tokensCollectedAfter = graphTallyCollector.tokensCollected(
            signedRav.rav.dataService,
            signedRav.rav.collectionId,
            signedRav.rav.serviceProvider,
            signedRav.rav.payer
        );
        assertEq(tokensCollected, tokensToCollect);
        assertEq(
            tokensCollectedAfter,
            _tokensToCollect == 0 ? signedRav.rav.valueAggregate : tokensAlreadyCollected + _tokensToCollect
        );
    }
}
