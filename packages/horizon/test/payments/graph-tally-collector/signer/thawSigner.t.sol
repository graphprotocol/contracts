// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphTallyCollector } from "../../../../contracts/interfaces/IGraphTallyCollector.sol";

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
            IGraphTallyCollector.GraphTallyCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }

    function testGraphTally_ThawSigner_RevertWhen_AlreadyRevoked() public useGateway useSigner {
        _thawSigner(signer);
        skip(revokeSignerThawingPeriod + 1);
        _revokeAuthorizedSigner(signer);

        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorAuthorizationAlreadyRevoked.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }

    function testGraphTally_ThawSigner_RevertWhen_AlreadyThawing() public useGateway useSigner {
        _thawSigner(signer);

        (,uint256 thawEndTimestamp,) = graphTallyCollector.authorizedSigners(signer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerAlreadyThawing.selector,
            signer,
            thawEndTimestamp
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }
}
