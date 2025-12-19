// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { BurnMintGRT } from "../../../contracts/token/BurnMintGRT.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract BurnMintGRTTest is Test {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Test accounts
    address public admin;
    address public minter;
    address public burner;
    address public user;
    address public proxyAdmin;

    // Token
    BurnMintGRT public token;
    BurnMintGRT public tokenImpl;

    // Constants
    string public constant NAME = "Graph Token";
    string public constant SYMBOL = "GRT";
    uint8 public constant DECIMALS = 18;
    uint256 public constant MAX_SUPPLY = 10_000_000_000 ether;
    uint256 public constant AMOUNT = 1000 ether;

    // Signer for permit tests
    uint256 internal constant SIGNER_PRIVATE_KEY = 0xA11CE;
    address internal signer;

    function setUp() public {
        // Create test accounts
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        burner = makeAddr("burner");
        user = makeAddr("user");
        proxyAdmin = makeAddr("proxyAdmin");
        signer = vm.addr(SIGNER_PRIVATE_KEY);

        // Deploy implementation
        tokenImpl = new BurnMintGRT();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            BurnMintGRT.initialize.selector,
            NAME,
            SYMBOL,
            DECIMALS,
            MAX_SUPPLY,
            0, // no premint
            admin
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(tokenImpl),
            proxyAdmin,
            initData
        );

        token = BurnMintGRT(address(proxy));

        // Grant roles
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        vm.stopPrank();
    }

    // ================================================================
    // │                      Initialization Tests                     │
    // ================================================================

    function test_Initialize() public view {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Initialize_WithPremint() public {
        uint256 premint = 1000 ether;

        bytes memory initData = abi.encodeWithSelector(
            BurnMintGRT.initialize.selector,
            NAME,
            SYMBOL,
            DECIMALS,
            MAX_SUPPLY,
            premint,
            admin
        );

        BurnMintGRT impl = new BurnMintGRT();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            proxyAdmin,
            initData
        );

        BurnMintGRT newToken = BurnMintGRT(address(proxy));

        assertEq(newToken.totalSupply(), premint);
        assertEq(newToken.balanceOf(admin), premint);
    }

    function test_Initialize_RevertWhen_PremintExceedsMaxSupply() public {
        uint256 maxSupply = 100 ether;
        uint256 premint = 101 ether;

        bytes memory initData = abi.encodeWithSelector(
            BurnMintGRT.initialize.selector,
            NAME,
            SYMBOL,
            DECIMALS,
            maxSupply,
            premint,
            admin
        );

        BurnMintGRT impl = new BurnMintGRT();

        vm.expectRevert(abi.encodeWithSelector(BurnMintGRT.BurnMintGRT__MaxSupplyExceeded.selector, premint));
        new TransparentUpgradeableProxy(address(impl), proxyAdmin, initData);
    }

    // ================================================================
    // │                      ERC165 Tests                            │
    // ================================================================

    function test_SupportsInterface() public view {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(token.supportsInterface(type(IERC20Permit).interfaceId));
    }

    // ================================================================
    // │                      Mint Tests                              │
    // ================================================================

    function test_Mint() public {
        vm.prank(minter);
        token.mint(user, AMOUNT);

        assertEq(token.balanceOf(user), AMOUNT);
        assertEq(token.totalSupply(), AMOUNT);
    }

    function test_Mint_Fuzz(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);

        vm.prank(minter);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount);
    }

    function test_Mint_RevertWhen_NotMinter() public {
        vm.expectRevert();
        vm.prank(user);
        token.mint(user, AMOUNT);
    }

    function test_Mint_RevertWhen_ExceedsMaxSupply() public {
        vm.prank(minter);
        token.mint(user, MAX_SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(BurnMintGRT.BurnMintGRT__MaxSupplyExceeded.selector, MAX_SUPPLY + 1)
        );
        vm.prank(minter);
        token.mint(user, 1);
    }

    function test_Mint_RevertWhen_ToSelf() public {
        vm.expectRevert(
            abi.encodeWithSelector(BurnMintGRT.BurnMintGRT__InvalidRecipient.selector, address(token))
        );
        vm.prank(minter);
        token.mint(address(token), AMOUNT);
    }

    // ================================================================
    // │                      Burn Tests                              │
    // ================================================================

    function test_Burn() public {
        // Mint first
        vm.prank(minter);
        token.mint(burner, AMOUNT);

        // Burn
        vm.prank(burner);
        token.burn(AMOUNT);

        assertEq(token.balanceOf(burner), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_BurnFrom() public {
        // Mint to user
        vm.prank(minter);
        token.mint(user, AMOUNT);

        // User approves burner
        vm.prank(user);
        token.approve(burner, AMOUNT);

        // Burner burns from user
        vm.prank(burner);
        token.burnFrom(user, AMOUNT);

        assertEq(token.balanceOf(user), 0);
    }

    function test_Burn_Address_Alias() public {
        // Mint to user
        vm.prank(minter);
        token.mint(user, AMOUNT);

        // User approves burner
        vm.prank(user);
        token.approve(burner, AMOUNT);

        // Use the burn(address, uint256) overload
        vm.prank(burner);
        token.burn(user, AMOUNT);

        assertEq(token.balanceOf(user), 0);
    }

    function test_Burn_RevertWhen_NotBurner() public {
        vm.prank(minter);
        token.mint(user, AMOUNT);

        vm.expectRevert();
        vm.prank(user);
        token.burn(AMOUNT);
    }

    // ================================================================
    // │                      Transfer Tests                          │
    // ================================================================

    function test_Transfer() public {
        vm.prank(minter);
        token.mint(user, AMOUNT);

        vm.prank(user);
        token.transfer(admin, AMOUNT);

        assertEq(token.balanceOf(admin), AMOUNT);
        assertEq(token.balanceOf(user), 0);
    }

    function test_Transfer_RevertWhen_ToSelf() public {
        vm.prank(minter);
        token.mint(user, AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(BurnMintGRT.BurnMintGRT__InvalidRecipient.selector, address(token))
        );
        vm.prank(user);
        token.transfer(address(token), AMOUNT);
    }

    // ================================================================
    // │                      Approval Tests                          │
    // ================================================================

    function test_Approve() public {
        vm.prank(user);
        token.approve(admin, AMOUNT);

        assertEq(token.allowance(user, admin), AMOUNT);
    }

    function test_Approve_RevertWhen_SpenderIsSelf() public {
        vm.expectRevert(
            abi.encodeWithSelector(BurnMintGRT.BurnMintGRT__InvalidRecipient.selector, address(token))
        );
        vm.prank(user);
        token.approve(address(token), AMOUNT);
    }

    // ================================================================
    // │                      Permit Tests                            │
    // ================================================================

    function _getPermitDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }

    function _signPermit(
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = token.nonces(owner);
        bytes32 digest = _getPermitDigest(owner, spender, value, nonce, deadline);
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function test_Permit() public {
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(SIGNER_PRIVATE_KEY, signer, user, value, deadline);

        vm.expectEmit();
        emit IERC20.Approval(signer, user, value);

        token.permit(signer, user, value, deadline, v, r, s);

        assertEq(token.allowance(signer, user), value);
        assertEq(token.nonces(signer), 1);
    }

    function test_Permit_MaxAllowance() public {
        uint256 value = type(uint256).max;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(SIGNER_PRIVATE_KEY, signer, user, value, deadline);

        token.permit(signer, user, value, deadline, v, r, s);

        assertEq(token.allowance(signer, user), value);
    }

    function test_Permit_RevertWhen_ExpiredDeadline() public {
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(SIGNER_PRIVATE_KEY, signer, user, value, deadline);

        vm.expectRevert(abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", deadline));

        token.permit(signer, user, value, deadline, v, r, s);
    }

    function test_Permit_RevertWhen_InvalidSigner() public {
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 wrongPrivateKey = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(wrongPrivateKey, signer, user, value, deadline);

        address wrongSigner = vm.addr(wrongPrivateKey);

        vm.expectRevert(abi.encodeWithSignature("ERC2612InvalidSigner(address,address)", wrongSigner, signer));

        token.permit(signer, user, value, deadline, v, r, s);
    }

    function test_Permit_RevertWhen_NonceReused() public {
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(SIGNER_PRIVATE_KEY, signer, user, value, deadline);

        token.permit(signer, user, value, deadline, v, r, s);

        // Second permit with same signature should fail
        vm.expectRevert();
        token.permit(signer, user, value, deadline, v, r, s);
    }

    function test_Permit_ThenTransfer() public {
        // Mint tokens to signer
        vm.prank(minter);
        token.mint(signer, AMOUNT);

        // Sign permit
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(SIGNER_PRIVATE_KEY, signer, user, value, deadline);

        // Execute permit
        token.permit(signer, user, value, deadline, v, r, s);

        // User transfers from signer
        vm.prank(user);
        token.transferFrom(signer, admin, AMOUNT);

        assertEq(token.balanceOf(admin), AMOUNT);
        assertEq(token.balanceOf(signer), 0);
    }

    // ================================================================
    // │                      CCIP Admin Tests                        │
    // ================================================================

    function test_GetCCIPAdmin() public view {
        assertEq(token.getCCIPAdmin(), admin);
    }

    function test_SetCCIPAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.expectEmit();
        emit BurnMintGRT.CCIPAdminTransferred(admin, newAdmin);

        vm.prank(admin);
        token.setCCIPAdmin(newAdmin);

        assertEq(token.getCCIPAdmin(), newAdmin);
    }

    function test_SetCCIPAdmin_RevertWhen_NotAdmin() public {
        vm.expectRevert();
        vm.prank(user);
        token.setCCIPAdmin(user);
    }

    // ================================================================
    // │                      Role Tests                              │
    // ================================================================

    function test_GrantMintAndBurnRoles() public {
        address newBurnMinter = makeAddr("newBurnMinter");

        vm.prank(admin);
        token.grantMintAndBurnRoles(newBurnMinter);

        assertTrue(token.hasRole(token.MINTER_ROLE(), newBurnMinter));
        assertTrue(token.hasRole(token.BURNER_ROLE(), newBurnMinter));
    }
}
