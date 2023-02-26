// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// 字节码程度的溢出原理参考文章 https://cn-sec.com/archives/1140400.html

//  安全转换方法
/// @title Safe casting methods
// 包含用于在类型之间安全强制转换的方法
/// @notice Contains methods for safely casting between types
library SafeCast {
    // 将uint256转换到uint160,回滚溢出
    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param y The uint256 to be downcasted
    // 向下转换的整数，现在类型是uint160
    /// @return z The downcasted integer, now type uint160
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        // 先用uint160方法把y转换成160位的正整数，然后赋值给z，
        // 再对比z和y是否一致（是否存在溢出问题）
        require((z = uint160(y)) == y);
        // 160位指的是 储存空间里，160个槽位，每个槽位可以存放（0/1），然后最大能记录的数 是，2**159 - 1,最小值是0
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y);
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
}
