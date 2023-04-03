// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './TickMath.sol';
import './LiquidityMath.sol';

/// @title Tick  单点刻度，不是区间;  其实这里记录的都是激活的tick，是position头寸 的上下边界 tick 
// 包含管理参数流程和相关计算的函数；所有pool的所有tick（激活+未激活）都是一样的，都定义了一个价格为1的tick
// tick的索引为log(sqrt(1.0001)) * sqrt(P),是一个整数，i=0时，P为1
/// @notice Contains functions for managing tick processes and relevant calculations
library Tick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    // 存储在每个初始化的 单个刻度 上的信息
    // info stored for each initialized individual tick
    struct Info {
        // 这一刻度的总的头寸流动性,总流动性
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // 从左到右交叉(从右到左)时增加(减去)净流动性的数量，流动性变量
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;
        // token0的外侧累计费用
        // 在这个刻度的外侧（外侧需要看 目标tick在当前tick区间的左侧还是右侧，若在左侧，那外侧就是目标tick的左侧; 若在右侧则外侧就是目标tick的右侧），
        // 每单位流动性的费用增长(相对于当前刻度)只有相对意义，
        // 而不是绝对意义——该值取决于刻度初始化的时间
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // 在刻度的另一侧的累积刻度值
        // the cumulative tick value on the other side of the tick
        int56 tickCumulativeOutside;
        // 在刻度的另一侧(相对于当前刻度)，
        // 每单位流动性的秒数只有相对意义，而不是绝对意义——该值取决于刻度初始化的时间
        // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint160 secondsPerLiquidityOutsideX128;
        // the seconds spent on the other side of the tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint32 secondsOutside;
        // 是否被激活，被用到
        // 如果tick已初始化，即该值完全等价于表达式liquidityGross != 0这8位被设置为防止在穿越新初始化的tick时进行新鲜存储
        // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
        // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
        bool initialized;
    }

    // 根据给定的tickSpacing 获知每刻度的最大流动性
    /// @notice Derives max liquidity per tick from given tick spacing
    // 在Poll池子合约的 构造函数中执行
    /// @dev Executed within the pool constructor
    /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return The max liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        // 最小价格区间,相当于就是 TickMath.MIN_TICK  -887272
        // tickSpacing 在工厂合约里默认有3种，是10/60/200.  这里估计是为了舍去不能被整除的余数
        // 如11/10=1.1, 1.1 因为只能是整数所以只保留了1， 再乘以10，最后的结果就变成了10
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        // 若tickSpacing是10，最大价格区间 887270
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        // 相当于maxTick*2/tickSpacing +1   ==  (887272+887272)/10 +1 == 177,454.4 +1 == 177,455.4
        // uint24最大值是 2**24 -1 == 16,777,216 -1 == 16,777,215
        // 表示有多少个tick
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        // type(uint128).max是 2**128-1 ， 那么也就是  (2**128-1)/177,455.4   ==  1.91756e+33  == 1.91756 * 10**33
        //  uint128 public override liquidity;流动性的值最大是2^127，最大的时候，除以多少个tick，那就表示最多的单个tick里的流动性
        return type(uint128).max / numTicks;
    }

    /// @notice Retrieves fee growth data 检索费用增长数据
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @param tickCurrent The current tick
    /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
    // 每单位流动性的象征性费用在该头寸的刻度范围内的空前增长
    /// @return feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @return feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        // calculate fee growth below
        // 计算低于tickLower部分的手续费
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // calculate fee growth above
        // 计算超出tickUpper部分的手续费
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }
        // 所有价格累计总费用 减去小于lower,大于upper的fee，剩下的就是当前postion里的fee
        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    // 更新ticks里的 当前刻度信息，如果刻度从初始化翻转到未初始化，
    // 则返回true，反之亦然
    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The tick that will be updated 将被更新的刻度
    /// @param tickCurrent The current tick 当前刻度
    // 从左到右(从右到左)穿过tick时要增加(减去)的新流动性量。流动性变量
    /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
    // 每单位流动性的全局费用增长，以token0表示
    /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
    // 池中流动性的总秒数 ；(流动性最小为1)
    /// @param secondsPerLiquidityCumulativeX128 The all-time seconds per max(1, liquidity) of the pool
    // 自池第一次初始化以来所经过的时间
    /// @param tickCumulative The tick * time elapsed since the pool was first initialized
    // 当前块时间戳转换为uint32
    /// @param time The current block timestamp cast to a uint32
    // 更新位置的上刻度为True，更新位置的下刻度为false
    /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
    /// @param maxLiquidity The maximum liquidity allocation for a single tick
    /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta, //流动性变量
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        // 获取当前tick索引下的详细Tick信息
        Tick.Info storage info = self[tick];

        // 当前刻度的流动性
        // 未变化之前的也存一份
        uint128 liquidityGrossBefore = info.liquidityGross;
        // 加上流动性变量后当前tick的流动性，liquidityDelta可能是负值
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        // maxLiquidityPerTick是 in128上限值时的单个tick的流动性
        require(liquidityGrossAfter <= maxLiquidity, 'LO');

        // 若liquidityGrossAfter和liquidityGrossBefore都等于0,则flipped为false
        // 若都不等于0，flipped也为false
        // 若其中一个为0，另一个不为0，也就是到达了边界地带，则flipped为true，tick的激活状态变了
        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        // 如果更新前的流动性是0，那么表示这次是初始化，刚刚激活这个tick
        if (liquidityGrossBefore == 0) {
            // 按照惯例，我们假定在tick初始化之前的所有增长都发生在tick的下面
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                // 若要更新的tick小于当前价格的tick

                // 假设初始化之前，所有的交易都发生在低于tick价格的范围里。 也就是global所有的fee就是外侧费用
                // 这个假设不一定符合真实情况，但是由于在最终的结算中，因为涉及到Lower/upper tick的减法，所以这个假设并不会对最终的结果造成误差
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        // 流动性在info里更新一下
        info.liquidityGross = liquidityGrossAfter;

        // liquidityNet是指经过这个tick时需要变化多少流动性
        // 当下(上)刻度从左到右(从右到左)交叉时，必须添加(删除)流动性
        // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
        info.liquidityNet = upper
            ? // 假设原来是0，那这一次相当于就是-liquidityDelta
            int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice Clears tick data
    // 包含已初始刻度的所有已初始刻度信息的映射
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    // 根据价格变动的需要，过渡到下一个刻度，返回变化的流动性
    /// @notice Transitions to next tick as needed by price movement
    // 包含初始化刻度的所有刻度信息的映射，调用cross方法的变量
    /// @param self The mapping containing all tick information for initialized ticks
    // 转换的目标tick
    /// @param tick The destination tick of the transition
    // 每单位流动性的全局费用增长，以token0表示
    /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
    // 单位流动性的秒数
    /// @param secondsPerLiquidityCumulativeX128 The current seconds per liquidity
    // 自池第一次初始化以来所经过的时间
    /// @param tickCumulative The tick * time elapsed since the pool was first initialized
    /// @param time The current block.timestamp
    // 从左到右(从右到左)穿过tick时增加(减去)的流动性量
    /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time
    ) internal returns (int128 liquidityNet) {
        Tick.Info storage info = self[tick];
        // 全局累计费用 - 外侧费用
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }
}
