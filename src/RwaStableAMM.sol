// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { RwaMath } from "./libraries/RwaMath.sol";

contract RwaStableAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 public blockTimestampLast;

    event LiquidityAdded(
        address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity
    );
    event Swap(
        address indexed trader,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(IERC20 token0_, IERC20 token1_) ERC20("RWA AMM LP Token", "rwaLP") {
        require(address(token0_) != address(0) && address(token1_) != address(0), "token zero");
        require(address(token0_) != address(token1_), "same token");
        token0 = token0_;
        token1 = token1_;
    }

    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "expired");
        _;
    }

    function getReserves() public view returns (uint112 reserve0_, uint112 reserve1_) {
        reserve0_ = reserve0;
        reserve1_ = reserve1;
    }

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        require(to != address(0), "to zero");
        (uint112 reserve0_, uint112 reserve1_) = getReserves();
        if (reserve0_ == 0 && reserve1_ == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = RwaMath.quote(amount0Desired, reserve0_, reserve1_);
            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, "amount1 slippage");
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = RwaMath.quote(amount1Desired, reserve1_, reserve0_);
                require(amount0Optimal >= amount0Min, "amount0 slippage");
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        require(amount0 >= amount0Min && amount1 >= amount1Min, "slippage");
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 supply = totalSupply();
        if (supply == 0) {
            liquidity = RwaMath.sqrtYul(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            liquidity = RwaMath.min((amount0 * supply) / reserve0_, (amount1 * supply) / reserve1_);
        }
        require(liquidity > 0, "insufficient liquidity");
        _mint(to, liquidity);
        _updateReserves();
        emit LiquidityAdded(to, amount0, amount1, liquidity);
    }

    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amount0, uint256 amount1) {
        require(to != address(0), "to zero");
        require(liquidity > 0, "zero liquidity");
        uint256 supply = totalSupply();
        amount0 = (liquidity * token0.balanceOf(address(this))) / supply;
        amount1 = (liquidity * token1.balanceOf(address(this))) / supply;
        require(amount0 >= amount0Min && amount1 >= amount1Min, "slippage");

        _burn(msg.sender, liquidity);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);
        _updateReserves();
        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    function getAmountOut(address tokenIn, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "zero amount");
        (uint112 reserveIn, uint112 reserveOut) = _reservesFor(tokenIn);
        require(reserveIn > 0 && reserveOut > 0, "empty reserves");
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOut)
            / (uint256(reserveIn) * FEE_DENOMINATOR + amountInWithFee);
    }

    function swapExactIn(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountOut) {
        require(to != address(0), "to zero");
        amountOut = getAmountOut(tokenIn, amountIn);
        require(amountOut >= minAmountOut, "slippage");

        if (tokenIn == address(token0)) {
            token0.safeTransferFrom(msg.sender, address(this), amountIn);
            token1.safeTransfer(to, amountOut);
        } else if (tokenIn == address(token1)) {
            token1.safeTransferFrom(msg.sender, address(this), amountIn);
            token0.safeTransfer(to, amountOut);
        } else {
            revert("invalid token");
        }

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(balance0 * balance1 >= uint256(reserve0) * uint256(reserve1), "k decreased");
        _setReserves(balance0, balance1);
        emit Swap(msg.sender, tokenIn, amountIn, amountOut, to);
    }

    function _reservesFor(address tokenIn)
        internal
        view
        returns (uint112 reserveIn, uint112 reserveOut)
    {
        if (tokenIn == address(token0)) return (reserve0, reserve1);
        if (tokenIn == address(token1)) return (reserve1, reserve0);
        revert("invalid token");
    }

    function _updateReserves() internal {
        _setReserves(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    function _setReserves(uint256 balance0, uint256 balance1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "reserve overflow");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }
}
