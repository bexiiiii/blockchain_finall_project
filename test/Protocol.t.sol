// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { TBillToken } from "../src/TBillToken.sol";
import { TBillTokenV2 } from "../src/TBillTokenV2.sol";
import { RwaGovernanceToken } from "../src/RwaGovernanceToken.sol";
import { ReserveCertificateNFT } from "../src/ReserveCertificateNFT.sol";
import { TBillVault } from "../src/TBillVault.sol";
import { RwaStableAMM } from "../src/RwaStableAMM.sol";
import { OracleAdapter } from "../src/OracleAdapter.sol";
import { ProtocolTreasury } from "../src/ProtocolTreasury.sol";
import { ProtocolFactory } from "../src/ProtocolFactory.sol";
import { RwaGovernor } from "../src/RwaGovernor.sol";
import { RwaMath } from "../src/libraries/RwaMath.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";
import {
    VulnerableEthVault,
    FixedEthVault,
    ReentrancyAttacker
} from "./mocks/ReentrancyFixtures.sol";
import { VulnerableIssuer, FixedIssuer } from "./mocks/AccessControlFixtures.sol";

contract ProtocolTest is Test {
    address internal admin = address(0xA11CE);
    address internal issuer = address(0x1550E);
    address internal user = address(0xB0B);
    address internal user2 = address(0xCAFE);
    address internal registry = address(0x1234);

    TBillToken internal tbill;
    MockERC20 internal usdc;
    TBillVault internal vault;
    RwaStableAMM internal amm;
    RwaGovernanceToken internal govToken;
    ReserveCertificateNFT internal cert;
    MockV3Aggregator internal priceFeed;
    MockV3Aggregator internal reserveFeed;
    OracleAdapter internal oracle;
    ProtocolTreasury internal treasury;
    ProtocolFactory internal factory;

    function setUp() public {
        vm.warp(1_700_000_000);
        TBillToken implementation = new TBillToken();
        bytes memory initData =
            abi.encodeCall(TBillToken.initialize, ("Tokenized T-Bill", "TBILL", admin, registry));
        tbill = TBillToken(address(new ERC1967Proxy(address(implementation), initData)));

        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new TBillVault(IERC20(address(tbill)), admin);
        amm = new RwaStableAMM(IERC20(address(tbill)), IERC20(address(usdc)));
        govToken = new RwaGovernanceToken(admin, 1_000_000 ether);
        cert = new ReserveCertificateNFT(admin);
        priceFeed = new MockV3Aggregator(8, 100_000_000);
        reserveFeed = new MockV3Aggregator(8, 105_000_000);
        oracle = new OracleAdapter(priceFeed, reserveFeed, 1 days, admin);
        treasury = new ProtocolTreasury(admin);
        factory = new ProtocolFactory(admin);

        vm.startPrank(admin);
        tbill.grantRole(tbill.ISSUER_ROLE(), issuer);
        tbill.grantRole(tbill.BURNER_ROLE(), issuer);
        tbill.mint(admin, 10_000_000 ether);
        tbill.mint(user, 1_000_000 ether);
        tbill.mint(user2, 1_000_000 ether);
        usdc.mint(admin, 10_000_000e6);
        usdc.mint(user, 1_000_000e6);
        usdc.mint(user2, 1_000_000e6);
        tbill.approve(address(vault), type(uint256).max);
        tbill.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user);
        tbill.approve(address(vault), type(uint256).max);
        tbill.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function _seedAmm() internal {
        vm.prank(admin);
        amm.addLiquidity(1_000_000 ether, 1_000_000e6, 1, 1, admin, block.timestamp + 1);
    }

    function _deployGovernorStack()
        internal
        returns (RwaGovernanceToken token, TimelockController timelock, RwaGovernor governor)
    {
        token = new RwaGovernanceToken(admin, 1_000_000 ether);
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(2 days, proposers, executors, admin);
        governor = new RwaGovernor(token, timelock, 10_000 ether);

        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        token.delegate(admin);
        vm.stopPrank();
    }

    function test001_TBillMetadata() public view {
        assertEq(tbill.name(), "Tokenized T-Bill");
        assertEq(tbill.symbol(), "TBILL");
        assertEq(tbill.decimals(), 18);
    }

    function test002_TBillVersionV1() public view {
        assertEq(tbill.version(), "1.0.0");
    }

    function test003_TBillRegistrySet() public {
        vm.prank(admin);
        tbill.setRegistry(address(0x4567));
        assertEq(tbill.registry(), address(0x4567));
    }

    function test004_TBillRegistryOnlyAdmin() public {
        vm.expectRevert();
        vm.prank(user);
        tbill.setRegistry(address(0x4567));
    }

    function test005_TBillMintByIssuer() public {
        vm.prank(issuer);
        tbill.mint(user, 100 ether);
        assertEq(tbill.balanceOf(user), 1_000_100 ether);
    }

    function test006_TBillMintRejectsNonIssuer() public {
        vm.expectRevert();
        vm.prank(user);
        tbill.mint(user, 100 ether);
    }

    function test007_TBillBurnByBurner() public {
        vm.prank(issuer);
        tbill.burn(user, 100 ether);
        assertEq(tbill.balanceOf(user), 999_900 ether);
    }

    function test008_TBillBurnRejectsNonBurner() public {
        vm.expectRevert();
        vm.prank(user);
        tbill.burn(user, 100 ether);
    }

    function test009_TBillPauseBlocksTransfer() public {
        vm.prank(admin);
        tbill.pause();
        vm.expectRevert();
        vm.prank(user);
        tbill.transfer(user2, 1 ether);
    }

    function test010_TBillUnpauseAllowsTransfer() public {
        vm.startPrank(admin);
        tbill.pause();
        tbill.unpause();
        vm.stopPrank();
        vm.prank(user);
        tbill.transfer(user2, 1 ether);
        assertEq(tbill.balanceOf(user2), 1_000_001 ether);
    }

    function test011_TBillPauseOnlyPauser() public {
        vm.expectRevert();
        vm.prank(user);
        tbill.pause();
    }

    function test012_TBillUpgradeToV2() public {
        TBillTokenV2 v2 = new TBillTokenV2();
        vm.prank(admin);
        tbill.upgradeToAndCall(address(v2), "");
        TBillTokenV2 upgraded = TBillTokenV2(address(tbill));
        assertEq(upgraded.version(), "2.0.0");
        vm.prank(admin);
        upgraded.setComplianceUri("ipfs://compliance");
        assertEq(upgraded.complianceUri(), "ipfs://compliance");
    }

    function test013_TBillUpgradeRejectsNonUpgrader() public {
        TBillTokenV2 v2 = new TBillTokenV2();
        vm.expectRevert();
        vm.prank(user);
        tbill.upgradeToAndCall(address(v2), "");
    }

    function test014_GovTokenMetadataAndSupply() public view {
        assertEq(govToken.name(), "RWA Governance Token");
        assertEq(govToken.symbol(), "RWAG");
        assertEq(govToken.totalSupply(), 1_000_000 ether);
    }

    function test015_GovTokenPermitDomainNonces() public view {
        assertEq(govToken.nonces(admin), 0);
    }

    function test016_GovTokenMintByMinter() public {
        vm.prank(admin);
        govToken.mint(user, 100 ether);
        assertEq(govToken.balanceOf(user), 100 ether);
    }

    function test017_GovTokenMintRejectsNonMinter() public {
        vm.expectRevert();
        vm.prank(user);
        govToken.mint(user, 100 ether);
    }

    function test018_GovTokenDelegateVotingPower() public {
        vm.prank(admin);
        govToken.delegate(admin);
        assertEq(govToken.getVotes(admin), 1_000_000 ether);
    }

    function test019_GovTokenPastVotesByTimestamp() public {
        vm.startPrank(admin);
        govToken.delegate(admin);
        vm.warp(block.timestamp + 10);
        assertEq(govToken.getPastVotes(admin, block.timestamp - 1), 1_000_000 ether);
        vm.stopPrank();
    }

    function test020_GovTokenClockModeTimestamp() public view {
        assertEq(govToken.CLOCK_MODE(), "mode=timestamp");
    }

    function test021_CertificateMint() public {
        vm.prank(admin);
        uint256 tokenId = cert.mintCertificate(user, "ipfs://reserve-1");
        assertEq(tokenId, 1);
        assertEq(cert.ownerOf(1), user);
        assertEq(cert.tokenURI(1), "ipfs://reserve-1");
    }

    function test022_CertificateMintRejectsNonCertifier() public {
        vm.expectRevert();
        vm.prank(user);
        cert.mintCertificate(user, "ipfs://reserve-1");
    }

    function test023_CertificateRevoke() public {
        vm.startPrank(admin);
        cert.mintCertificate(user, "ipfs://reserve-1");
        cert.revokeCertificate(1);
        vm.stopPrank();
        vm.expectRevert();
        cert.ownerOf(1);
    }

    function test024_CertificatePauseBlocksTransfer() public {
        vm.prank(admin);
        cert.mintCertificate(user, "ipfs://reserve-1");
        vm.prank(admin);
        cert.pause();
        vm.expectRevert();
        vm.prank(user);
        cert.transferFrom(user, user2, 1);
    }

    function test025_CertificateUnpauseAllowsTransfer() public {
        vm.startPrank(admin);
        cert.mintCertificate(user, "ipfs://reserve-1");
        cert.pause();
        cert.unpause();
        vm.stopPrank();
        vm.prank(user);
        cert.transferFrom(user, user2, 1);
        assertEq(cert.ownerOf(1), user2);
    }

    function test026_VaultDeposit() public {
        vm.prank(user);
        uint256 shares = vault.deposit(100 ether, user);
        assertEq(shares, vault.balanceOf(user));
        assertEq(vault.totalAssets(), 100 ether);
    }

    function test027_VaultMint() public {
        vm.prank(user);
        uint256 assets = vault.mint(50 ether, user);
        assertEq(assets, 50 ether);
        assertEq(vault.balanceOf(user), 50 ether);
    }

    function test028_VaultWithdraw() public {
        vm.startPrank(user);
        vault.deposit(100 ether, user);
        uint256 burned = vault.withdraw(40 ether, user, user);
        vm.stopPrank();
        assertGt(burned, 0);
        assertEq(vault.totalAssets(), 60 ether);
    }

    function test029_VaultRedeem() public {
        vm.startPrank(user);
        vault.deposit(100 ether, user);
        uint256 assets = vault.redeem(20 ether, user, user);
        vm.stopPrank();
        assertGt(assets, 0);
        assertEq(vault.balanceOf(user), 80 ether);
    }

    function test030_VaultReportYield() public {
        vm.startPrank(admin);
        vault.deposit(100 ether, admin);
        vault.reportYield(10 ether);
        vm.stopPrank();
        assertEq(vault.totalAssets(), 110 ether);
    }

    function test031_VaultReportYieldRejectsNonManager() public {
        vm.expectRevert();
        vm.prank(user);
        vault.reportYield(1 ether);
    }

    function test032_VaultPauseBlocksDeposit() public {
        vm.prank(admin);
        vault.pause();
        vm.expectRevert();
        vm.prank(user);
        vault.deposit(1 ether, user);
    }

    function test033_VaultUnpauseAllowsDeposit() public {
        vm.startPrank(admin);
        vault.pause();
        vault.unpause();
        vm.stopPrank();
        vm.prank(user);
        vault.deposit(1 ether, user);
        assertEq(vault.balanceOf(user), 1 ether);
    }

    function test034_VaultPreviewDepositMatchesMintedShares() public {
        uint256 preview = vault.previewDeposit(123 ether);
        vm.prank(user);
        uint256 shares = vault.deposit(123 ether, user);
        assertEq(preview, shares);
    }

    function test035_VaultWithdrawRejectsOverBalance() public {
        vm.expectRevert();
        vm.prank(user);
        vault.withdraw(1 ether, user, user);
    }

    function test036_AmmAddInitialLiquidity() public {
        _seedAmm();
        (uint112 reserve0, uint112 reserve1) = amm.getReserves();
        assertEq(reserve0, 1_000_000 ether);
        assertEq(reserve1, 1_000_000e6);
        assertGt(amm.balanceOf(admin), 0);
    }

    function test037_AmmAddProportionalLiquidity() public {
        _seedAmm();
        vm.prank(user);
        amm.addLiquidity(10_000 ether, 10_000e6, 1, 1, user, block.timestamp + 1);
        assertGt(amm.balanceOf(user), 0);
    }

    function test038_AmmAddLiquiditySlippage() public {
        _seedAmm();
        vm.expectRevert("slippage");
        vm.prank(user);
        amm.addLiquidity(10_000 ether, 1e6, 1, 10_000e6, user, block.timestamp + 1);
    }

    function test039_AmmRemoveLiquidity() public {
        _seedAmm();
        uint256 lp = amm.balanceOf(admin) / 2;
        vm.prank(admin);
        (uint256 amount0, uint256 amount1) =
            amm.removeLiquidity(lp, 1, 1, admin, block.timestamp + 1);
        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test040_AmmRemoveLiquidityRejectsZero() public {
        _seedAmm();
        vm.expectRevert("zero liquidity");
        vm.prank(admin);
        amm.removeLiquidity(0, 1, 1, admin, block.timestamp + 1);
    }

    function test041_AmmGetAmountOutToken0() public {
        _seedAmm();
        uint256 out = amm.getAmountOut(address(tbill), 100 ether);
        assertGt(out, 0);
    }

    function test042_AmmGetAmountOutToken1() public {
        _seedAmm();
        uint256 out = amm.getAmountOut(address(usdc), 100e6);
        assertGt(out, 0);
    }

    function test043_AmmSwapToken0ForToken1() public {
        _seedAmm();
        uint256 beforeBalance = usdc.balanceOf(user);
        vm.prank(user);
        uint256 out = amm.swapExactIn(address(tbill), 100 ether, 1, user, block.timestamp + 1);
        assertEq(usdc.balanceOf(user), beforeBalance + out);
    }

    function test044_AmmSwapToken1ForToken0() public {
        _seedAmm();
        uint256 beforeBalance = tbill.balanceOf(user);
        vm.prank(user);
        uint256 out = amm.swapExactIn(address(usdc), 100e6, 1, user, block.timestamp + 1);
        assertEq(tbill.balanceOf(user), beforeBalance + out);
    }

    function test045_AmmSwapRejectsSlippage() public {
        _seedAmm();
        uint256 out = amm.getAmountOut(address(tbill), 100 ether);
        vm.expectRevert("slippage");
        vm.prank(user);
        amm.swapExactIn(address(tbill), 100 ether, out + 1, user, block.timestamp + 1);
    }

    function test046_AmmRejectsExpiredDeadline() public {
        _seedAmm();
        vm.expectRevert("expired");
        vm.prank(user);
        amm.swapExactIn(address(tbill), 100 ether, 1, user, block.timestamp - 1);
    }

    function test047_AmmRejectsInvalidToken() public {
        _seedAmm();
        vm.expectRevert("invalid token");
        amm.getAmountOut(address(0xDEAD), 100 ether);
    }

    function test048_AmmKDoesNotDecreaseOnSwap() public {
        _seedAmm();
        (uint112 r0Before, uint112 r1Before) = amm.getReserves();
        vm.prank(user);
        amm.swapExactIn(address(tbill), 100 ether, 1, user, block.timestamp + 1);
        (uint112 r0After, uint112 r1After) = amm.getReserves();
        assertGe(uint256(r0After) * uint256(r1After), uint256(r0Before) * uint256(r1Before));
    }

    function test049_OracleLatestPrice() public view {
        (uint256 answer, uint256 updatedAt) = oracle.latestPrice();
        assertEq(answer, 100_000_000);
        assertGt(updatedAt, 0);
    }

    function test050_OracleLatestReserve() public view {
        (uint256 answer,) = oracle.latestReserve();
        assertEq(answer, 105_000_000);
    }

    function test051_OracleRejectsStalePrice() public {
        priceFeed.setUpdatedAt(block.timestamp - 2 days);
        vm.expectRevert();
        oracle.latestPrice();
    }

    function test052_OracleRejectsNegativeAnswer() public {
        priceFeed.updateAnswer(-1);
        vm.expectRevert();
        oracle.latestPrice();
    }

    function test053_OracleSetMaxStaleness() public {
        vm.prank(admin);
        oracle.setMaxStaleness(2 days);
        assertEq(oracle.maxStaleness(), 2 days);
    }

    function test054_OracleSetMaxStalenessOnlyAdmin() public {
        vm.expectRevert();
        vm.prank(user);
        oracle.setMaxStaleness(2 days);
    }

    function test055_OracleSetFeeds() public {
        MockV3Aggregator newPrice = new MockV3Aggregator(8, 99_000_000);
        MockV3Aggregator newReserve = new MockV3Aggregator(8, 101_000_000);
        vm.prank(admin);
        oracle.setFeeds(newPrice, newReserve);
        (uint256 answer,) = oracle.latestPrice();
        assertEq(answer, 99_000_000);
    }

    function test056_TreasuryDepositToken() public {
        vm.startPrank(user);
        tbill.approve(address(treasury), 50 ether);
        treasury.depositToken(IERC20(address(tbill)), 50 ether);
        vm.stopPrank();
        assertEq(tbill.balanceOf(address(treasury)), 50 ether);
    }

    function test057_TreasuryPullTokenPayment() public {
        vm.startPrank(admin);
        tbill.approve(address(treasury), 50 ether);
        treasury.depositToken(IERC20(address(tbill)), 50 ether);
        treasury.scheduleTokenPayment(IERC20(address(tbill)), user, 25 ether);
        vm.stopPrank();
        vm.prank(user);
        treasury.withdrawTokenPayment(IERC20(address(tbill)));
        assertEq(treasury.tokenPayments(address(tbill), user), 0);
    }

    function test058_TreasuryRejectsUnauthorizedSchedule() public {
        vm.expectRevert();
        vm.prank(user);
        treasury.scheduleTokenPayment(IERC20(address(tbill)), user, 25 ether);
    }

    function test059_TreasuryPullEthPayment() public {
        vm.deal(address(treasury), 10 ether);
        vm.prank(admin);
        treasury.scheduleEthPayment(user, 1 ether);
        uint256 beforeBalance = user.balance;
        vm.prank(user);
        treasury.withdrawEthPayment();
        assertEq(user.balance, beforeBalance + 1 ether);
    }

    function test060_TreasuryRejectsEmptyWithdrawal() public {
        vm.expectRevert("nothing owed");
        vm.prank(user);
        treasury.withdrawEthPayment();
    }

    function test061_FactoryDeployCreate() public {
        vm.prank(admin);
        address proxy = factory.deployAssetCreate("Factory T-Bill", "fTBILL", admin, registry);
        assertEq(TBillToken(proxy).name(), "Factory T-Bill");
    }

    function test062_FactoryDeployCreate2PredictedAddress() public {
        bytes32 salt = keccak256("tbill-salt");
        address predicted =
            factory.predictCreate2Address(salt, "Factory T-Bill", "fTBILL", admin, registry);
        vm.prank(admin);
        address actual =
            factory.deployAssetCreate2(salt, "Factory T-Bill", "fTBILL", admin, registry);
        assertEq(actual, predicted);
    }

    function test063_FactoryRejectsUnauthorizedDeploy() public {
        vm.expectRevert();
        vm.prank(user);
        factory.deployAssetCreate("Factory T-Bill", "fTBILL", admin, registry);
    }

    function test064_FactoryImplementationIsInitializedLocked() public {
        address impl = factory.tbillImplementation();
        vm.expectRevert();
        TBillToken(impl).initialize("Bad", "BAD", user, registry);
    }

    function test065_MathSqrtYulMatchesSolidity() public pure {
        assertEq(RwaMath.sqrtYul(0), RwaMath.sqrtSolidity(0));
        assertEq(RwaMath.sqrtYul(1), RwaMath.sqrtSolidity(1));
        assertEq(RwaMath.sqrtYul(10_000), RwaMath.sqrtSolidity(10_000));
        assertEq(RwaMath.sqrtYul(123_456_789), RwaMath.sqrtSolidity(123_456_789));
    }

    function test066_MathQuote() public pure {
        assertEq(RwaMath.quote(10, 100, 200), 20);
    }

    function test067_VulnerableReentrancyCaseStudyDrainsFunds() public {
        VulnerableEthVault vulnerable = new VulnerableEthVault();
        FixedEthVault fixedVault = new FixedEthVault();
        ReentrancyAttacker attacker = new ReentrancyAttacker(vulnerable, fixedVault);
        vulnerable.deposit{ value: 3 ether }();
        attacker.attackVulnerable{ value: 1 ether }();
        assertLt(address(vulnerable).balance, 3 ether);
        assertGt(address(attacker).balance, 1 ether);
    }

    function test068_FixedReentrancyCaseStudyKeepsAccounting() public {
        VulnerableEthVault vulnerable = new VulnerableEthVault();
        FixedEthVault fixedVault = new FixedEthVault();
        ReentrancyAttacker attacker = new ReentrancyAttacker(vulnerable, fixedVault);
        fixedVault.deposit{ value: 3 ether }();
        attacker.attackFixed{ value: 1 ether }();
        assertEq(address(fixedVault).balance, 3 ether);
    }

    function test069_VulnerableAccessControlCaseStudyAllowsAnyone() public {
        VulnerableIssuer vulnerable = new VulnerableIssuer();
        vm.prank(user);
        vulnerable.mint(user, 100);
        assertEq(vulnerable.minted(user), 100);
    }

    function test070_FixedAccessControlCaseStudyRejectsAnyone() public {
        FixedIssuer fixedIssuer = new FixedIssuer(admin);
        vm.expectRevert();
        vm.prank(user);
        fixedIssuer.mint(user, 100);
    }

    function test071_GovernorParameters() public {
        (RwaGovernanceToken token, TimelockController timelock, RwaGovernor governor) =
            _deployGovernorStack();
        assertEq(address(governor.token()), address(token));
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 1 weeks);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test072_GovernorLifecycleProposeVoteQueueExecute() public {
        (RwaGovernanceToken token, TimelockController timelock, RwaGovernor governor) =
            _deployGovernorStack();
        ProtocolTreasury governedTreasury = new ProtocolTreasury(admin);
        vm.startPrank(admin);
        governedTreasury.grantRole(governedTreasury.TREASURY_MANAGER_ROLE(), address(timelock));
        vm.stopPrank();
        vm.deal(address(governedTreasury), 2 ether);

        vm.warp(block.timestamp + 1);
        address[] memory targets = new address[](1);
        targets[0] = address(governedTreasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(ProtocolTreasury.scheduleEthPayment, (user, 1 ether));
        string memory description = "Schedule T-Bill distribution";

        vm.prank(admin);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint8(governor.state(proposalId)), uint8(GovernorState.Pending));

        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.prank(admin);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(GovernorState.Succeeded));

        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(GovernorState.Queued));

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(governedTreasury.ethPayments(user), 1 ether);
        assertEq(token.getVotes(admin), 1_000_000 ether);
    }

    function test073_GovernorRejectsBelowProposalThreshold() public {
        (RwaGovernanceToken token,, RwaGovernor governor) = _deployGovernorStack();
        vm.prank(admin);
        token.transfer(user, 1 ether);
        vm.prank(user);
        token.delegate(user);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(ProtocolTreasury.scheduleEthPayment, (user, 1 ether));
        vm.expectRevert();
        vm.prank(user);
        governor.propose(targets, values, calldatas, "too small");
    }

    function test074_GovernorClockMatchesTokenClock() public {
        (RwaGovernanceToken token,, RwaGovernor governor) = _deployGovernorStack();
        assertEq(governor.clock(), token.clock());
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }

    function test075_FuzzAmmSwapDoesNotDecreaseK(uint96 amountIn) public {
        _seedAmm();
        uint256 bounded = bound(uint256(amountIn), 1 ether, 10_000 ether);
        (uint112 r0Before, uint112 r1Before) = amm.getReserves();
        vm.prank(user);
        amm.swapExactIn(address(tbill), bounded, 1, user, block.timestamp + 1);
        (uint112 r0After, uint112 r1After) = amm.getReserves();
        assertGe(uint256(r0After) * uint256(r1After), uint256(r0Before) * uint256(r1Before));
    }

    function test076_FuzzVaultDepositWithdraw(uint96 amount) public {
        uint256 assets = bound(uint256(amount), 2, 100_000 ether);
        vm.startPrank(user);
        uint256 shares = vault.deposit(assets, user);
        uint256 burned = vault.withdraw(assets / 2, user, user);
        vm.stopPrank();
        assertGt(shares, 0);
        assertGt(burned, 0);
        assertLe(vault.totalAssets(), assets);
    }

    function test077_FuzzVaultRedeemRounding(uint96 amount) public {
        uint256 assets = bound(uint256(amount), 2, 100_000 ether);
        vm.startPrank(user);
        uint256 shares = vault.deposit(assets, user);
        uint256 redeemed = vault.redeem(shares / 2, user, user);
        vm.stopPrank();
        assertLe(redeemed, assets);
    }

    function test078_FuzzGovernanceVotingPower(uint96 amount) public {
        uint256 minted = bound(uint256(amount), 1 ether, 100_000 ether);
        vm.prank(admin);
        govToken.mint(user, minted);
        vm.prank(user);
        govToken.delegate(user);
        assertEq(govToken.getVotes(user), minted);
    }

    function test079_FuzzMathSqrt(uint128 x) public pure {
        uint256 y = uint256(x);
        uint256 root = RwaMath.sqrtYul(y);
        assertLe(root * root, y);
        assertGt((root + 1) * (root + 1), y);
    }

    function test080_FuzzFactoryPredict(bytes32 salt) public view {
        address predicted = factory.predictCreate2Address(salt, "A", "A", admin, registry);
        assertNotEq(predicted, address(0));
    }

    enum GovernorState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }
}
