// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TBillToken } from "../../src/TBillToken.sol";
import { TBillVault } from "../../src/TBillVault.sol";
import { RwaStableAMM } from "../../src/RwaStableAMM.sol";
import { ProtocolTreasury } from "../../src/ProtocolTreasury.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";

contract ProtocolHandler {
    TBillToken public tbill;
    MockERC20 public usdc;
    TBillVault public vault;
    RwaStableAMM public amm;
    ProtocolTreasury public treasury;
    address public user;

    uint256 public lastK;
    uint256 public depositedToTreasury;

    constructor(
        TBillToken tbill_,
        MockERC20 usdc_,
        TBillVault vault_,
        RwaStableAMM amm_,
        ProtocolTreasury treasury_
    ) {
        tbill = tbill_;
        usdc = usdc_;
        vault = vault_;
        amm = amm_;
        treasury = treasury_;
        user = address(this);
        tbill.approve(address(vault), type(uint256).max);
        tbill.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        tbill.approve(address(treasury), type(uint256).max);
    }

    function depositVault(uint96 amount) external {
        uint256 assets = _bound(amount, 1, 1000 ether);
        if (tbill.balanceOf(user) >= assets) {
            vault.deposit(assets, user);
        }
    }

    function swapTbill(uint96 amount) external {
        uint256 assets = _bound(amount, 1 ether, 1000 ether);
        if (tbill.balanceOf(user) >= assets) {
            try amm.swapExactIn(address(tbill), assets, 1, user, block.timestamp + 1) {
                _recordK();
            } catch { }
        }
    }

    function swapUsdc(uint96 amount) external {
        uint256 assets = _bound(amount, 1e6, 1000e6);
        if (usdc.balanceOf(user) >= assets) {
            try amm.swapExactIn(address(usdc), assets, 1, user, block.timestamp + 1) {
                _recordK();
            } catch { }
        }
    }

    function depositTreasury(uint96 amount) external {
        uint256 assets = _bound(amount, 1, 100 ether);
        if (tbill.balanceOf(user) >= assets) {
            treasury.depositToken(IERC20(address(tbill)), assets);
            depositedToTreasury += assets;
        }
    }

    function _recordK() internal {
        (uint112 r0, uint112 r1) = amm.getReserves();
        lastK = uint256(r0) * uint256(r1);
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        return min + (x % (max - min + 1));
    }
}

contract ProtocolInvariantsTest is Test {
    TBillToken internal tbill;
    MockERC20 internal usdc;
    TBillVault internal vault;
    RwaStableAMM internal amm;
    ProtocolTreasury internal treasury;
    ProtocolHandler internal handler;
    uint256 internal initialSupply;
    uint256 internal initialK;

    function setUp() public {
        TBillToken implementation = new TBillToken();
        tbill = TBillToken(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        TBillToken.initialize,
                        ("Tokenized T-Bill", "TBILL", address(this), address(0))
                    )
                )
            )
        );
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new TBillVault(IERC20(address(tbill)), address(this));
        amm = new RwaStableAMM(IERC20(address(tbill)), IERC20(address(usdc)));
        treasury = new ProtocolTreasury(address(this));

        tbill.mint(address(this), 2_000_000 ether);
        usdc.mint(address(this), 2_000_000e6);
        tbill.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000_000 ether, 1_000_000e6, 1, 1, address(this), block.timestamp + 1);
        (uint112 r0, uint112 r1) = amm.getReserves();
        initialK = uint256(r0) * uint256(r1);

        handler = new ProtocolHandler(tbill, usdc, vault, amm, treasury);
        tbill.mint(address(handler), 100_000 ether);
        usdc.mint(address(handler), 100_000e6);
        initialSupply = tbill.totalSupply();
        targetContract(address(handler));
    }

    function invariant_ConstantProductNeverBelowSeed() public view {
        (uint112 r0, uint112 r1) = amm.getReserves();
        assertGe(uint256(r0) * uint256(r1), initialK);
    }

    function invariant_TBillSupplyConserved() public view {
        assertEq(tbill.totalSupply(), initialSupply);
    }

    function invariant_VaultAssetsCoverShares() public view {
        assertGe(tbill.balanceOf(address(vault)) + 1, vault.convertToAssets(vault.totalSupply()));
    }

    function invariant_TreasuryAccountingCovered() public view {
        assertGe(tbill.balanceOf(address(treasury)), handler.depositedToTreasury());
    }

    function invariant_AmmReservesMatchBalances() public view {
        (uint112 r0, uint112 r1) = amm.getReserves();
        assertEq(r0, tbill.balanceOf(address(amm)));
        assertEq(r1, usdc.balanceOf(address(amm)));
    }
}
