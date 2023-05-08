// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

// 打包标记初始化状态库
/// @title Packed tick initialized state library
// 存储标记索引到其初始化状态的打包映射
/// @notice Stores a packed mapping of tick index to its initialized state
// 映射使用int16作为键，因为tick表示为int24，每个单词有256(2^8)个值。
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickBitmap {
    // 计算tick的初始化位在映射中的头寸
    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position 要为其计算头寸的刻度,tick索引
    // 映射中的键，其中包含存储位的word
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    // 在word中存储标志的位头寸
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        // tick / 2^8 = tick / 256,商为wordPos,余数为bitPos
        // 1个word是由256个tick*tickSpacing组成。
        // 这里是找到这个tick位于哪个word，第几个word
        wordPos = int16(tick >> 8);
        // word里的第几位
        bitPos = uint8(tick % 256);
    }

    // 将给定刻度的初始化状态从false翻转为true，反之亦然
    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        // 确保tick已经经过tickSpacing舍去余数化了。(Tick / tickSpacing) * tickSpacing;
        require(tick % tickSpacing == 0); // ensure that the tick is spaced
        // 获取wordPos,bitPos
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        // 相当于2^bitPos
        uint256 mask = 1 << bitPos;
        // tickBitmap里的wordPos与mask按位异或
        self[wordPos] ^= mask;
    }

    // 返回与给定刻度的左(小于或等于)或右(大于)刻度包含在同一word(或相邻word)中的下一个初始化的刻度
    // 就是寻找当前word区间内有没有记录其他激活了的tickIndex，有则找出来，没有则采用这个word的边界；
    // 用word的方式来限制每一步交易的跨度不要太大，减少计算中溢出的可能性
    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick 开始的tick索引
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(
        //表示用了这个方法的变量（这个library会赋予给某些变量，一般为 tickBitmap）
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        //下一个tick是不是在左边,tick是否向左移动，价格降低
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        // tick压缩一下，用于计算处于第几个word
        int24 compressed = tick / tickSpacing;
        // 如果tick是负值，并且不能整除tickSpacing，那么 压缩的tick需要 -1
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

        if (lte) {
            // 向左移动，那么就是tick变小,要看的是左边的word区域
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // all the 1s at or to the right of the current bitPos
            // 所有的1s在或前往当前bitPos的右边
            // 若bitPos为1，那么1<<bitPos为0000...00010,转换成十进制为2，mask为2-1+2=3，为00...00011
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            // self[wordPos] ^= mask = 1 << bitPos;
            // 那么self[wordPos]为000010，and 0000011的结果为 0000010
            uint256 masked = self[wordPos] & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            // 如果当前刻度 右侧或当前刻度处没有已初始化的刻度，则返回word中的最右侧tick
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            // 上溢/下溢是有可能的，但可以通过限制tickSpacing和tick 来从外部阻止
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                // 去掉余数bitPos，返回左侧那个word的最右侧tick（当前word最左侧tick)
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            // 从下一个刻度的word开始，因为当前刻度状态无关紧要
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // all the 1s at or to the left of the bitPos
            // 若bitPos==1,那么1<<bitPos 为2进制00...00010，也就是2,2-1=1，换算成2进制就是0001，~取反就是111...1110
            uint256 mask = ~((1 << bitPos) - 1);
            // self[wordPos] ^= mask = 1 << bitPos;
            // 原本position(compressed)的bitPos很可能是0，那么self[wordPos]=000...00001
            // 000...00001 & 111...1110 == 0
            uint256 masked = self[wordPos] & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            // 如果当前刻度左侧侧或当前刻度处没有已初始化的刻度，则返回word中的最左侧tick
            // 若不等于0，则表示这个word里左侧还有初始化过的tick
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                // 补齐余数即达到word最右侧，并+1,当前word的最右侧(右侧word的最左侧tick)
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }
}
