// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { ITAPCollector } from "../../../contracts/interfaces/ITAPCollector.sol";
import { IPaymentsCollector } from "../../../contracts/interfaces/IPaymentsCollector.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { TAPCollector } from "../../../contracts/payments/collectors/TAPCollector.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../../shared/payments-escrow/PaymentsEscrowShared.t.sol";

contract TAPCollectorTest is HorizonStakingSharedTest, PaymentsEscrowSharedTest {
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
        bytes32 messageHash = keccak256(abi.encodePacked(block.chainid, _proofDeadline, msgSender));
        bytes32 proofToDigest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signer, proofToDigest);
        return abi.encodePacked(r, s, v);
    }

    /*
     * ACTIONS
     */

    function _authorizeSigner(address _signer, uint256 _proofDeadline, bytes memory _proof) internal {
        (, address msgSender, ) = vm.readCallers();
        
        vm.expectEmit(address(tapCollector));
        emit ITAPCollector.SignerAuthorized(msgSender, _signer);
        
        tapCollector.authorizeSigner(_signer, _proofDeadline, _proof);
        
        (address _payer, uint256 thawEndTimestamp) = tapCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, 0);
    }

    function _thawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEndTimestamp = block.timestamp + revokeSignerThawingPeriod;

        vm.expectEmit(address(tapCollector));
        emit ITAPCollector.SignerThawing(msgSender, _signer, expectedThawEndTimestamp);

        tapCollector.thawSigner(_signer);

        (address _payer, uint256 thawEndTimestamp) = tapCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, expectedThawEndTimestamp);
    }

    function _cancelThawSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        vm.expectEmit(address(tapCollector));
        emit ITAPCollector.SignerThawCanceled(msgSender, _signer, 0);

        tapCollector.cancelThawSigner(_signer);

        (address _payer, uint256 thawEndTimestamp) = tapCollector.authorizedSigners(_signer);
        assertEq(_payer, msgSender);
        assertEq(thawEndTimestamp, 0);
    }

    function _revokeAuthorizedSigner(address _signer) internal {
        (, address msgSender, ) = vm.readCallers();

        vm.expectEmit(address(tapCollector));
        emit ITAPCollector.SignerRevoked(msgSender, _signer);

        tapCollector.revokeAuthorizedSigner(_signer);

        (address _payer, uint256 thawEndTimestamp) = tapCollector.authorizedSigners(_signer);
        assertEq(_payer, address(0));
        assertEq(thawEndTimestamp, 0);
    }

    function _collect(IGraphPayments.PaymentTypes _paymentType, bytes memory _data) internal {
        (ITAPCollector.SignedRAV memory signedRAV, uint256 dataServiceCut) = abi.decode(_data, (ITAPCollector.SignedRAV, uint256));
        bytes32 messageHash = tapCollector.encodeRAV(signedRAV.rav);
        address _signer = ECDSA.recover(messageHash, signedRAV.signature);
        (address _payer, ) = tapCollector.authorizedSigners(_signer);
        uint256 tokensAlreadyCollected = tapCollector.tokensCollected(signedRAV.rav.dataService, signedRAV.rav.serviceProvider, _payer);
        uint256 tokensToCollect = signedRAV.rav.valueAggregate - tokensAlreadyCollected;
        uint256 tokensDataService = tokensToCollect.mulPPM(dataServiceCut);
        
        vm.expectEmit(address(tapCollector));
        emit IPaymentsCollector.PaymentCollected(
            _paymentType, 
            _payer,
            signedRAV.rav.serviceProvider,
            tokensToCollect,
            signedRAV.rav.dataService,
            tokensDataService
        );
        emit ITAPCollector.RAVCollected(
            _payer,
            signedRAV.rav.dataService,
            signedRAV.rav.serviceProvider,
            signedRAV.rav.timestampNs,
            signedRAV.rav.valueAggregate,
            signedRAV.rav.metadata,
            signedRAV.signature
        );
        
        uint256 tokensCollected = tapCollector.collect(_paymentType, _data);
        assertEq(tokensCollected, tokensToCollect);

        uint256 tokensCollectedAfter = tapCollector.tokensCollected(signedRAV.rav.dataService, signedRAV.rav.serviceProvider, _payer);
        assertEq(tokensCollectedAfter, signedRAV.rav.valueAggregate);
    }
}
