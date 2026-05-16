// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { TBillToken } from "../src/TBillToken.sol";
import { TBillVault } from "../src/TBillVault.sol";
import { ProtocolTreasury } from "../src/ProtocolTreasury.sol";
import { RwaGovernor } from "../src/RwaGovernor.sol";

contract VerifyDeployment is Script {
    function run() external view {
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        address tbill = vm.parseJsonAddress(json, ".tbillProxy");
        address vault = vm.parseJsonAddress(json, ".vault");
        address treasury = vm.parseJsonAddress(json, ".treasury");
        address timelock = vm.parseJsonAddress(json, ".timelock");
        address governor = vm.parseJsonAddress(json, ".governor");

        TimelockController tl = TimelockController(payable(timelock));
        RwaGovernor gov = RwaGovernor(payable(governor));
        TBillToken asset = TBillToken(tbill);
        TBillVault tbillVault = TBillVault(vault);
        ProtocolTreasury protocolTreasury = ProtocolTreasury(payable(treasury));

        require(tl.getMinDelay() == 2 days, "bad timelock delay");
        require(gov.votingDelay() == 1 days, "bad voting delay");
        require(gov.votingPeriod() == 1 weeks, "bad voting period");
        require(gov.quorumNumerator() == 4, "bad quorum");
        require(gov.proposalThreshold() == 10_000 ether, "bad proposal threshold");
        require(asset.hasRole(asset.DEFAULT_ADMIN_ROLE(), timelock), "tbill admin not timelock");
        require(asset.hasRole(asset.UPGRADER_ROLE(), timelock), "tbill upgrader not timelock");
        require(
            tbillVault.hasRole(tbillVault.DEFAULT_ADMIN_ROLE(), timelock),
            "vault admin not timelock"
        );
        require(
            protocolTreasury.hasRole(protocolTreasury.TREASURY_MANAGER_ROLE(), timelock),
            "treasury manager not timelock"
        );
        require(tl.hasRole(tl.PROPOSER_ROLE(), governor), "governor not proposer");
        require(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "open executor missing");

        console2.log("Deployment verification passed for chain", block.chainid);
        console2.log("Timelock", timelock);
        console2.log("Governor", governor);
        console2.log("TBill proxy", tbill);
    }
}
