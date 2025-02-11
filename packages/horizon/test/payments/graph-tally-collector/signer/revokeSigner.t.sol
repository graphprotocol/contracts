// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphTallyCollector } from "../../../../contracts/interfaces/IGraphTallyCollector.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyRevokeAuthorizedSignerTest is GraphTallyTest {

    /*
     * TESTS
     */

    function testGraphTally_RevokeAuthorizedSigner() public useGateway useSigner {
        _thawSigner(signer);

        // Advance time to thaw signer
        skip(revokeSignerThawingPeriod + 1);

        _revokeAuthorizedSigner(signer);
    }

    function testGraphTally_RevokeAuthorizedSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.revokeAuthorizedSigner(signer);
    }
    
    function testGraphTally_RevokeAuthorizedSigner_RevertWhen_NotThawing() public useGateway useSigner {
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerNotThawing.selector,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.revokeAuthorizedSigner(signer);
    }

    function testGraphTally_RevokeAuthorizedSigner_RevertWhen_StillThawing() public useGateway useSigner {
        _thawSigner(signer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerStillThawing.selector,
            block.timestamp,
            block.timestamp + revokeSignerThawingPeriod
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.revokeAuthorizedSigner(signer);
    }
}
