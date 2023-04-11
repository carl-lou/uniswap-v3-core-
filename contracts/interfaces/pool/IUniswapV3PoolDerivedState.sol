// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Pool state that is not stored 未存储的池状态
// 包含视图函数，以提供有关计算而不是存储在区块链上的池的信息。这里的函数可能有不同的燃气成本。
/// @notice Contains view functions to provide information about the pool that is computed rather than stored on the
/// blockchain. The functions here may have variable gas costs.
interface IUniswapV3PoolDerivedState {
    // 从当前块时间戳中返回每个时间戳' secondsAgo '的累计tick和流动性
    /// @notice Returns the cumulative tick and liquidity as of each timestamp `secondsAgo` from the current block timestamp
    // 要获得时间加权平均滴答或范围内流动性，您必须使用两个值来调用它，
    // 一个表示周期的开始，另一个表示周期的结束。例如，要得到最后一个小时的时间加权平均滴答，必须调用secondsAgos =[360,0]。
    /// @dev To get a time weighted average tick or liquidity-in-range, you must call this with two values, one representing
    /// the beginning of the period and another for the end of the period. E.g., to get the last hour time-weighted average tick,
    /// you must call it with secondsAgos = [3600, 0].
    // 时间加权平均刻度表示池的几何时间加权平均价格，以token1 / token0的对数根号(1.0001)为单位。TickMath库可用于从刻度值转换为比率。
    /// @dev The time weighted average tick represents the geometric time weighted average price of the pool, in
    /// log base sqrt(1.0001) of token1 / token0. The TickMath library can be used to go from a tick value to a ratio.
    // 从多长时间以前，每个累计滴答和流动性价值应返回
    /// @param secondsAgos From how long ago each cumulative tick and liquidity value should be returned
    /// @return tickCumulatives Cumulative tick values as of each `secondsAgos` from the current block timestamp
    /// @return secondsPerLiquidityCumulativeX128s Cumulative seconds per liquidity-in-range value as of each `secondsAgos` from the current block
    /// timestamp
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    // 返回两个tick之间的 tick累积值，流动性累积值，秒数
    /// @notice Returns a snapshot of the tick cumulative, seconds per liquidity and seconds inside a tick range
    // 快照只能与在某个位置存在的时间段内拍摄的其他快照进行比较。也就是说，
    // 如果从第一个快照到第二个快照之间的整个时间内，某个位置都没有被保存，则不能进行快照比较。
    /// @dev Snapshots must only be compared to other snapshots, taken over a period for which a position existed.
    /// I.e., snapshots cannot be compared if a position is not held for the entire period between when the first
    /// snapshot is taken and the second snapshot is taken.
    /// @param tickLower The lower tick of the range  范围的下刻度
    /// @param tickUpper The upper tick of the range
    /// @return tickCumulativeInside The snapshot of the tick accumulator for the range  范围的刻度累加器的快照
    /// @return secondsPerLiquidityInsideX128 The snapshot of seconds per liquidity for the range 范围内每个流动性的秒快照
    /// @return secondsInside The snapshot of seconds per liquidity for the range
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        );
}
