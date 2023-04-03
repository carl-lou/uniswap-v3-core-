// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Pool state that never changes 永不改变的池状态

// 对于一个池，这些参数永远是固定的，也就是说，方法总是返回相同的值
/// @notice These parameters are fixed for a pool forever, i.e., the methods will always return the same values
interface IUniswapV3PoolImmutables {
    // 部署池的工厂合约，它必须遵循IUniswapV3Factory接口
    /// @notice The contract that deployed the pool, which must adhere to the IUniswapV3Factory interface
    /// @return The contract address 合约地址
    function factory() external view returns (address);

    /// @notice The first of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token1() external view returns (address);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6 流动性池子的收费单位是bip的百分之一，即1e-6
    /// @return The fee
    function fee() external view returns (uint24);

    /// @notice The pool tick spacing
    // Ticks只能用于该值的倍数，最小值为1并且始终为正，例如:tickSpacing为3意味着tick可以每3个tick初始化一次，即…， -6， -3, 0,3,6，…该值为int24，以避免强制转换，即使它总是正的。
    /// @dev Ticks can only be used at multiples of this value, minimum of 1 and always positive
    /// e.g.: a tickSpacing of 3 means ticks can be initialized every 3rd tick, i.e., ..., -6, -3, 0, 3, 6, ...
    /// This value is an int24 to avoid casting even though it is always positive.
    /// @return The tick spacing
    function tickSpacing() external view returns (int24);

    // 可以使用范围内任何刻度的头寸流动性的最大金额
    /// @notice The maximum amount of position liquidity that can use any tick in the range
    // 这个参数每tick强制执行一次，以防止流动性在任何时候溢出uint128，也防止使用范围外的流动性来防止向池中添加范围内的流动性
    /// @dev This parameter is enforced per tick to prevent liquidity from overflowing a uint128 at any point, and
    /// also prevents out-of-range liquidity from being used to prevent adding in-range liquidity to a pool
    /// @return The max amount of liquidity per tick
    function maxLiquidityPerTick() external view returns (uint128);
}
