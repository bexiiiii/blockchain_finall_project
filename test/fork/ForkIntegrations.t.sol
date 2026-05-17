// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3Interface } from "../../src/interfaces/AggregatorV3Interface.sol";

interface IERC20Like {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IUniswapV2RouterLike {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
}

contract ForkIntegrationsTest is Test {
    function _mainnetRpc() internal view returns (string memory) {
        return vm.envOr("MAINNET_RPC_URL", string(""));
    }

    function testFork_USDCTotalSupply() public {
        string memory rpc = _mainnetRpc();
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        IERC20Like usdc = IERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(usdc.decimals(), 6);
        assertGt(usdc.totalSupply(), 0);
    }

    function testFork_UniswapV2RouterMetadata() public {
        string memory rpc = _mainnetRpc();
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        IUniswapV2RouterLike router =
            IUniswapV2RouterLike(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        assertNotEq(router.WETH(), address(0));
        assertNotEq(router.factory(), address(0));
    }

    function testFork_ChainlinkEthUsdFeed() public {
        string memory rpc = _mainnetRpc();
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        AggregatorV3Interface feed =
            AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
    }
}
