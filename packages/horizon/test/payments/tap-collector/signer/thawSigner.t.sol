// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorThawSignerTest is TAPCollectorTest {

    /*
     * TESTS
     */

    function testTAPCollector_ThawSigner() public useGateway useSigner {
        _thawSigner(signer);
    }

    function testTAPCollector_ThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.thawSigner(signer);
    }

    function testTAPCollector_ThawSigner_RevertWhen_AlreadyRevoked() public useGateway useSigner {
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _revokeAuthorizedSigner(signer);

        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorAuthorizationAlreadyRevoked.selector,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.thawSigner(signer);
    }

    function testTAPCollector_ThawSigner_RevertWhen_AlreadyThawing() public useGateway useSigner {
        _thawSigner(signer);

        (,uint256 thawEndTimestamp,) = tapCollector.authorizedSigners(signer);
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerAlreadyThawing.selector,
            signer,
            thawEndTimestamp
        );
        vm.expectRevert(expectedError);
        tapCollector.thawSigner(signer);
    }
}
