// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Permissionless pool actions
/// @notice Contains pool methods that can be called by anyone
interface IUniswapV3PoolActions {
    /// @notice Sets the initial price for the pool
    /// @dev Price is represented as a sqrt(amountToken1/amountToken0) Q64.96 value
    /// @param sqrtPriceX96 the initial sqrt price of the pool as a Q64.96
    function initialize(uint160 sqrtPriceX96) external;

    // 为给定的 接收者/上刻度/下刻度 头寸增加流动性
    /// @notice Adds liquidity for the given recipient/tickLower/tickUpper position
    // 该方法的调用者接收到一个形式为IUniswapV3MintCallback的回调，
    // 其中他们必须为流动性支付任何token0或token1。token0/token1的到期金额取决于tickLower、tickUpper、流动性金额和当前价格。
    /// @dev The caller of this method receives a callback in the form of IUniswapV3MintCallback#uniswapV3MintCallback
    /// in which they must pay any token0 or token1 owed for the liquidity. The amount of token0/token1 due depends
    /// on tickLower, tickUpper, the amount of liquidity, and the current price.
    // 将为其创建流动性的地址
    /// @param recipient The address for which the liquidity will be created
    // 增加流动性的位置的较低刻度
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    // 铸造的流动性的数量
    /// @param amount The amount of liquidity to mint
    /// @param data Any data that should be passed through to the callback
    // 为制造给定数量的流动性而支付的token0的数量。匹配回调中的值
    /// @return amount0 The amount of token0 that was paid to mint the given amount of liquidity. Matches the value in the callback
    /// @return amount1 The amount of token1 that was paid to mint the given amount of liquidity. Matches the value in the callback
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Collects tokens owed to a position  收集应给予头寸的代币
    // 不重新计算赚取的费用，这必须通过mint或燃烧任何数量的流动性。Collect必须由位置所有者调用。要只提取token0或token1, 
    // amount0Requested或amount1Requested可以设置为零。为了收回所有所欠的令牌，调用者可以传递任何大于实际所欠令牌的值，
    // 例如type(uint128).max。所欠代币可能来自累积的掉期费用或消耗的流动性。
    /// @dev Does not recompute fees earned, which must be done either via mint or burn of any amount of liquidity.
    /// Collect must be called by the position owner. To withdraw only token0 or only token1, amount0Requested or
    /// amount1Requested may be set to zero. To withdraw all tokens owed, caller may pass any value greater than the
    /// actual tokens owed, e.g. type(uint128).max. Tokens owed may be from accumulated swap fees or burned liquidity.
    /// @param recipient The address which should receive the fees collected 收取费用的地址
    /// @param tickLower The lower tick of the position for which to collect fees 要收取费用的位置的下刻度
    /// @param tickUpper The upper tick of the position for which to collect fees
    /// @param amount0Requested How much token0 should be withdrawn from the fees owed 应从费用中提取多少token0
    /// @param amount1Requested How much token1 should be withdrawn from the fees owed
    /// @return amount0 The amount of fees collected in token0 在token0中收取的费用金额
    /// @return amount1 The amount of fees collected in token1
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    // 从发送方和账户代币中消耗流动性
    /// @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
    // 可以通过调用0 ?来触发一个头寸所欠费用的重新计算
    /// @dev Can be used to trigger a recalculation of fees owed to a position by calling with an amount of 0
    // 费用必须通过盗用#collect 单独收取
    /// @dev Fees must be collected separately via a call to #collect
    /// @param tickLower The lower tick of the position for which to burn liquidity
    /// @param tickUpper The upper tick of the position for which to burn liquidity
    /// @param amount How much liquidity to burn
    /// @return amount0 The amount of token0 sent to the recipient
    /// @return amount1 The amount of token1 sent to the recipient
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    // 将token0替换为token1，或将token1替换为token0
    /// @notice Swap token0 for token1, or token1 for token0
    // 此方法的调用者接收一个形式为IUniswapV3SwapCallback#uniswapV3SwapCallback的回调
    /// @dev The caller of this method receives a callback in the form of IUniswapV3SwapCallback#uniswapV3SwapCallback
    /// @param recipient The address to receive the output of the swap 接收交换输出的地址
    // 交换的方向，token0到token1为真，token1到token0为假
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    // 交换量，它隐式地将交换配置为精确输入(正)或精确输出(负)
    /// @param amountSpecified The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    // Q64.96根号限价。如果token0换成token1，则交换后的价格不能小于此值。 如果1换成0,swap后的price不能大于此值
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback 要传递给回调的任何数据
    // 池中token0的余额的delta，当为负时是正确的，当为正时最小
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    // 接收token0和/或token1，并在回调中偿还它，外加一笔费用
    /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
    // 此方法的调用者接收一个形式为IUniswapV3FlashCallback#uniswapV3FlashCallback的回调
    /// @dev The caller of this method receives a callback in the form of IUniswapV3FlashCallback#uniswapV3FlashCallback
    /// @dev Can be used to donate underlying tokens pro-rata to currently in-range liquidity providers by calling
    /// with 0 amount{0,1} and sending the donation amount(s) from the callback
    /// @param recipient The address which will receive the token0 and token1 amounts
    /// @param amount0 The amount of token0 to send
    /// @param amount1 The amount of token1 to send
    /// @param data Any data to be passed through to the callback
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice Increase the maximum number of price and liquidity observations that this pool will store
    /// @dev This method is no-op if the pool already has an observationCardinalityNext greater than or equal to
    /// the input observationCardinalityNext.
    /// @param observationCardinalityNext The desired minimum number of observations for the pool to store
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}
