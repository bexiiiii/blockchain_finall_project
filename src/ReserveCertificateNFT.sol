// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
    ERC721URIStorage
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract ReserveCertificateNFT is ERC721, ERC721URIStorage, AccessControl, Pausable {
    bytes32 public constant CERTIFIER_ROLE = keccak256("CERTIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public nextTokenId = 1;

    event ReserveCertificateIssued(uint256 indexed tokenId, address indexed issuer, string uri);
    event ReserveCertificateRevoked(uint256 indexed tokenId);

    constructor(address admin) ERC721("T-Bill Reserve Certificate", "TBCERT") {
        require(admin != address(0), "admin zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CERTIFIER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function mintCertificate(address issuer, string calldata uri)
        external
        onlyRole(CERTIFIER_ROLE)
        returns (uint256 tokenId)
    {
        require(issuer != address(0), "issuer zero");
        tokenId = nextTokenId++;
        _safeMint(issuer, tokenId);
        _setTokenURI(tokenId, uri);
        emit ReserveCertificateIssued(tokenId, issuer, uri);
    }

    function revokeCertificate(uint256 tokenId) external onlyRole(CERTIFIER_ROLE) {
        _requireOwned(tokenId);
        _burn(tokenId);
        emit ReserveCertificateRevoked(tokenId);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
