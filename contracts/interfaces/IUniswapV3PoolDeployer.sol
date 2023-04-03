// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// 能够部署Uniswap V3池的契约的接口
/// @title An interface for a contract that is capable of deploying Uniswap V3 Pools
// 构造池的契约必须实现此功能，以便将参数传递给池
/// @notice A contract that constructs a pool must implement this to pass arguments to the pool
// 这用于避免在池契约中有构造函数参数，这将导致池的init代码哈希为常量，从而允许在chai上轻松计算池的CREATE2地址
/// @dev This is used to avoid having constructor arguments in the pool contract, which results in the init code hash
/// of the pool being constant allowing the CREATE2 address of the pool to be cheaply computed on-chain
interface IUniswapV3PoolDeployer {
    // 获取用于构造池的参数，在池创建期间临时设置。
    /// @notice Get the parameters to be used in constructing the pool, set transiently during pool creation.
    // 由池构造函数调用以获取池的参数
    /// @dev Called by the pool constructor to fetch the parameters of the pool
    // 工厂地址
    /// Returns factory The factory address
    // 按地址排序顺序的池的第一个标记
    /// Returns token0 The first token of the pool by address sort order
    /// Returns token1 The second token of the pool by address sort order
    // 池中每一次掉期所收取的费用，以百分之一bip为单位
    /// Returns fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    // 初始化刻度之间的最小刻度数
    /// Returns tickSpacing The minimum number of ticks between initialized ticks
    function parameters()
        external
        view
        returns (
            address factory,
            address token0,
            address token1,
            uint24 fee,
            int24 tickSpacing
        );
}
