// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract VulnerableIssuer {
    mapping(address => uint256) public minted;

    function mint(address to, uint256 amount) external {
        minted[to] += amount;
    }
}

contract FixedIssuer is AccessControl {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    mapping(address => uint256) public minted;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ISSUER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(ISSUER_ROLE) {
        minted[to] += amount;
    }
}
