// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { ProtocolFixture } from "./ProtocolFixture.t.sol";
import { L2GatewayMock } from "../mocks/L2GatewayMock.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";
import { IL2CurationLike } from "../interfaces/IL2CurationLike.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";
import { ISubgraphNFTLike } from "../interfaces/ISubgraphNFTLike.sol";

/// L2 discovery stack: L2GraphToken, L2Curation, SubgraphNFT and L2GNS, with a mock L2 gateway.
/// There is no staking, rewards manager or epoch manager.
abstract contract DiscoveryTest is ProtocolFixture {
    string internal constant TOKEN_ARTIFACTS = "node_modules/@graphprotocol/graph-token/artifacts/contracts/";
    string internal constant L2_GRAPH_TOKEN =
        string.concat(TOKEN_ARTIFACTS, "l2/token/L2GraphToken.sol/L2GraphToken.json");
    string internal constant GRAPH_CURATION_TOKEN = "GraphCurationToken.sol:GraphCurationToken";
    string internal constant L2_CURATION = "L2Curation.sol:L2Curation";
    string internal constant SUBGRAPH_NFT = "SubgraphNFT.sol:SubgraphNFT";
    string internal constant SUBGRAPH_NFT_DESCRIPTOR = "SubgraphNFTDescriptor.sol:SubgraphNFTDescriptor";
    string internal constant L2_GNS = "L2GNS.sol:L2GNS";

    IGraphTokenLike internal grt;
    IL2CurationLike internal curation;
    IL2GNSLike internal gns;
    ISubgraphNFTLike internal nft;
    L2GatewayMock internal gatewayMock;
    address internal curationTokenMaster;

    address internal me = makeAddr("me");
    address internal other = makeAddr("other");
    address internal curator = makeAddr("curator");
    address internal attacker = makeAddr("attacker");
    address internal l1GNS = makeAddr("l1GNS");
    address internal subgraphService = makeAddr("subgraphService");

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        _deployProtocolBase();

        grt = IGraphTokenLike(
            _deployBehindProxy(
                _deployArtifact(L2_GRAPH_TOKEN, ""),
                abi.encodeWithSignature("initialize(address)", governor)
            )
        );
        gatewayMock = new L2GatewayMock(address(grt));
        vm.startPrank(governor);
        grt.addMinter(address(gatewayMock));
        grt.addMinter(governor);
        vm.stopPrank();

        curationTokenMaster = _deployPkg(GRAPH_CURATION_TOKEN, "");

        curation = IL2CurationLike(
            _deployBehindProxy(
                _deployPkg(L2_CURATION, ""),
                abi.encodeCall(IL2CurationLike.initialize, (address(controller), curationTokenMaster, 0, 1))
            )
        );

        nft = ISubgraphNFTLike(_deployPkg(SUBGRAPH_NFT, abi.encode(governor)));
        address descriptor = _deployPkg(SUBGRAPH_NFT_DESCRIPTOR, "");
        vm.prank(governor);
        nft.setTokenDescriptor(descriptor);

        gns = IL2GNSLike(
            _deployBehindProxy(
                _deployPkg(L2_GNS, ""),
                abi.encodeCall(IL2GNSLike.initialize, (address(controller), address(nft)))
            )
        );
        vm.prank(governor);
        nft.setMinter(address(gns));

        _registerContract("GraphToken", address(grt));
        _registerContract("Curation", address(curation));
        _registerContract("GNS", address(gns));
        _registerContract("GraphTokenGateway", address(gatewayMock));
        IManaged(address(curation)).syncAllContracts();
        IManaged(address(gns)).syncAllContracts();

        gns.approveAll();
        vm.startPrank(governor);
        gns.setCounterpartGNSAddress(l1GNS);
        curation.setSubgraphService(subgraphService);
        vm.stopPrank();
    }
}
