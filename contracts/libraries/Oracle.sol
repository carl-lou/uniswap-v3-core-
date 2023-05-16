// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

// 链上预言机，可以用来在链下寻找最优交易对价格源（流动性最大的池子）； 也可以获知最近一段时间的加权几何平均价格（用来绘制小时线，日线等）
// Oracle 数据的更新发生在价格变动的时候
// 对历史价格的记录，还有对应的流动性（可以选流动性大的池子作为价格参考来源。 交易量最大的一个交易所，那个交易所就相当于拥有这个代币的定价权）

/// @title Oracle
// 为各种系统设计提供有用的价格和流动性数据
/// @notice Provides price and liquidity data useful for a wide variety of system designs
// 存储的oracle数据的实例，“观察”，收集在oracle数组中
/// @dev Instances of stored oracle data, "observations", are collected in the oracle array
// 每个池初始化的oracle数组长度为1。
// 任何人都可以通过支付SSTOREs来增加oracle数组的最大长度。
// 当数组被完全填充时，将添加新的插槽。
/// Every pool is initialized with an oracle array length of 1. Anyone can pay the SSTOREs to increase the
/// maximum length of the oracle array. New slots will be added when the array is fully populated.
/// Observations are overwritten when the full length of the oracle array is populated.
// 通过将0传递给observe()，可以获得最近的观测值，与oracle数组的长度无关。
/// The most recent observation is available, independent of the length of the oracle array, by passing 0 to observe()
library Oracle {
    // 观察
    struct Observation {
        // 观察到的区块时间戳
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // tick index 的时间加权累积值
        // 刻度 累加器，即tickIndex * 自池第一次初始化以来所经过的时间
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        // last.tickCumulative + int56(tick) * 时间差。

        // price(tick) = 1.0001^tick,当 tick 为 0 时，价格为 1；当 tick 为 1 时，价格为 1.0001；
        // 当 tick 为 2 时，价格为 1.0001^2。也即是说，相邻价格点之间的价差为 0.01%。
        // 当然，tick 也可以为负值，为负值时表明价格 p 小于 1。
        // 可以通过TIckMath库里的getSqrtRatioAtTick方法，根据tick获知平方价
        int56 tickCumulative;
        // 价格所在区间的流动性的时间加权累积值
        // 每个流动性的秒数，即自池第一次初始化以来的秒数/最大(1，流动性)
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // 观察值是否初始化
        // whether or not the observation is initialized
        bool initialized;
    }

    /// @notice Transforms a previous observation into a new observation, given the passage of time and the current tick and liquidity values
    /// @dev blockTimestamp _must_ be chronologically equal to or greater than last.blockTimestamp, safe for 0 or 1 overflows
    /// @param last The specified observation to be transformed
    /// @param blockTimestamp The timestamp of the new observation
    /// @param tick The active tick at the time of the new observation
    /// @param liquidity The total in-range liquidity at the time of the new observation
    /// @return Observation The newly populated observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        // 上次Oracle数据和本次的时间差
        uint32 delta = blockTimestamp - last.blockTimestamp;
        return
            Observation({
                blockTimestamp: blockTimestamp,
                // 计算tick INdex的时间加权累积值
                tickCumulative: last.tickCumulative + int56(tick) * delta,
                // 时间差/流动性， 每份流动性的秒数
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                initialized: true
            });
    }

    // 通过写入第一个槽来初始化oracle数组。对于观测数组的生命周期调用一次
    /// @notice Initialize the oracle array by writing the first slot. Called once for the lifecycle of the observations array
    /// @param self The stored oracle array
    /// @param time The time of the oracle initialization, via block.timestamp truncated to uint32
    // oracle数组中已填充元素的数目
    /// @return cardinality The number of populated elements in the oracle array
    // oracle数组的新长度，与population无关
    /// @return cardinalityNext The new length of the oracle array, independent of population
    function initialize(
        Observation[65535] storage self,
        uint32 time //缩短成32位的区块时间戳
    ) internal returns (uint16 cardinality, uint16 cardinalityNext) {
        // 创建第一个元素
        self[0] = Observation({
            blockTimestamp: time, //区块时间戳
            tickCumulative: 0, //初始累计值为0
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        // （当前Oracle数组中的个数，最大可用个数）
        return (1, 1);
    }

    /// @notice Writes an oracle observation to the array
    /// @dev Writable at most once per block. Index represents the most recently written element. cardinality and index must be tracked externally.
    /// If the index is at the end of the allowable array length (according to cardinality), and the next cardinality
    /// is greater than the current one, cardinality may be increased. This restriction is created to preserve ordering.
    /// @param self The stored oracle array
    // 最近写入观测值数组的观测值的索引
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param blockTimestamp The timestamp of the new observation
    /// @param tick The active tick at the time of the new observation
    /// @param liquidity The total in-range liquidity at the time of the new observation
    // oracle数组中已填充元素的数目
    /// @param cardinality The number of populated elements in the oracle array
    // oracle数组的新长度，与population无关
    /// @param cardinalityNext The new length of the oracle array, independent of population
    // oracle数组中最近写入的元素的新索引
    /// @return indexUpdated The new index of the most recently written element in the oracle array
    // oracle数组的新基数
    /// @return cardinalityUpdated The new cardinality of the oracle array
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        // 获取当前的Oracle数据
        Observation memory last = self[index];

        // early return if we've already written an observation this block
        // 同一个区块内，只会在第一笔交易中写入 Oracle 数据
        // 若是同一个区块，则直接返回输入的索引 和 Oracle数组数量
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // if the conditions are right, we can bump the cardinality
        // 检查是否需要使用新的数组空间
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        // 算出新的索引，使用余数方式实现
        // 若依旧是初始化时候的（1，1）， 那么这里的index是0，cardinalityUpdated是1，1&1==0，
        // 下一个indexUpdated还是0
        indexUpdated = (index + 1) % cardinalityUpdated;
        // 写入Oracle数据
        self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
    }

    /// @notice Prepares the oracle array to store up to `next` observations
    /// @param self The stored oracle array
    /// @param current The current next cardinality of the oracle array
    /// @param next The proposed next cardinality which will be populated in the oracle array
    /// @return next The next cardinality which will be populated in the oracle array
    function grow(Observation[65535] storage self, uint16 current, uint16 next) internal returns (uint16) {
        require(current > 0, 'I');
        // no-op if the passed next value isn't greater than the current next value
        if (next <= current) return current;
        // store in each slot to prevent fresh SSTOREs in swaps
        // this data will not be used because the initialized boolean is still false
        // 对数组中将来可能会用到的槽位进行写入，以初始化其空间，避免在 swap 中初始化，而初始化的过程消耗的gas是昂贵的
        // 这样在代币交易写入新的 Oracle 数据时，不需要再进行初始化，可以让交易时更新 Oracle 不至于花费太多的 gas，
        // SSTORE 指令由 20000 降至 5000。可以参考：EIP-1087, EIP-2200, EIP-2929，具体实现：core/vm/gas_table.go。
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice comparator for 32-bit timestamps
    /// @dev safe for 0 or 1 overflows, a and b _must_ be chronologically before or equal to time
    /// @param time A timestamp truncated to 32 bits
    /// @param a A comparison timestamp from which to determine the relative position of `time`
    /// @param b From which to determine the relative position of `time`
    /// @return bool Whether `a` is chronologically <= `b`
    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        // if there hasn't been overflow, no need to adjust
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a target, i.e. where [beforeOrAt, atOrAfter] is satisfied.
    /// The result may be the same observation, or adjacent observations.
    /// @dev The answer must be contained in the array, used when the target is located within the stored observation
    /// boundaries: older than the most recent observation and younger, or the same age as, the oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation recorded before, or at, the target
    /// @return atOrAfter The observation recorded at, or after, the target
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized tick, keep searching higher (more recently)
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // check if we've found the answer!
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    // 找出的时间点前后，最近的两个 Oracle 数据。
    /// @notice Fetches the observations beforeOrAt and atOrAfter a given target, i.e. where [beforeOrAt, atOrAfter] is satisfied
    /// @dev Assumes there is at least 1 initialized observation.
    /// Used by observeSingle() to compute the counterfactual accumulator values as of a given block timestamp.
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param tick The active tick at the time of the returned or simulated observation
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The total pool liquidity at the time of the call
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation which occurred at, or before, the given timestamp
    /// @return atOrAfter The observation which occurred at, or after, the given timestamp
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // optimistically set before to the newest observation
        beforeOrAt = self[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity));
            }
        }

        // now, set before to the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // ensure that the target is chronologically at or after the oldest observation
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // if we've reached this point, we have to binary search
        return binarySearch(self, time, target, index, cardinality);
    }

    // 如果在所要的观察时间戳中或之前的观察不存在，则返回。0可以作为' secondsAgo'传递，以返回当前的累积值。
    // 如果调用的时间戳位于两个观察值之间，则返回恰好位于两个观察值之间的时间戳的反事实累加器值。
    /// @dev Reverts if an observation at or before the desired observation timestamp does not exist.
    /// 0 may be passed as `secondsAgo' to return the current cumulative values.
    /// If called with a timestamp falling between two observations, returns the counterfactual accumulator values
    /// at exactly the timestamp between the two observations.
    /// @param self The stored oracle array
    /// @param time The current block timestamp
    // 回头看的时间，以秒为单位，在这一点上返回观察结果
    /// @param secondsAgo The amount of time to look back, in seconds, at which point to return an observation
    /// @param tick The current tick
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return tickCumulative The tick * time elapsed since the pool was first initialized, as of `secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128 The time elapsed / max(1, liquidity) since the pool was first initialized, as of `secondsAgo`
    function observeSingle(
        Observation[65535] storage self,
        uint32 time, //当前区块时间戳
        uint32 secondsAgo,
        int24 tick, //slot0.tick,
        uint16 index, //slot0.observationIndex,
        uint128 liquidity,
        uint16 cardinality //slot0.observationCardinality oracle数组中已填充元素的数目
    ) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        // secondsAgo 为 0 表示当前的最新 Oracle 数据
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            // 如果Oracle数据里最新的一条数据里记录的时间戳  和当前传入的时间戳不一样，那么重新创建一份Oracle数据
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        // 计算出 请求的时间戳， 当前的时间戳 - x秒
        uint32 target = time - secondsAgo;

        // 计算出请求时间戳最近的两个 Oracle 数据
        (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(
            self,
            time,
            target,
            tick,
            index,
            liquidity,
            cardinality
        );

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            // 如果请求时间和返回的左侧时间戳吻合，那么可以直接使用
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            // 在右边界
            // 也可以直接使用
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // we're in the middle
            // 当请请求的时间在中间时，计算根据增长率计算出请求的时间点的 Oracle 值并返回
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / observationTimeDelta) *
                    targetDelta,
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    // 返回' secondsAgos '数组中给定时间秒前的每个时间的累加器值
    /// @notice Returns the accumulator values as of each time seconds ago from the given time in the array of `secondsAgos`
    /// @dev Reverts if `secondsAgos` > oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param secondsAgos Each amount of time to look back, in seconds, at which point to return an observation
    /// @param tick The current tick
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return tickCumulatives The tick * time elapsed since the pool was first initialized, as of each `secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128s The cumulative seconds / max(1, liquidity) since the pool was first initialized, as of each `secondsAgo`
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        require(cardinality > 0, 'I');
        // 创建和输入参数 秒数数组一样长度的  数组用于返回
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                liquidity,
                cardinality
            );
        }
    }
}



// 参考文章：https://cloud.tencent.com/developer/article/2017547