// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { TBillToken } from "../src/TBillToken.sol";
import { RwaGovernanceToken } from "../src/RwaGovernanceToken.sol";
import { ReserveCertificateNFT } from "../src/ReserveCertificateNFT.sol";
import { TBillVault } from "../src/TBillVault.sol";
import { RwaStableAMM } from "../src/RwaStableAMM.sol";
import { OracleAdapter } from "../src/OracleAdapter.sol";
import { ProtocolTreasury } from "../src/ProtocolTreasury.sol";
import { ProtocolFactory } from "../src/ProtocolFactory.sol";
import { RwaGovernor } from "../src/RwaGovernor.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";

contract Deploy is Script {
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant INITIAL_TBILL_SUPPLY = 10_000_000 ether;
    uint256 internal constant INITIAL_GOV_SUPPLY = 1_000_000 ether;
    uint256 internal constant TIMELOCK_DELAY = 2 days;

    struct Deployment {
        address deployer;
        address settlementToken;
        address priceFeed;
        address reserveFeed;
        address oracle;
        address tbillImplementation;
        address tbillProxy;
        address vault;
        address amm;
        address governanceToken;
        address timelock;
        address governor;
        address treasury;
        address certificateNft;
        address factory;
    }

    function run() external returns (Deployment memory d) {
        uint256 privateKey = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_PRIVATE_KEY);
        d.deployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        MockV3Aggregator priceFeed = new MockV3Aggregator(8, 100_000_000);
        MockV3Aggregator reserveFeed = new MockV3Aggregator(8, 105_000_000);
        MockERC20 settlement = new MockERC20("Mock USD Coin", "mUSDC", 6);
        TBillToken implementation = new TBillToken();
        TBillToken tbill = TBillToken(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        TBillToken.initialize, ("Tokenized T-Bill", "TBILL", d.deployer, address(0))
                    )
                )
            )
        );
        RwaGovernanceToken govToken = new RwaGovernanceToken(d.deployer, INITIAL_GOV_SUPPLY);
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock =
            new TimelockController(TIMELOCK_DELAY, proposers, executors, d.deployer);
        RwaGovernor governor = new RwaGovernor(govToken, timelock, INITIAL_GOV_SUPPLY / 100);
        TBillVault vault = new TBillVault(IERC20(address(tbill)), d.deployer);
        RwaStableAMM amm = new RwaStableAMM(IERC20(address(tbill)), IERC20(address(settlement)));
        ProtocolTreasury treasury = new ProtocolTreasury(d.deployer);
        ReserveCertificateNFT cert = new ReserveCertificateNFT(d.deployer);
        ProtocolFactory factory = new ProtocolFactory(d.deployer);
        OracleAdapter oracle = new OracleAdapter(priceFeed, reserveFeed, 1 days, d.deployer);

        tbill.mint(d.deployer, INITIAL_TBILL_SUPPLY);
        settlement.mint(d.deployer, 10_000_000e6);
        govToken.delegate(d.deployer);

        _handoff(
            d.deployer, tbill, govToken, vault, treasury, cert, factory, oracle, timelock, governor
        );

        vm.stopBroadcast();

        d.settlementToken = address(settlement);
        d.priceFeed = address(priceFeed);
        d.reserveFeed = address(reserveFeed);
        d.oracle = address(oracle);
        d.tbillImplementation = address(implementation);
        d.tbillProxy = address(tbill);
        d.vault = address(vault);
        d.amm = address(amm);
        d.governanceToken = address(govToken);
        d.timelock = address(timelock);
        d.governor = address(governor);
        d.treasury = address(treasury);
        d.certificateNft = address(cert);
        d.factory = address(factory);

        _writeDeployment(d);
        console2.log("RWA T-Bill protocol deployed on chain", block.chainid);
        console2.log("TBill proxy", d.tbillProxy);
        console2.log("Governor", d.governor);
        console2.log("Timelock", d.timelock);
    }

    function _handoff(
        address deployer,
        TBillToken tbill,
        RwaGovernanceToken govToken,
        TBillVault vault,
        ProtocolTreasury treasury,
        ReserveCertificateNFT cert,
        ProtocolFactory factory,
        OracleAdapter oracle,
        TimelockController timelock,
        RwaGovernor governor
    ) internal {
        address tl = address(timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        tbill.grantRole(tbill.DEFAULT_ADMIN_ROLE(), tl);
        tbill.grantRole(tbill.ISSUER_ROLE(), tl);
        tbill.grantRole(tbill.PAUSER_ROLE(), tl);
        tbill.grantRole(tbill.BURNER_ROLE(), tl);
        tbill.grantRole(tbill.UPGRADER_ROLE(), tl);
        tbill.renounceRole(tbill.ISSUER_ROLE(), deployer);
        tbill.renounceRole(tbill.PAUSER_ROLE(), deployer);
        tbill.renounceRole(tbill.BURNER_ROLE(), deployer);
        tbill.renounceRole(tbill.UPGRADER_ROLE(), deployer);
        tbill.renounceRole(tbill.DEFAULT_ADMIN_ROLE(), deployer);

        govToken.grantRole(govToken.DEFAULT_ADMIN_ROLE(), tl);
        govToken.grantRole(govToken.MINTER_ROLE(), tl);
        govToken.renounceRole(govToken.MINTER_ROLE(), deployer);
        govToken.renounceRole(govToken.DEFAULT_ADMIN_ROLE(), deployer);

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), tl);
        vault.grantRole(vault.YIELD_MANAGER_ROLE(), tl);
        vault.grantRole(vault.PAUSER_ROLE(), tl);
        vault.renounceRole(vault.YIELD_MANAGER_ROLE(), deployer);
        vault.renounceRole(vault.PAUSER_ROLE(), deployer);
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);

        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), tl);
        treasury.grantRole(treasury.TREASURY_MANAGER_ROLE(), tl);
        treasury.renounceRole(treasury.TREASURY_MANAGER_ROLE(), deployer);
        treasury.renounceRole(treasury.DEFAULT_ADMIN_ROLE(), deployer);

        cert.grantRole(cert.DEFAULT_ADMIN_ROLE(), tl);
        cert.grantRole(cert.CERTIFIER_ROLE(), tl);
        cert.grantRole(cert.PAUSER_ROLE(), tl);
        cert.renounceRole(cert.CERTIFIER_ROLE(), deployer);
        cert.renounceRole(cert.PAUSER_ROLE(), deployer);
        cert.renounceRole(cert.DEFAULT_ADMIN_ROLE(), deployer);

        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), tl);
        factory.grantRole(factory.DEPLOYER_ROLE(), tl);
        factory.renounceRole(factory.DEPLOYER_ROLE(), deployer);
        factory.renounceRole(factory.DEFAULT_ADMIN_ROLE(), deployer);

        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), tl);
        oracle.grantRole(oracle.ORACLE_ADMIN_ROLE(), tl);
        oracle.renounceRole(oracle.ORACLE_ADMIN_ROLE(), deployer);
        oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);

        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _writeDeployment(Deployment memory d) internal {
        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "deployer", d.deployer);
        vm.serializeAddress(key, "settlementToken", d.settlementToken);
        vm.serializeAddress(key, "priceFeed", d.priceFeed);
        vm.serializeAddress(key, "reserveFeed", d.reserveFeed);
        vm.serializeAddress(key, "oracle", d.oracle);
        vm.serializeAddress(key, "tbillImplementation", d.tbillImplementation);
        vm.serializeAddress(key, "tbillProxy", d.tbillProxy);
        vm.serializeAddress(key, "vault", d.vault);
        vm.serializeAddress(key, "amm", d.amm);
        vm.serializeAddress(key, "governanceToken", d.governanceToken);
        vm.serializeAddress(key, "timelock", d.timelock);
        vm.serializeAddress(key, "governor", d.governor);
        vm.serializeAddress(key, "treasury", d.treasury);
        vm.serializeAddress(key, "certificateNft", d.certificateNft);
        string memory json = vm.serializeAddress(key, "factory", d.factory);
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
    }
}
