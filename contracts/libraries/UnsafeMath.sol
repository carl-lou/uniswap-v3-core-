// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
// 不检查输入输出的溢出情况，也是节约gas费
/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
library UnsafeMath {
    /// @notice Returns ceil(x / y) 向上取证
    // 除0具有未指定的行为，必须在外部进行检查,  y不能为0的检查需要在外部进行
    /// @dev division by 0 has unspecified behavior, and must be checked externally
    /// @param x The dividend
    /// @param y The divisor
    /// @return z The quotient, ceil(x / y)
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // div(x, y)获取整数
            // gt(x, y)； if x > y返回1, 否则返回0；  也就是只要x %y 的余数不为0， gt(mode(x,y),0)就为1
            // 也就是只要有余数（x/y不能整除），就向上取整数
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }
}
