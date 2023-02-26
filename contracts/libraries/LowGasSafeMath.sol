// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

// 优化溢出和下溢 安全的数学操作
/// @title Optimized overflow and underflow safe math operations
// 这个库包含的数学操作的方法 可以及时回滚溢出或者下溢,以减少gas费花费
/// @notice Contains methods for doing math operations that revert on overflow or underflow for minimal gas cost
library LowGasSafeMath {
    // 返回x + y的和，如果sum溢出uint256则报错回滚
    /// @notice Returns x + y, reverts if sum overflows uint256
    // 被加数
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // 赋值给返回的z，就相当于return了。然后也做一下 溢出校验，如果没通过require会报错
        require((z = x + y) >= x);
    }

    // 返回x-y的差值 如果下溢，则回滚
    // 下溢就是0-1的结果 不是-1，而是2**255-1 , 因为uint256是无符号的,只能正整数
    /// @notice Returns x - y, reverts if underflows
    /// @param x The minuend 被减数
    /// @param y The subtrahend 减数
    /// @return z The difference of x and y   x和y的差
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    /// @notice Returns x * y, reverts if overflows
    /// @param x The multiplicand
    /// @param y The multiplier
    /// @return z The product of x and y
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    /// @notice Returns x + y, reverts if overflows or underflows
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x == (y >= 0));
    }

    /// @notice Returns x - y, reverts if overflows or underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x - y) <= x == (y >= 0));
    }
}
