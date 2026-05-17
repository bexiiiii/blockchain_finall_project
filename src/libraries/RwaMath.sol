// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RwaMath {
    error DivisionByZero();

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256)
    {
        if (reserveA == 0) revert DivisionByZero();
        return (amountA * reserveB) / reserveA;
    }

    function sqrtSolidity(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function sqrtYul(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                assembly ("memory-safe") {
                    x := div(add(div(y, x), x), 2)
                }
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
