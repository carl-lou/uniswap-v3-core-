// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title FixedPoint96
// 一个处理二进制定点数的库，
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    // 16^24= 2^(4*24)=2^96
    uint256 internal constant Q96 = 0x10000_0000000000_0000000000;
}
