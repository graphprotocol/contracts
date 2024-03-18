// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../governance/Governed.sol";
import "../libraries/HexStrings.sol";
import "./ISubgraphNFT.sol";
import "./ISubgraphNFTDescriptor.sol";

/// @title NFT that represents ownership of a Subgraph
contract SubgraphNFT is Governed, ERC721, ISubgraphNFT {
    // -- State --

    address public minter;
    ISubgraphNFTDescriptor public tokenDescriptor;
    mapping(uint256 => bytes32) private _subgraphMetadataHashes;

    // -- Events --

    event MinterUpdated(address minter);
    event TokenDescriptorUpdated(address tokenDescriptor);
    event SubgraphMetadataUpdated(uint256 indexed tokenID, bytes32 subgraphURI);

    // -- Modifiers --

    modifier onlyMinter() {
        require(msg.sender == minter, "Must be a minter");
        _;
    }

    constructor(address _governor) ERC721("Subgraph", "SG") {
        _initialize(_governor);
    }

    // -- Config --

    /**
     * @notice Set the minter allowed to perform actions on the NFT.
     * @dev Minter can mint, burn and update the metadata
     * @param _minter Address of the allowed minter
     */
    function setMinter(address _minter) external override onlyGovernor {
        _setMinter(_minter);
    }

    /**
     * @notice Internal: Set the minter allowed to perform actions on the NFT.
     * @dev Minter can mint, burn and update the metadata. Can be set to zero.
     * @param _minter Address of the allowed minter
     */
    function _setMinter(address _minter) internal {
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    /**
     * @notice Set the token descriptor contract.
     * @dev Token descriptor can be zero. If set, it must be a contract.
     * @param _tokenDescriptor Address of the contract that creates the NFT token URI
     */
    function setTokenDescriptor(address _tokenDescriptor) external override onlyGovernor {
        _setTokenDescriptor(_tokenDescriptor);
    }

    /**
     * @dev Internal: Set the token descriptor contract used to create the ERC-721 metadata URI.
     * @param _tokenDescriptor Address of the contract that creates the NFT token URI
     */
    function _setTokenDescriptor(address _tokenDescriptor) internal {
        require(
            _tokenDescriptor == address(0) || Address.isContract(_tokenDescriptor),
            "NFT: Invalid token descriptor"
        );
        tokenDescriptor = ISubgraphNFTDescriptor(_tokenDescriptor);
        emit TokenDescriptorUpdated(_tokenDescriptor);
    }

    /**
     * @notice Set the base URI.
     * @dev Can be set to empty.
     * @param _baseURI Base URI to use to build the token URI
     */
    function setBaseURI(string memory _baseURI) external override onlyGovernor {
        _setBaseURI(_baseURI);
    }

    // -- Minter actions --

    /**
     * @notice Mint `_tokenId` and transfers it to `_to`.
     * @dev `tokenId` must not exist and `to` cannot be the zero address.
     * @param _to Address receiving the minted NFT
     * @param _tokenId ID of the NFT
     */
    function mint(address _to, uint256 _tokenId) external override onlyMinter {
        _mint(_to, _tokenId);
    }

    /**
     * @notice Burn `_tokenId`.
     * @dev The approval is cleared when the token is burned.
     * @param _tokenId ID of the NFT
     */
    function burn(uint256 _tokenId) external override onlyMinter {
        _burn(_tokenId);
    }

    /**
     * @notice Set the metadata for a subgraph represented by `_tokenId`.
     * @dev `_tokenId` must exist.
     * @param _tokenId ID of the NFT
     * @param _subgraphMetadata IPFS hash for the metadata
     */
    function setSubgraphMetadata(uint256 _tokenId, bytes32 _subgraphMetadata) external override onlyMinter {
        require(_exists(_tokenId), "ERC721Metadata: URI set of nonexistent token");
        _subgraphMetadataHashes[_tokenId] = _subgraphMetadata;
        emit SubgraphMetadataUpdated(_tokenId, _subgraphMetadata);
    }

    // -- NFT display --

    /// @inheritdoc ERC721
    function tokenURI(uint256 _tokenId) public view override(ERC721, ISubgraphNFT) returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

        // Delegates rendering of the metadata to the token descriptor if existing
        // This allows for some flexibility in adapting the token URI
        if (address(tokenDescriptor) != address(0)) {
            return tokenDescriptor.tokenURI(minter, _tokenId, baseURI(), _subgraphMetadataHashes[_tokenId]);
        }

        // Default token URI
        uint256 metadata = uint256(_subgraphMetadataHashes[_tokenId]);

        string memory _subgraphURI = metadata > 0 ? HexStrings.toString(metadata) : "";
        string memory base = baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _subgraphURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_subgraphURI).length > 0) {
            return string(abi.encodePacked(base, _subgraphURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, HexStrings.toString(_tokenId)));
    }
}
