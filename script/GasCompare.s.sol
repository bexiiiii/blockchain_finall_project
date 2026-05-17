// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TBillToken } from "../src/TBillToken.sol";
import { TBillVault } from "../src/TBillVault.sol";
import { RwaStableAMM } from "../src/RwaStableAMM.sol";
import { OracleAdapter } from "../src/OracleAdapter.sol";
import { ProtocolTreasury } from "../src/ProtocolTreasury.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";

contract GasCompare is Script {
    function run() external {
        address actor = address(0xA11CE);
        vm.deal(actor, 10 ether);
        vm.startPrank(actor);

        TBillToken implementation = new TBillToken();
        TBillToken tbill = TBillToken(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        TBillToken.initialize, ("Tokenized T-Bill", "TBILL", actor, address(0))
                    )
                )
            )
        );
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        TBillVault vault = new TBillVault(IERC20(address(tbill)), actor);
        RwaStableAMM amm = new RwaStableAMM(IERC20(address(tbill)), IERC20(address(usdc)));
        MockV3Aggregator price = new MockV3Aggregator(8, 100_000_000);
        MockV3Aggregator reserve = new MockV3Aggregator(8, 105_000_000);
        OracleAdapter oracle = new OracleAdapter(price, reserve, 1 days, actor);
        ProtocolTreasury treasury = new ProtocolTreasury(actor);

        tbill.mint(actor, 2_000_000 ether);
        usdc.mint(actor, 2_000_000e6);
        tbill.approve(address(vault), type(uint256).max);
        tbill.approve(address(amm), type(uint256).max);
        tbill.approve(address(treasury), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);

        uint256 mintGas = _measureMint(tbill);
        uint256 depositGas = _measureVaultDeposit(vault, actor);
        uint256 reportYieldGas = _measureReportYield(vault);
        uint256 addLiquidityGas = _measureAddLiquidity(amm, actor);
        uint256 swapGas = _measureSwap(amm, actor);
        uint256 oracleGas = _measureOracle(oracle);
        uint256 treasuryGas = _measureTreasury(treasury, tbill);

        string memory report = string.concat(
            "# Gas Comparison\n\n",
            "Measured locally with Foundry. Fill the L1/Base Sepolia columns after running the same script against each RPC.\n\n",
            "| Operation | Local gas | L1 measured | Base Sepolia measured |\n",
            "| --- | ---: | ---: | ---: |\n",
            "| TBill mint | ",
            vm.toString(mintGas),
            " | TBD | TBD |\n",
            "| Vault deposit | ",
            vm.toString(depositGas),
            " | TBD | TBD |\n",
            "| Vault reportYield | ",
            vm.toString(reportYieldGas),
            " | TBD | TBD |\n",
            "| AMM addLiquidity | ",
            vm.toString(addLiquidityGas),
            " | TBD | TBD |\n",
            "| AMM swapExactIn | ",
            vm.toString(swapGas),
            " | TBD | TBD |\n",
            "| Oracle latestPrice | ",
            vm.toString(oracleGas),
            " | TBD | TBD |\n",
            "| Treasury depositToken | ",
            vm.toString(treasuryGas),
            " | TBD | TBD |\n"
        );
        vm.writeFile(string.concat(vm.projectRoot(), "/docs/reports/gas-comparison.md"), report);
        vm.stopPrank();
    }

    function _measureMint(TBillToken tbill) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        tbill.mint(address(0xBEEF), 1 ether);
        return gasBefore - gasleft();
    }

    function _measureVaultDeposit(TBillVault vault, address actor) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        vault.deposit(1 ether, actor);
        return gasBefore - gasleft();
    }

    function _measureReportYield(TBillVault vault) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        vault.reportYield(1 ether);
        return gasBefore - gasleft();
    }

    function _measureAddLiquidity(RwaStableAMM amm, address actor) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        amm.addLiquidity(100_000 ether, 100_000e6, 1, 1, actor, block.timestamp + 1);
        return gasBefore - gasleft();
    }

    function _measureSwap(RwaStableAMM amm, address actor) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        amm.swapExactIn(address(amm.token0()), 1 ether, 1, actor, block.timestamp + 1);
        return gasBefore - gasleft();
    }

    function _measureOracle(OracleAdapter oracle) internal view returns (uint256) {
        uint256 gasBefore = gasleft();
        oracle.latestPrice();
        return gasBefore - gasleft();
    }

    function _measureTreasury(ProtocolTreasury treasury, TBillToken tbill)
        internal
        returns (uint256)
    {
        uint256 gasBefore = gasleft();
        treasury.depositToken(IERC20(address(tbill)), 1 ether);
        return gasBefore - gasleft();
    }
}
