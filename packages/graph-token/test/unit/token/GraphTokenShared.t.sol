// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";

/// Cases shared by GraphToken (L1) and L2GraphToken; only the EIP-712 salt differs
abstract contract GraphTokenSharedTest is ProtocolFixture {
    bytes32 internal constant L1_SALT = 0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa;
    bytes32 internal constant L2_SALT = 0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591;

    address internal me;
    uint256 internal mePk;
    address internal other;
    uint256 internal otherPk;

    function _token() internal view virtual returns (IGraphTokenLike);

    function _salt() internal pure virtual returns (bytes32);

    /// Call after the token is deployed
    function _setUpShared() internal {
        (me, mePk) = makeAddrAndKey("me");
        (other, otherPk) = makeAddrAndKey("other");

        vm.prank(governor);
        _token().mint(me, 10_000 ether);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
                    ),
                    keccak256("Graph Token"),
                    keccak256("0"),
                    block.chainid,
                    address(_token()),
                    _salt()
                )
            );
    }

    function _permitDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _domainSeparator(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            owner,
                            spender,
                            value,
                            nonce,
                            deadline
                        )
                    )
                )
            );
    }

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    function _permit(uint256 value, uint256 deadline) internal view returns (Permit memory) {
        return Permit(me, other, value, _token().nonces(me), deadline);
    }

    /// Signs `p` with `pk` and submits it
    function _submitPermit(Permit memory p, uint256 pk) internal {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _permitDigest(p.owner, p.spender, p.value, p.nonce, p.deadline));
        _token().permit(p.owner, p.spender, p.value, p.deadline, v, r, s);
    }

    // -- permit --

    function test_Permit_PermitsTokenAllowance() public {
        uint256 tokensToApprove = 1000 ether;
        Permit memory p = _permit(tokensToApprove, 0);

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.Approval(p.owner, p.spender, tokensToApprove);
        _submitPermit(p, mePk);

        assertEq(_token().allowance(me, other), tokensToApprove);

        vm.prank(other);
        _token().transferFrom(me, other, 100 ether);
    }

    function test_Permit_PermitsMaxTokenAllowance() public {
        Permit memory p = _permit(type(uint256).max, 0);

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.Approval(p.owner, p.spender, type(uint256).max);
        _submitPermit(p, mePk);

        assertEq(_token().allowance(me, other), type(uint256).max);

        vm.prank(other);
        _token().transferFrom(me, other, 100 ether);
    }

    function test_Permit_RevertWhen_TransferExceedsPermit() public {
        uint256 tokensToApprove = 1000 ether;
        _submitPermit(_permit(tokensToApprove, 0), mePk);

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        vm.prank(other);
        _token().transferFrom(me, other, 1001 ether);

        vm.prank(other);
        _token().transferFrom(me, other, tokensToApprove);
    }

    function test_Permit_RevertWhen_NonceReused() public {
        Permit memory p = _permit(type(uint256).max, 0);
        _submitPermit(p, mePk);

        vm.expectRevert(bytes("GRT: invalid permit"));
        this.submitPermit(p, mePk);
    }

    function test_Permit_RevertWhen_Expired() public {
        vm.warp(1_700_000_000);
        Permit memory p = _permit(type(uint256).max, block.timestamp - 1);

        vm.expectRevert(bytes("GRT: expired permit"));
        this.submitPermit(p, mePk);
    }

    function test_Permit_RevertWhen_HolderDoesNotMatch() public {
        Permit memory p = _permit(type(uint256).max, 0);

        vm.expectRevert(bytes("GRT: invalid permit"));
        this.submitPermit(p, otherPk);
    }

    function test_Permit_DeniesTransferFromAfterPermitDenied() public {
        _submitPermit(_permit(type(uint256).max, 0), mePk);
        _submitPermit(_permit(0, 0), mePk);

        assertEq(_token().allowance(me, other), 0);

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        vm.prank(other);
        _token().transferFrom(me, other, 100 ether);
    }

    /// External wrapper so vm.expectRevert targets the permit call and not the signing cheatcode
    function submitPermit(Permit memory p, uint256 pk) external {
        _submitPermit(p, pk);
    }

    // -- mint --

    function test_Mint_RevertWhen_NotMinter() public {
        vm.expectRevert(bytes("Only minter can call"));
        vm.prank(me);
        _token().mint(me, 100 ether);
    }

    function test_AddMinter_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        _token().addMinter(me);
    }

    function test_AddMinter_AddsMinter() public {
        assertFalse(_token().isMinter(me));

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.MinterAdded(me);
        vm.prank(governor);
        _token().addMinter(me);

        assertTrue(_token().isMinter(me));
    }

    function test_Mint_MintsWhenMinter() public {
        vm.prank(governor);
        _token().addMinter(me);
        uint256 before = _token().balanceOf(me);
        uint256 tokensToMint = 100 ether;

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.Transfer(address(0), me, tokensToMint);
        vm.prank(me);
        _token().mint(me, tokensToMint);

        assertEq(_token().balanceOf(me), before + tokensToMint);
    }

    function test_Mint_MintsWhenGovernor() public {
        uint256 before = _token().balanceOf(me);

        vm.prank(governor);
        _token().mint(me, 100 ether);

        assertEq(_token().balanceOf(me), before + 100 ether);
    }

    function test_RemoveMinter_RevertWhen_NotGovernor() public {
        vm.prank(governor);
        _token().addMinter(me);

        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        _token().removeMinter(me);
    }

    function test_RemoveMinter_RemovesMinter() public {
        vm.prank(governor);
        _token().addMinter(me);

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.MinterRemoved(me);
        vm.prank(governor);
        _token().removeMinter(me);

        assertFalse(_token().isMinter(me));
    }

    function test_RenounceMinter_RenouncesMinter() public {
        vm.prank(governor);
        _token().addMinter(me);

        vm.expectEmit(address(_token()));
        emit IGraphTokenLike.MinterRemoved(me);
        vm.prank(me);
        _token().renounceMinter();

        assertFalse(_token().isMinter(me));
    }
}
