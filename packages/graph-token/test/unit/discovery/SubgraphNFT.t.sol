// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { VmSafe } from "forge-std/Vm.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { ISubgraphNFTLike } from "../interfaces/ISubgraphNFTLike.sol";

contract SubgraphNFTTest is ProtocolFixture {
    string internal constant SUBGRAPH_NFT = "SubgraphNFT.sol:SubgraphNFT";

    ISubgraphNFTLike internal nft;
    address internal minter = makeAddr("minter");
    address internal user = makeAddr("user");
    uint256 internal constant TOKEN_ID = 1;

    function setUp() public {
        governor = makeAddr("governor");
        nft = ISubgraphNFTLike(_deployPkg(SUBGRAPH_NFT, abi.encode(governor)));
        vm.prank(governor);
        nft.setMinter(minter);
    }

    function test_FoundrySubgraphNFTMatchesHardhat() public {
        vm.skip(vm.isContext(VmSafe.ForgeContext.Coverage));
        string memory json = vm.readFile("artifacts/contracts/discovery/SubgraphNFT.sol/SubgraphNFT.json");
        bytes memory hardhat = _stripMetadata(vm.parseJsonBytes(json, ".bytecode"));
        bytes memory foundry = _stripMetadata(vm.getCode(SUBGRAPH_NFT));
        assertGt(hardhat.length, 0);
        assertEq(foundry, hardhat);
    }

    function test_SetUp_SetsMinter() public view {
        assertEq(nft.minter(), minter);
    }

    // -- setMinter --

    function test_SetMinter_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(user);
        nft.setMinter(user);
    }

    function test_SetMinter_SetsMinter() public {
        vm.expectEmit(address(nft));
        emit ISubgraphNFTLike.MinterUpdated(user);
        vm.prank(governor);
        nft.setMinter(user);
        assertEq(nft.minter(), user);
    }

    // -- setTokenDescriptor --

    function test_SetTokenDescriptor_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(user);
        nft.setTokenDescriptor(address(0));
    }

    function test_SetTokenDescriptor_RevertWhen_NotContract() public {
        vm.expectRevert(bytes("NFT: Invalid token descriptor"));
        vm.prank(governor);
        nft.setTokenDescriptor(user);
    }

    function test_SetTokenDescriptor_SetsDescriptor() public {
        address descriptor = _deployPkg("SubgraphNFTDescriptor.sol:SubgraphNFTDescriptor", "");
        vm.expectEmit(address(nft));
        emit ISubgraphNFTLike.TokenDescriptorUpdated(descriptor);
        vm.prank(governor);
        nft.setTokenDescriptor(descriptor);
        assertEq(nft.tokenDescriptor(), descriptor);
    }

    function test_SetTokenDescriptor_AllowsZeroAddress() public {
        vm.prank(governor);
        nft.setTokenDescriptor(address(0));
        assertEq(nft.tokenDescriptor(), address(0));
    }

    // -- mint / burn / setSubgraphMetadata --

    function test_Mint_RevertWhen_NotMinter() public {
        vm.expectRevert(bytes("Must be a minter"));
        vm.prank(user);
        nft.mint(user, TOKEN_ID);
    }

    function test_Mint_MintsToken() public {
        vm.prank(minter);
        nft.mint(user, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), user);
    }

    function test_Burn_RevertWhen_NotMinter() public {
        vm.prank(minter);
        nft.mint(user, TOKEN_ID);
        vm.expectRevert(bytes("Must be a minter"));
        vm.prank(user);
        nft.burn(TOKEN_ID);
    }

    function test_Burn_BurnsToken() public {
        vm.startPrank(minter);
        nft.mint(user, TOKEN_ID);
        nft.burn(TOKEN_ID);
        vm.stopPrank();
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        nft.ownerOf(TOKEN_ID);
    }

    function test_SetSubgraphMetadata_RevertWhen_NotMinter() public {
        vm.expectRevert(bytes("Must be a minter"));
        vm.prank(user);
        nft.setSubgraphMetadata(TOKEN_ID, bytes32(uint256(1)));
    }

    function test_SetSubgraphMetadata_RevertWhen_NonexistentToken() public {
        vm.expectRevert(bytes("ERC721Metadata: URI set of nonexistent token"));
        vm.prank(minter);
        nft.setSubgraphMetadata(TOKEN_ID, bytes32(uint256(1)));
    }

    function test_SetSubgraphMetadata_EmitsEvent() public {
        vm.startPrank(minter);
        nft.mint(user, TOKEN_ID);
        vm.expectEmit(address(nft));
        emit ISubgraphNFTLike.SubgraphMetadataUpdated(TOKEN_ID, bytes32(uint256(1)));
        nft.setSubgraphMetadata(TOKEN_ID, bytes32(uint256(1)));
        vm.stopPrank();
    }

    // -- tokenURI --

    function test_TokenURI_RevertWhen_NonexistentToken() public {
        vm.expectRevert(bytes("ERC721Metadata: URI query for nonexistent token"));
        nft.tokenURI(TOKEN_ID);
    }

    function test_TokenURI_EmptyWithoutBaseOrMetadata() public {
        vm.prank(minter);
        nft.mint(user, TOKEN_ID);
        assertEq(nft.tokenURI(TOKEN_ID), "");
    }

    function test_TokenURI_MetadataOnlyWithoutBase() public {
        vm.startPrank(minter);
        nft.mint(user, TOKEN_ID);
        nft.setSubgraphMetadata(TOKEN_ID, bytes32(uint256(0xabcd)));
        vm.stopPrank();
        assertEq(nft.tokenURI(TOKEN_ID), "0xabcd");
    }

    function test_TokenURI_BaseAndMetadata() public {
        vm.prank(governor);
        nft.setBaseURI("ipfs://");
        vm.startPrank(minter);
        nft.mint(user, TOKEN_ID);
        nft.setSubgraphMetadata(TOKEN_ID, bytes32(uint256(0xabcd)));
        vm.stopPrank();
        assertEq(nft.tokenURI(TOKEN_ID), "ipfs://0xabcd");
    }

    function test_TokenURI_BaseAndTokenIdWithoutMetadata() public {
        vm.prank(governor);
        nft.setBaseURI("ipfs://");
        vm.prank(minter);
        nft.mint(user, TOKEN_ID);
        assertEq(nft.tokenURI(TOKEN_ID), "ipfs://0x01");
    }

    function test_TokenURI_UsesDescriptor() public {
        address descriptor = _deployPkg("SubgraphNFTDescriptor.sol:SubgraphNFTDescriptor", "");
        vm.prank(governor);
        nft.setTokenDescriptor(descriptor);
        vm.prank(minter);
        nft.mint(user, TOKEN_ID);
        assertEq(nft.tokenURI(TOKEN_ID), "QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51");
    }
}
