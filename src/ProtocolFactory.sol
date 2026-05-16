// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TBillToken } from "./TBillToken.sol";

contract ProtocolFactory is AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    address public immutable tbillImplementation;

    event AssetDeployed(
        address indexed proxy, bytes32 indexed salt, string name, string symbol, bool deterministic
    );

    constructor(address admin) {
        require(admin != address(0), "admin zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, admin);
        tbillImplementation = address(new TBillToken());
    }

    function deployAssetCreate(
        string calldata name,
        string calldata symbol,
        address tokenAdmin,
        address registry
    ) external onlyRole(DEPLOYER_ROLE) returns (address proxy) {
        bytes memory initData = _initData(name, symbol, tokenAdmin, registry);
        proxy = address(new ERC1967Proxy(tbillImplementation, initData));
        emit AssetDeployed(proxy, bytes32(0), name, symbol, false);
    }

    function deployAssetCreate2(
        bytes32 salt,
        string calldata name,
        string calldata symbol,
        address tokenAdmin,
        address registry
    ) external onlyRole(DEPLOYER_ROLE) returns (address proxy) {
        bytes memory bytecode = _proxyBytecode(name, symbol, tokenAdmin, registry);
        proxy = Create2.deploy(0, salt, bytecode);
        emit AssetDeployed(proxy, salt, name, symbol, true);
    }

    function predictCreate2Address(
        bytes32 salt,
        string calldata name,
        string calldata symbol,
        address tokenAdmin,
        address registry
    ) external view returns (address) {
        return Create2.computeAddress(
            salt, keccak256(_proxyBytecode(name, symbol, tokenAdmin, registry))
        );
    }

    function _initData(
        string calldata name,
        string calldata symbol,
        address tokenAdmin,
        address registry
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(TBillToken.initialize, (name, symbol, tokenAdmin, registry));
    }

    function _proxyBytecode(
        string calldata name,
        string calldata symbol,
        address tokenAdmin,
        address registry
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(tbillImplementation, _initData(name, symbol, tokenAdmin, registry))
        );
    }
}
