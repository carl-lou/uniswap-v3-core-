// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Pool state that can change 可以更改的池状态
// 这些方法组成了池的状态，并且可以以任何频率改变，包括每个事务多次
/// @notice These methods compose the pool's state, and can change with any frequency including multiple times
/// per transaction
interface IUniswapV3PoolState {
    // 池中的第0个存储槽存储许多值，并且在外部访问时暴露为单一方法以节省气体。
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.

    // sqrtPriceX96作为 (token1/token0)的平方根 Q64.96 value tick池的当前刻度，即根据运行的最后一个刻度转换。
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// tick The current tick of the pool, i.e. according to the last tick transition that was run.
    // 如果价格在一个刻度上，这个值可能并不总是等于SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96)
    /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96) if the price is on a tick
    /// boundary.

    // observationCardinality当前池中存储的最大观测值数，observationCardinalityNext下一个最大观测值数，
    // 当观测值被写入时更新。为池中的两个令牌支付的协议费用。
    /// observationIndex The index of the last oracle observation that was written,
    /// observationCardinality The current maximum number of observations stored in the pool,
    /// observationCardinalityNext The next maximum number of observations, to be updated when the observation.
    /// feeProtocol The protocol fee for both tokens of the pool.

    // 编码为两个4位值，其中token1的协议费用移动了4位，而token0的协议费用是较低的4位。
    // 用作掉期费用分数的分母，例如4表示掉期费用的1/4。unlocked当前池是否锁定重入
    /// Encoded as two 4 bit values, where the protocol fee of token1 is shifted 4 bits and the protocol fee of token0
    /// is the lower 4 bits. Used as the denominator of a fraction of the swap fee, e.g. 4 means 1/4th of the swap fee.
    /// unlocked Whether the pool is currently locked to reentrancy
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    // 费用增长为Q128.128（-2^127 到 2^127 - 2^-96)，在池的整个生命周期内，每单位流动性收取的token0费用
    /// @notice The fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
    /// @dev This value can overflow the uint256 该值可以溢出uint256
    function feeGrowthGlobal0X128() external view returns (uint256);

    /// @notice The fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
    /// @dev This value can overflow the uint256
    function feeGrowthGlobal1X128() external view returns (uint256);

    // 应给与合约的token0和token1的数量（手续费用）
    /// @notice The amounts of token0 and token1 that are owed to the protocol
    // 任何token的协议费用都不会超过uint128 max
    /// @dev Protocol fees will never exceed uint128 max in either token
    function protocolFees() external view returns (uint128 token0, uint128 token1);

    //  liquidity等于x*y=k中K的平方根  ，liquidity*liquidity=常数k=x*y；  为了方便减少运算，减少溢出的可能性
    // 当前可用于池的范围内的流动性
    /// @notice The currently in range liquidity available to the pool
    // 该值与所有刻度的总流动性无关
    /// @dev This value has no relationship to the total liquidity across all ticks
    function liquidity() external view returns (uint128);

    // 查找池中特定刻度的信息
    /// @notice Look up information about a specific tick in the pool
    /// @param tick The tick to look up  要查找的刻度
    // 使用该池作为tick down或tick up的头寸流动性总额，
    // 使用池作为点低或点高的头寸流动性的总量
    /// @return liquidityGross the total amount of position liquidity that uses the pool either as tick lower or
    /// tick upper,

    // liquidityNet当池价格越过tick时流动性变化的多少，
    // liquidityNet how much liquidity changes when the pool price crosses the tick,

    // feeGrowthOutside0X128在token0中，从当前tick开始，tick另一侧的费用增长，
    // 另一侧也叫做外侧，在这个刻度的外侧（外侧需要看 当前tick刻度在当前tick区间的左侧还是右侧，
    // 若在左侧，那外侧就是左侧，若在右侧则外侧就是右侧），
    /// feeGrowthOutside0X128 the fee growth on the other side of the tick from the current tick in token0,

    // fegrowthoutside1x128从token1的当前tick开始，tick另一侧的费用增长，
    /// feeGrowthOutside1X128 the fee growth on the other side of the tick from the current tick in token1,

    // tickcumulative在当前刻度刻度另一侧的累积刻度值之外
    /// tickCumulativeOutside the cumulative tick value on the other side of the tick from the current tick

    // secondsPerLiquidityOutsideX128从当前刻度开始，每个流动性在刻度另一侧花费的秒数，
    /// secondsPerLiquidityOutsideX128 the seconds spent per liquidity on the other side of the tick from the current tick,

    // secondsOutside 从当前刻度到刻度另一端所花费的时间，
    // initialized 如果标记被初始化，即liquidityGross大于0，则设置为true，否则等于false。
    // 外部值只能在tick被初始化时使用，即如果liquidityGross大于0。
    // 此外，这些值只是相对的，必须仅用于与特定位置的先前快照进行比较
    /// secondsOutside the seconds spent on the other side of the tick from the current tick,
    /// initialized Set to true if the tick is initialized, i.e. liquidityGross is greater than 0, otherwise equal to false.
    /// Outside values can only be used if the tick is initialized, i.e. if liquidityGross is greater than 0.
    /// In addition, these values are only relative and must be used only in comparison to previous snapshots for
    /// a specific position.
    function ticks(
        // log(1.0001的平方根) * 当前价格P的平方根(也就是sqrtPriceX96)  
        // log(sqrt(1.001)) * sqrt(p)
        // 其中 P = y/X = sqrtPriceX96 * sqrtPriceX96
        // int24 tick 相当于 索引
        int24 tick
    )
        external
        view
        returns (
            // 不需要记录所有tick，只需要记录各个流动性的上下边界tick值
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );

    // 返回256个打包的标记初始化布尔值。更多信息请参见TickBitmap
    /// @notice Returns 256 packed tick initialized boolean values. See TickBitmap for more information
    function tickBitmap(int16 wordPosition) external view returns (uint256);

    // 通过位置的键返回有关位置的信息
    /// @notice Returns the information about a position by the position's key
    // 该位置的键是由所有者tickLower和tickUpper组成的原像的散列
    /// @param key The position's key is a hash of a preimage composed by the owner, tickLower and tickUpper
    // 头寸的流动性，
    /// @return _liquidity The amount of liquidity in the position,
    // 在最后一次mint/burn/poke的tick范围内，token0的费用增长
    /// Returns feeGrowthInside0LastX128 fee growth of token0 inside the tick range as of the last mint/burn/poke,
    // 截止到最后一次mint/burn/poke, token1在tick范围内的费用增长
    /// Returns feeGrowthInside1LastX128 fee growth of token1 inside the tick range as of the last mint/burn/poke,
    // token0的计算量欠的位置作为最后一次mint/burn/poke，
    /// Returns tokensOwed0 the computed amount of token0 owed to the position as of the last mint/burn/poke,
    /// Returns tokensOwed1 the computed amount of token1 owed to the position as of the last mint/burn/poke
    function positions(
        bytes32 key
    )
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    // 返回关于特定观察索引的数据
    /// @notice Returns data about a specific observation index
    // 要获取的观察数组的元素
    /// @param index The element of the observations array to fetch
    // 您很可能希望使用#observe()而不是这个方法来获取一段时间前的观察结果，而不是数组中的特定索引。
    /// @dev You most likely want to use #observe() instead of this method to get an observation as of some amount of time
    /// ago, rather than at a specific index in the array.
    // 观测的时间戳，
    /// @return blockTimestamp The timestamp of the observation,
    // 从观察时间戳开始，刻度乘以池生命周期的秒数，
    /// Returns tickCumulative the tick multiplied by seconds elapsed for the life of the pool as of the observation timestamp,
    // 在观察时间戳时，池的生命周期内每秒的流动性，
    /// Returns secondsPerLiquidityCumulativeX128 the seconds per in range liquidity for the life of the pool as of the observation timestamp,
    // 观察值是否已经初始化，值是否可以安全使用
    /// Returns initialized whether the observation has been initialized and the values are safe to use
    function observations(
        uint256 index
    )
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
}
