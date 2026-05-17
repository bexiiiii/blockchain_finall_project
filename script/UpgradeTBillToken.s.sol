// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { TBillToken } from "../src/TBillToken.sol";
import { TBillTokenV2 } from "../src/TBillTokenV2.sol";

contract UpgradeTBillToken is Script {
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address newImplementation) {
        uint256 privateKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_PRIVATE_KEY);
        address proxy = vm.envAddress("TBILL_PROXY");
        string memory complianceUri =
            vm.envOr("COMPLIANCE_URI", string("ipfs://tbill-compliance-v2"));

        vm.startBroadcast(privateKey);
        TBillTokenV2 v2 = new TBillTokenV2();
        TBillToken(proxy)
            .upgradeToAndCall(
                address(v2), abi.encodeCall(TBillTokenV2.setComplianceUri, (complianceUri))
            );
        vm.stopBroadcast();

        newImplementation = address(v2);
        console2.log("TBillToken upgraded to V2 implementation", newImplementation);
    }
}
