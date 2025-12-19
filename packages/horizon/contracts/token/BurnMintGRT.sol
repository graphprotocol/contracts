// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20BurnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title BurnMintGRT
 * @author Edge & Node
 * @notice An upgradeable ERC20 token with burn, mint, and ERC2612 permit support.
 * Designed for use as a CCIP-bridged GRT token on spoke chains (Avalanche, Base, etc.).
 *
 * Key features:
 * - ERC2612 permit for gasless approvals
 * - Role-based access control for minting and burning
 * - Pausable via PausableUpgradeable (see BurnMintGRTPausable)
 * - Transparent proxy upgradeable pattern
 * - CCIP admin management for Chainlink Token Manager integration
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract BurnMintGRT is
    Initializable,
    IERC165,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    /// @notice Thrown when minting would exceed the maximum supply
    error BurnMintGRT__MaxSupplyExceeded(uint256 supplyAfterMint);

    /// @notice Thrown when an invalid recipient is specified (e.g., address(this))
    error BurnMintGRT__InvalidRecipient(address recipient);

    /// @notice Emitted when the CCIP admin is transferred
    event CCIPAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    /// @notice Role identifier for addresses allowed to mint tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role identifier for addresses allowed to burn tokens
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @custom:storage-location erc7201:graphprotocol.storage.BurnMintGRT
    struct BurnMintGRTStorage {
        /// @dev The CCIP admin can be used to register with the CCIP token admin registry,
        /// but has no other special powers, and can only be transferred by the owner.
        address ccipAdmin;
        /// @dev The number of decimals for the token
        uint8 decimals;
        /// @dev The maximum supply of the token, 0 if unlimited
        uint256 maxSupply;
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.BurnMintGRT")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BURN_MINT_GRT_STORAGE_LOCATION =
        0x5e17d28b210b6d8f95a8e9e75d4968e437f9fc70a74ce03c689db6037be89e00;

    // solhint-disable-next-line func-name-mixedcase
    function _getBurnMintGRTStorage() private pure returns (BurnMintGRTStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := BURN_MINT_GRT_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the token contract
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param decimals_ The number of decimals (typically 18)
     * @param maxSupply_ The maximum supply (0 for unlimited)
     * @param preMint Amount to mint to the admin on initialization
     * @param defaultAdmin Address to receive admin role and pre-minted tokens
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        uint256 preMint,
        address defaultAdmin
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        __ERC20Permit_init(name_);
        __AccessControl_init();

        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();

        $.decimals = decimals_;
        $.maxSupply = maxSupply_;
        $.ccipAdmin = defaultAdmin;

        if (preMint != 0) {
            if (maxSupply_ != 0 && preMint > maxSupply_) {
                revert BurnMintGRT__MaxSupplyExceeded(preMint);
            }
            _mint(defaultAdmin, preMint);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual override(AccessControlDefaultAdminRulesUpgradeable, IERC165) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IAccessControl).interfaceId || interfaceId == type(IERC20Permit).interfaceId;
    }

    /// @dev Returns the number of decimals used in its user representation.
    function decimals() public view virtual override returns (uint8) {
        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();
        return $.decimals;
    }

    /// @notice Returns the max supply of the token, 0 if unlimited.
    function maxSupply() public view virtual returns (uint256) {
        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();
        return $.maxSupply;
    }

    /// @dev Disallows minting and transferring to address(this).
    function _update(address from, address to, uint256 value) internal virtual override {
        if (to == address(this)) revert BurnMintGRT__InvalidRecipient(to);

        super._update(from, to, value);
    }

    /// @dev Disallows approving for address(this)
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (spender == address(this)) revert BurnMintGRT__InvalidRecipient(spender);

        super._approve(owner, spender, value, emitEvent);
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    /// @dev Decreases the total supply. Requires BURNER_ROLE.
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    /**
     * @notice Burns tokens from a specific account
     * @dev Alias for burnFrom for compatibility with older naming convention.
     * @param account The account to burn from
     * @param amount The amount to burn
     */
    function burn(address account, uint256 amount) public virtual {
        burnFrom(account, amount);
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    /// @dev Decreases the total supply. Requires BURNER_ROLE.
    function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burnFrom(account, amount);
    }

    /**
     * @notice Mints new tokens to an account
     * @dev Requires MINTER_ROLE. Reverts if minting would exceed maxSupply.
     * @param account The account to mint to
     * @param amount The amount to mint
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();
        uint256 _maxSupply = $.maxSupply;
        uint256 _totalSupply = totalSupply();

        if (_maxSupply != 0 && _totalSupply + amount > _maxSupply) {
            revert BurnMintGRT__MaxSupplyExceeded(_totalSupply + amount);
        }

        _mint(account, amount);
    }

    /**
     * @notice Grants both mint and burn roles to an address
     * @dev Convenience function for CCIP pool setup
     * @param burnAndMinter The address to grant roles to
     */
    function grantMintAndBurnRoles(address burnAndMinter) external {
        grantRole(MINTER_ROLE, burnAndMinter);
        grantRole(BURNER_ROLE, burnAndMinter);
    }

    /**
     * @notice Returns the current CCIP admin
     * @return The address of the CCIP admin
     */
    function getCCIPAdmin() external view returns (address) {
        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();
        return $.ccipAdmin;
    }

    /**
     * @notice Transfers the CCIP admin role to a new address
     * @dev Only the default admin can call this function.
     * Setting to address(0) is a valid way to revoke the role.
     * @param newAdmin The address to transfer the CCIP admin role to
     */
    function setCCIPAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BurnMintGRTStorage storage $ = _getBurnMintGRTStorage();
        address currentAdmin = $.ccipAdmin;

        $.ccipAdmin = newAdmin;

        emit CCIPAdminTransferred(currentAdmin, newAdmin);
    }
}
