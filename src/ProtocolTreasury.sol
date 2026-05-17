// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ProtocolTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    mapping(address token => mapping(address payee => uint256 amount)) public tokenPayments;
    mapping(address payee => uint256 amount) public ethPayments;

    event TokenDeposited(address indexed token, address indexed from, uint256 amount);
    event TokenPaymentScheduled(address indexed token, address indexed payee, uint256 amount);
    event TokenPaymentWithdrawn(address indexed token, address indexed payee, uint256 amount);
    event EthPaymentScheduled(address indexed payee, uint256 amount);
    event EthPaymentWithdrawn(address indexed payee, uint256 amount);

    constructor(address admin) {
        require(admin != address(0), "admin zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_MANAGER_ROLE, admin);
    }

    receive() external payable { }

    function depositToken(IERC20 token, uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit TokenDeposited(address(token), msg.sender, amount);
    }

    function scheduleTokenPayment(IERC20 token, address payee, uint256 amount)
        external
        onlyRole(TREASURY_MANAGER_ROLE)
    {
        require(payee != address(0), "payee zero");
        tokenPayments[address(token)][payee] += amount;
        emit TokenPaymentScheduled(address(token), payee, amount);
    }

    function withdrawTokenPayment(IERC20 token) external nonReentrant {
        uint256 amount = tokenPayments[address(token)][msg.sender];
        require(amount > 0, "nothing owed");
        tokenPayments[address(token)][msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit TokenPaymentWithdrawn(address(token), msg.sender, amount);
    }

    function scheduleEthPayment(address payee, uint256 amount)
        external
        onlyRole(TREASURY_MANAGER_ROLE)
    {
        require(payee != address(0), "payee zero");
        ethPayments[payee] += amount;
        emit EthPaymentScheduled(payee, amount);
    }

    function withdrawEthPayment() external nonReentrant {
        uint256 amount = ethPayments[msg.sender];
        require(amount > 0, "nothing owed");
        ethPayments[msg.sender] = 0;
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "eth transfer failed");
        emit EthPaymentWithdrawn(msg.sender, amount);
    }
}
