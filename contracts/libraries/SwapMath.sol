// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {
    // 这里计算了交易能否在目标价格范围内结束
    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    // 如果掉期' amountSpecified '为正数，那么费用加上进入的金额将永远不会超过剩余的金额
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
    // 不能超过的价格，从中可以推断出交易的方向
    /// @param sqrtRatioTargetX96 The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    // 还有多少输入或输出量需要被交易输入/输出
    /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
    // 从输入金额中收取的费用，以百分之一比特表示
    /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
    // 换入/换出金额后的价格，不超过目标价格
    /// @return sqrtRatioNextX96 The price after swapping the amount in/out, not to exceed the price target
    // 根据交换的方向，token0或token1的要交换的数量
    /// @return amountIn The amount to be swapped in, of either token0 or token1, based on the direction of the swap
    // 根据交换的方向，接收到的token0或token1的数量
    /// @return amountOut The amount to be received, of either token0 or token1, based on the direction of the swap
    // 输入的数量将被作为一种费用
    /// @return feeAmount The amount of input that will be taken as a fee
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96, //当前价格
        uint160 sqrtRatioTargetX96, //目标价
        uint128 liquidity,
        int256 amountRemaining, //tokenIn 的余额
        uint24 feePips
    ) internal pure returns (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        // 如果当前价格大于等于目标价，那说明是从token0兑换成token1，token0的价格降低，也就是token0兑换成token1（池子中token1减少，token0增加）
        // （兑换过程中 数量要增加的币种会变得更泛滥，价格下降，毕竟物以稀为贵，越少越贵，越泛滥越便宜，so token0的价格要下降）
        // 比如token0，token1,原本池子里都有100个， 现在有一个第三方的人，用50个token0要兑换成token1，那么池子里x的数量会上升，变成150个（这时候假设Y变成了50个）
        // ，那么x的价格为  y的数量/x的数量  = 50/150 = 1/3元，x的价格从1变成了1/3
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        // 若tokenIn 的余额 >=0，表示这是指定输入资金求输出资金数量的方式，而不是根据指定输出求输入资金
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
            // 交易之前，
            // 先计算当前价格amountRemaining移动到交易区间边界时所需要的手续费
            // 即此步骤最多需要的手续费数额
            // amountRemaining * (1000000 - feePips) / 1000000, 100w是费率基数,feePips可能为500（万分之5），那么剩余的也就是注入金额的万分之九千九百九十5
            // 先将 tokenIn 的余额扣除掉最大所需的手续费
            // FullMath是为了减少溢出造成精度损失
            uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
            // 算出达到目标价所需要消耗的tokenIn数量
            amountIn = zeroForOne // 如果是token0兑换成token1,那么消耗的是token0的数量
                ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);
            //如果注入的资金比 这次达到目标价消耗的资金量多（也就是达到目标价后还有剩余。）
            // 那么下一次的价格就是这次的目标价；也表示价格能够真的变化到目标价
            if (amountRemainingLessFee >= amountIn)
                sqrtRatioNextX96 = sqrtRatioTargetX96;
                // 否则需要计算出，真实能达到多少的目标价（在上面的目标价 和 此刻的真实价格 之间）
            else
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
        } else {
            // 这里是输入的tokenIn已经用完（想要从池子兑换的消费者注入的资金已经被消耗完）

            // 根据目标价和当前价格， 计算输出的tokenOut的数量
            amountOut = zeroForOne
                ? // 如果是token0换成token1，则计算当前价到目标价token1需要的金额量
                SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);
            // 缺的需输出资金的额度（原来是负值，负负得正）  比 这次需要的输出token的量要大，
            // 那说明目标价能达到，目标价直接赋值给下次循环的价格
            if (uint256(-amountRemaining) >= amountOut)
                sqrtRatioNextX96 = sqrtRatioTargetX96;
                // 在给定token0或token1的输出量的情况下，获取下一个平方根价格
            else
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
        }

        // 目标价就是下次价格的时候，表示这次注入的资金量足够达到目标价，max为true
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

        // get the input/output amounts
        // 获取输入/输出的金额
        if (zeroForOne) {
            // 达到目标价且是指定输入的时候，就是上面计算的amountIn
            amountIn = max && exactIn
                ? amountIn
                // 根据达到sqrtRatioNextX96价格，计算需要多少金额
                : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            //达到目标价，且不是指定输入（指定输出） 
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false);
        } else {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        }

        // cap the output amount to not exceed the remaining output amount
        // 限制output产量不能超过剩余产量
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // we didn't reach the target, so take the remainder of the maximum input as fee
            // 当余额不足以让价格移动到边界，则直接把余额中剩余的资金全部作为手续费
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // 当价格移动到边界时，计算相应的手续费
            // amountIn * feePips / (1e6 - feePips)
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
