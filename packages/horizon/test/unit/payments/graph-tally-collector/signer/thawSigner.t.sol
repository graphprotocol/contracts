// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAuthorizable } from "@graphprotocol/interfaces/contracts/horizon/IAuthorizable.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyThawSignerTest is GraphTallyTest {
    /*
     * TESTS
     */

    function testGraphTally_ThawSigner() public useGateway useSigner {
        _thawSigner(signer);
    }

    function testGraphTally_ThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }

    function testGraphTally_ThawSigner_RevertWhen_AlreadyRevoked() public useGateway useSigner {
        _thawSigner(signer);
        skip(REVOKE_SIGNER_THAWING_PERIOD + 1);
        _revokeAuthorizedSigner(signer);

        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }

    function testGraphTally_ThawSigner_AlreadyThawing() public useGateway useSigner {
        _thawSigner(signer);
        uint256 originalThawEnd = graphTallyCollector.getThawEnd(signer);
        skip(1);

        graphTallyCollector.thawSigner(signer);
        uint256 currentThawEnd = graphTallyCollector.getThawEnd(signer);
        vm.assertEq(originalThawEnd, block.timestamp + REVOKE_SIGNER_THAWING_PERIOD - 1);
        vm.assertEq(currentThawEnd, block.timestamp + REVOKE_SIGNER_THAWING_PERIOD);
    }
}
