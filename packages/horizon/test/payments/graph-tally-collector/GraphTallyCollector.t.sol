// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphTallyCollector } from "../../../contracts/interfaces/IGraphTallyCollector.sol";
import { IPaymentsCollector } from "../../../contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { GraphTallyCollector } from "../../../contracts/payments/collectors/GraphTallyCollector.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

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
        bytes32 messageHash = keccak256(abi.encodePacked(block.chainid, address(graphTallyCollector), _proofDeadline, msgSender));
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
        emit IGraphTallyCollector.SignerAuthorized(msgSender, _signer);

        graphTallyCollector.authorizeSigner(_signer, _proofDeadline, _proof);

        (address _payer, uint256 thawEndTimestamp, bool revoked) = graphTallyCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, 0);
        assertEq(revoked, false);
    }

    function _thawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEndTimestamp = block.timestamp + revokeSignerThawingPeriod;

        vm.expectEmit(address(graphTallyCollector));
        emit IGraphTallyCollector.SignerThawing(msgSender, _signer, expectedThawEndTimestamp);

        graphTallyCollector.thawSigner(_signer);

        (address _payer, uint256 thawEndTimestamp, bool revoked) = graphTallyCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, expectedThawEndTimestamp);
        assertEq(revoked, false);
    }

    function _cancelThawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        vm.expectEmit(address(graphTallyCollector));
        emit IGraphTallyCollector.SignerThawCanceled(msgSender, _signer, 0);

        graphTallyCollector.cancelThawSigner(_signer);

        (address _payer, uint256 thawEndTimestamp, bool revoked) = graphTallyCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, 0);
        assertEq(revoked, false);
    }

    function _revokeAuthorizedSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        (address beforePayer, uint256 beforeThawEndTimestamp, ) = graphTallyCollector.authorizedSigners(_signer);

        vm.expectEmit(address(graphTallyCollector));
        emit IGraphTallyCollector.SignerRevoked(msgSender, _signer);

        graphTallyCollector.revokeAuthorizedSigner(_signer);

        (address afterPayer, uint256 afterThawEndTimestamp, bool afterRevoked) = graphTallyCollector.authorizedSigners(
            _signer
        );

        assertEq(beforePayer, afterPayer);
        assertEq(beforeThawEndTimestamp, afterThawEndTimestamp);
        assertEq(afterRevoked, true);
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data) internal {
        __collect(_paymentType, _data, 0);
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data, uint256 _tokensToCollect) internal {
        __collect(_paymentType, _data, _tokensToCollect);
    }

    function __collect(
        IGraphPayments.PaymentTypes _paymentType,
        bytes memory _data,
        uint256 _tokensToCollect
    ) internal {
        (IGraphTallyCollector.SignedRAV memory signedRAV, ) = abi.decode(
            _data,
            (IGraphTallyCollector.SignedRAV, uint256)
        );
        bytes32 messageHash = graphTallyCollector.encodeRAV(signedRAV.rav);
        address _signer = ECDSA.recover(messageHash, signedRAV.signature);
        (address _payer, , ) = graphTallyCollector.authorizedSigners(_signer);
        uint256 tokensAlreadyCollected = graphTallyCollector.tokensCollected(
            signedRAV.rav.dataService,
            signedRAV.rav.collectionId,
            signedRAV.rav.serviceProvider,
            _payer
        );
        uint256 tokensToCollect = _tokensToCollect == 0
            ? signedRAV.rav.valueAggregate - tokensAlreadyCollected
            : _tokensToCollect;

        vm.expectEmit(address(graphTallyCollector));
        emit IPaymentsCollector.PaymentCollected(
            _paymentType,
            signedRAV.rav.collectionId,
            _payer,
            signedRAV.rav.serviceProvider,
            signedRAV.rav.dataService,
            tokensToCollect
        );
        vm.expectEmit(address(graphTallyCollector));
        emit IGraphTallyCollector.RAVCollected(
            signedRAV.rav.collectionId,
            _payer,
            signedRAV.rav.serviceProvider,
            signedRAV.rav.dataService,
            signedRAV.rav.timestampNs,
            signedRAV.rav.valueAggregate,
            signedRAV.rav.metadata,
            signedRAV.signature
        );
        uint256 tokensCollected = _tokensToCollect == 0
            ? graphTallyCollector.collect(_paymentType, _data)
            : graphTallyCollector.collect(_paymentType, _data, _tokensToCollect);

        uint256 tokensCollectedAfter = graphTallyCollector.tokensCollected(
            signedRAV.rav.dataService,
            signedRAV.rav.collectionId,
            signedRAV.rav.serviceProvider,
            _payer
        );
        assertEq(tokensCollected, tokensToCollect);
        assertEq(
            tokensCollectedAfter,
            _tokensToCollect == 0 ? signedRAV.rav.valueAggregate : tokensAlreadyCollected + _tokensToCollect
        );
    }
}
