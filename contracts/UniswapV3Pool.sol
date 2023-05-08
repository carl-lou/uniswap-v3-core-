// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Pool.sol';

import './NoDelegateCall.sol';

// 优化溢出和下溢 安全的数学操作
import './libraries/LowGasSafeMath.sol';

import './libraries/SafeCast.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/Position.sol';
import './libraries/Oracle.sol';

import './libraries/FullMath.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/SwapMath.sol';

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';

// 上2段视频讲了uniswap的基础介绍，以及工厂合约 + 注入流动性
// 这视频讲普通用户 兑换货币，swap交易的过程
// 觉得我讲得好，记得分享一下。需要注释代码的，加我微信loulan0176即可。 也可以进群交流一下技术。

// 1.外围合约从创建池子 => 做市商注入流动性 铸造NFT头寸 => 更新流动性，更新tick
// 2.普通用户交易，外围合约解析调用路径path，然后调用 pool合约 swap函数，最后算出要兑换的tokenOut金额
// 过程中涵盖 费用，预言机，闪电贷等内容。
// 还有很多基础库，数学库，定点数Q格式，汇编yul等知识点
// 会进行尽可能的代码逐行讲解。

// 学完这个，我觉得可以算是入门defi了，出去也可以吹一下牛逼了。
// 再去看其他类似的交易所的代码，借贷的代码，也会简单很多。



// 基础公式
/*
amountX * amountY = k = L^2
L表示流动性liquidity
P=y/x (p为x的价格，以y计价，每个x需要多少个y)，  y的单价是x单价的倒数1/P
一般地址大的为tokenY

sqrt(P) 就是平方价
可推导出
x=sqrt(k/p)= L/sqrt(P)
y=sqrt(k*P)= L * sqrt(P)

diff表示变化量, 根据这 可以获知交易到指定价格P（不溢出流动性边界）,需要多少x token，可以获得多少y token（L流动性在交易过程中是已知的）
给定多少x token (注入100个USDT),可以获得多少个y token (ETH)，以及最终的x,y价格
diffX= 1/sqrt(diffP) * L
diffY= sqrt(diffP) * L

*/

// 接口的实现粒度比较低，不适合普通用户使用，错误的调用其中的接口可能会造成经济上的损失。
// 另外还有个peirphery 仓库，里面有对这个Pool合约进行再次封装的SwapRouter(用于与前端界面进行交互，对用户调用也更友好）
// ，还有NonfungiblePositionManager用来增删改pool的流动性
contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
    // 防止溢出下溢，并节约gas费， 作用于uint256/int256类型
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    // 安全类型转换
    using SafeCast for uint256;
    using SafeCast for int256;

    // 刻度的数据结构
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    // 头寸库应用于这两个类型
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    // 预言机，最多支持65525个历史价格信息
    // 还可以包含当前未被写入的价格信息，这样就是65536个价格信息
    // 但实际存储的容量并不会这么大，实际容量由 observationCardinality 所决定，看你需要存多长时间的数据
    // 当 Oracle 数据可使用空间被扩容至最大，即 65535 时，假设平均出块时间为 13 秒，那么此时至少可以存储最近 9.8 天的历史数据。
    using Oracle for Oracle.Observation[65535];

    /// @inheritdoc IUniswapV3PoolImmutables
    // immutable构造函数之外不可修改
    address public immutable override factory; //工厂合约地址
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token0; //数值小的token地址
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token1; //数值大的token地址
    /// @inheritdoc IUniswapV3PoolImmutables
    // 这个交易池的费率，如0.05% * 10^6 = 500
    uint24 public immutable override fee; //税费 流动性池子的收费单位是bip的百分之一，即1e-6

    /// @inheritdoc IUniswapV3PoolImmutables
    // 跳过多少个tick
    // Ticks只能用于该值的倍数，最小值为1并且始终为正，
    // 例如:tickSpacing为3意味着tick可以每3个tick初始化一次，
    // 即…， -6， -3, 0,3,6，…该值为int24，以避免强制转换，即使它总是正的。
    int24 public immutable override tickSpacing;

    /// @inheritdoc IUniswapV3PoolImmutables
    // 可以使用范围内 任何刻度的头寸流动性的最大金额
    // 这个参数每tick强制执行一次，以防止流动性在任何时候溢出uint128，
    // 也防止使用范围外的流动性来防止向池中添加范围内的流动性
    uint128 public immutable override maxLiquidityPerTick; //每个价格区间，最大的流动性（流动性资金数量）

    // 储存一些 全局会用到的数据
    struct Slot0 {
        // the current price 当前价格,   token1/token0的值再开根号  就是sqrtPriceX96
        // 直接储存 根号后的值时因为 Solidity 不支持开根号运算， 需要依赖第三方库，浪费gas
        // 另一个问题是价格通常来说都是比较小的数，比如10，5000，0.01等等，我们不希望在求根号时失去太多的精度。
        // 这里的  根号P  是一个 Q64.96 定点数,是一个二进制数字——分别是指64位和96位的二进制位,整数64个位元(2进制),小数位元96个 (因为solidity里不支持小数,所以这里用Q格式来实现)
        // Q64.96的范围也就是  -2^63 到 2^63 - 2^-96
        // Q是数学里表示有理数的字母
        // 更多定点数介绍 参考 https://y1cunhui.github.io/uniswapV3-book-zh-cn/docs/milestone_3/more-on-fixed-point-numbers/
        // https://zh.wikipedia.org/wiki/Q%E6%A0%BC%E5%BC%8F
        uint160 sqrtPriceX96;
        // the current tick 当前刻度，
        // 流动性供应者的设置的价格只能在这些 tick上，
        // 为了避免各种刻度，节省gas（不然储存这些各种各样的刻度就会兄啊好很多储存空间，耗费gas），
        // 甚至会有精度问题，如（1.0000000000001，1.0000000000002）
        // tick采用1.0001等比数列,即 1.0001^-2 , 1.0001^-1(1/1.0001),1，1.0001^1，1.0001*1.0001，1.0001^3，1.0001^4，..., 1.0001^10 ，
        // 也就是LP做市商老板 每个可选价格之间的差值为0.01%，相对还是比较细的，不过实际能激活的tick是tickSpacing的倍数,也就是n是tickSpacing的倍数
        int24 tick;
        // 记录了最近一次 Oracle 记录在 Oracle 数组中的索引位置
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        // 当前已经存储的 Oracle 数量，当前observations数组中的容量值，能存多少条数据（数组的长度），最多65535条
        uint16 observationCardinality;
        // observations即将要扩展到的容量值（数组长度），此值初始时会被设置为 1，后续根据需要来可以扩展
        // 在observation .write中触发的下一个要存储的最大观察数
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // 当前协议费用  提现时交换费用的百分比，表示为整数分母(1/x)%
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol; //协议费用
        // whether the pool is locked 存储池是否被锁定
        bool unlocked;
    }
    /// @inheritdoc IUniswapV3PoolState  看interfaces/pool/IUniswapV3PoolState里的翻译
    Slot0 public override slot0;

    /// @inheritdoc IUniswapV3PoolState
    // 累计的token0手续费总额，使用了 Q128.128 浮点数来记录
    uint256 public override feeGrowthGlobal0X128; //该值可以溢出uint256
    /// @inheritdoc IUniswapV3PoolState
    // 每单位流动性收取的token1费用
    uint256 public override feeGrowthGlobal1X128;

    // accumulated protocol fees in token0/token1 units
    // 以token0/token1单位计算的累计协议费用,协议费用指的是给合约的，不是给LP做市商的
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    /// @inheritdoc IUniswapV3PoolState  协议费用
    // 应给与合约的token0和token1的数量（手续费用）
    ProtocolFees public override protocolFees;

    /// @inheritdoc IUniswapV3PoolState
    // 当前价格上，所有覆盖当前价格的头寸的 流动性之和,
    // liquidity等于x*y=k中K的平方根  ，liquidity*liquidity=常数k=x*y；
    // 存根号K而不是直接存K,是为了方便运算，以及减少溢出的可能性
    uint128 public override liquidity;

    /// @inheritdoc IUniswapV3PoolState
    // 查找池中特定刻度的信息,key是tickIndex 。
    // value是Tick的详细信息，详见IUniswapV3PoolState
    // log(1.0001的平方根) * 当前价格P的平方根(也就是sqrtPriceX96)  （P=y/X=sqrtPriceX96 * sqrtPriceX96)
    mapping(int24 => Tick.Info) public override ticks;
    /// @inheritdoc IUniswapV3PoolState
    // 记录所有被当前价格 引用着的头寸的 tick上下限索引
    mapping(int16 => uint256) public override tickBitmap;
    /// @inheritdoc IUniswapV3PoolState
    // 通过头寸的键返回有关头寸的信息
    mapping(bytes32 => Position.Info) public override positions;
    /// @inheritdoc IUniswapV3PoolState
    //  返回关于特定观察索引的数据
    Oracle.Observation[65535] public override observations;

    // 一个方法在池中的互斥重入保护。该方法还可以防止在池初始化之前进入函数。
    // 在整个合约中都需要重入保护，因为我们使用余额检查来确定交互的支付状态，如mint、swap和flash。
    /// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
    /// to a function before the pool is initialized. The reentrancy guard is required throughout the contract because
    /// we use balance checks to determine the payment status of interactions such as mint, swap and flash.
    modifier lock() {
        // 要求unlocked==true，没被锁住，否则报错“LOK"
        require(slot0.unlocked, 'LOK');
        // 置为false，也就是锁住
        slot0.unlocked = false;
        // 执行用这个modifier的方法的代码
        _;
        // 执行完代码后，重置为true
        slot0.unlocked = true;
    }

    // 阻止从除IUniswapV3Factory#owner()返回的地址以外的任何人调用函数
    /// @dev Prevents calling a function from anyone except the address returned by IUniswapV3Factory#owner()
    modifier onlyFactoryOwner() {
        // IUniswapV3Factory 是一个Interface接口，IUniswapV3Factory()   括号内传入factory合约地址可以返回 已经部署上去的继承了该IUniswapV3Factory接口的合约
        //interface用法参考 https://www.pangzai.win/%E3%80%90solidity%E3%80%91interface%E7%9A%84%E4%BD%BF%E7%94%A8%E6%96%B9%E6%B3%95/
        // 要求调用者必须是工厂合约的所有者
        require(msg.sender == IUniswapV3Factory(factory).owner());
        _;
    }

    constructor() {
        // 初始化刻度之间的最小刻度数
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        // 价格刻度 间距 部署后，不可修改
        tickSpacing = _tickSpacing;

        // 每个刻度最大的流动性
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    // 有效tick输入的 常规检查，Low需小于Upper，小于最大刻度，大于最小刻度
    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        // 要求tickLower 应该小于 tickUpper
        require(tickLower < tickUpper, 'TLU');
        // tickLower 大于最小值 -887272
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        // tickUpper 需要小于最大值 887272
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    // 返回截短为32位的块时间戳，即mod 2**32。此方法在测试中被重写。
    /// @dev Returns the block timestamp truncated to 32 bits, i.e. mod 2**32. This method is overridden in tests.
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired 需要截断
    }

    // 获取池子里token0的余额
    /// @dev Get the pool's balance of token0
    // 此函数经过gas优化，以避免在返回数据大小检查之外，还进行冗余的额外代码数量检查
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance0() private view returns (uint256) {
        // 这staticcall方法允许一个合约调用另一个合约（或它自己）而不修改状态。
        // 参考https://cryptoguide.dev/post/guide-to-solidity's-staticcall-and-how-to-use-it/
        (bool success, bytes memory data) = token0.staticcall(
            // IERC20Minimal接口里的查询余额方法，其实也就是查询当前地址
            // encodeWithSelector是一种通过selector进行加密的方式，同类的还有encodeWithSignature
            // address(this)是balanceOf的入参，查询当前合约地址 在 token0合约中的余额
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
        );
        // 调用需要成功，success需要等于true，返回的数据data字符长度需要大于32个
        require(success && data.length >= 32);
        // 把bytes字节数组 数据结构 转换成 uint256数字
        return abi.decode(data, (uint256));
    }

    // 获取池子里token1的余额
    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) = token1.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    // 预言机查询
    // 返回两个tick之间的 tick累积值，流动性累积值，秒数
    function snapshotCumulativesInside(
        int24 tickLower, //范围的下刻度
        int24 tickUpper
    )
        external
        view
        override
        noDelegateCall
        returns (
            int56 tickCumulativeInside, //范围的刻度累加器的快照
            uint160 secondsPerLiquidityInsideX128, //范围内每个流动性的秒快照
            uint32 secondsInside
        )
    {
        checkTicks(tickLower, tickUpper);
        // 累计刻度最小值
        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            // mapping(int24 => Tick.Info) public override ticks;
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }

        // 上面定义的Slot0 public override slot0;
        Slot0 memory _slot0 = slot0;

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time,
                0,
                _slot0.tick,
                _slot0.observationIndex,
                liquidity,
                _slot0.observationCardinality
            );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 -
                    secondsPerLiquidityOutsideLowerX128 -
                    secondsPerLiquidityOutsideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    // 从当前块时间戳中返回每个时间戳' secondsAgo '的累计tick和流动性
    // 比如我们想要获取最近 1 小时的 TWAP(时间加权平均价格)，和 现在的TWAP，那可传入数组 [3600, 0]，
    function observe(
        // 动态数组，请求N秒之前的数据（以前的tickIndex累积值，流动性累积值）
        // 一次性可以请求多个历史数据
        uint32[] calldata secondsAgos
    )
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );
    }

    /// @inheritdoc IUniswapV3PoolActions
    // 扩容Oracle数组
    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) external override lock noDelegateCall {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // for the event
        uint16 observationCardinalityNextNew = observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    /// @inheritdoc IUniswapV3PoolActions
    // 未锁定，因为它初始化为未锁定
    /// @dev not locked because it initializes unlocked
    // PoolInitializer抽象合约里createAndInitializePoolIfNecessary方法会调用本方法，传入初始的平方根价格
    // 这一步完成之后，才算交易池真的创建好，可以转入流动性资金了
    function initialize(uint160 sqrtPriceX96) external override {
        // slot0里记录的当前价格必须为0，才能初始化
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        // 初始化Oracle
        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        // 新建一个Slot0实例
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner; //头寸的拥有者
        // the lower and upper tick of the position
        int24 tickLower; //刻度下限
        int24 tickUpper;
        // any change in liquidity
        // 变化的流动性额度
        int128 liquidityDelta;
    }

    // 对头寸做一些改变
    /// @dev Effect some changes to a position
    // 头寸详情及头寸流动性的改变所产生的影响
    /// @param params the position details and the change to the position's liquidity to effect
    // 引用具有给定所有者和刻度范围的位置的存储指针
    /// @return position a storage pointer referencing the position with the given owner and tick range
    // token0欠池的金额，如果池应该支付给接收者，则为负数
    /// @return amount0 the amount of token0 owed to the pool, negative if the pool should pay the recipient
    /// @return amount1 the amount of token1 owed to the pool, negative if the pool should pay the recipient
    function _modifyPosition(
        ModifyPositionParams memory params
    ) private noDelegateCall returns (Position.Info storage position, int256 amount0, int256 amount1) {
        // tick刻度的检测，下限需要小于上限，不能溢出tickMath的最大最小Tick
        checkTicks(params.tickLower, params.tickUpper);

        //因为后续要操作slot0， 从storage里存到memory，以节约gas费
        // 修改memory比storage 便宜很多。
        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        // 更新头寸，返回头寸的详情
        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta, //根据这增减流动性
            _slot0.tick
        );

        if (params.liquidityDelta != 0) {
            // 根据流动性+tick上下限 ，逆运算出所需要的token0,token1数量，也是分三种情况

            //当前市场价格的tick 小于 头寸下限tick,那么头寸里所有资金都应该是token0
            if (_slot0.tick < params.tickLower) {
                // 当前刻度低于通过范围;流动性只能通过从左到右交叉进入范围，
                // 当我们需要_more_ token0时(它变得更有价值)，所以用户必须提供它
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // 当前刻度在范围内
                // current tick is inside the passed range
                uint128 liquidityBefore = liquidity; // SLOAD for gas optimization

                // write an oracle entry
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );
                // 根据流动性，两个价格返回 amount0的数量
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96, //当前价格
                    TickMath.getSqrtRatioAtTick(params.tickUpper), //头寸上限
                    params.liquidityDelta
                );
                // 调换一下两个价格顺序
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower), //头寸下限
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );
                // 当前价格的tick如果在头寸范围内，那么需要增加流动性liquidityBefore + params.liquidityDelta
                // liquidity是全局变量，当前价格上 所有头寸的流动性之和
                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // 当前价格在 头寸上限 之上。
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    // 获取并更新具有给定流动性增量的头寸
    /// @dev Gets and updates a position with the given liquidity delta
    /// @param owner the owner of the position 头寸的所有者
    /// @param tickLower the lower tick of the position's tick range 位置刻度范围的下刻度
    /// @param tickUpper the upper tick of the position's tick range 位置刻度范围的上刻度
    /// @param tick the current tick, passed to avoid sloads 当前刻度，通过以避免负载
    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta, //给你用户希望增加或移除的虚拟流动性数量
        int24 tick
    ) private returns (Position.Info storage position) {
        // position.sol中的方法  返回给定所有者和头寸边界的头寸的Info结构
        // 头寸所有者的地址，价格刻度的上下限，这三个数据组合在一起，形成一个头寸的唯一标识
        position = positions.get(owner, tickLower, tickUpper);

        // feeGrowthGlobal0X128是所有刻度里的token0的fee之和
        // 也是storage转成memory，节约gas
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // SLOAD for gas optimization
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // SLOAD for gas optimization

        // if we need to update the ticks, do it
        // 如果我们需要去更新刻度，就这样做，lower的tick是不是
        bool flippedLower;
        bool flippedUpper;

        // 若确实有增减
        if (liquidityDelta != 0) {
            //当前区块时间戳
            uint32 time = _blockTimestamp();
            //这一刻的 价格，流动性记录下来
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time,
                0,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality //oracle数组中已填充元素的数目
            );

            // 要对上下两个边界tick里的详情进行更新

            // 更新ticks里对应的tickLower这个索引里的Tick.Info里的信息，返回激活状态是否变化的boos值
            flippedLower = ticks.update(
                tickLower, //下边界
                tick, //tickCurrent
                liquidityDelta, //流动性变化量
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true, //表示这是上边界
                maxLiquidityPerTick
            );

            // 若tickLower位置激活状态变化了，则 tickBitmap里也需要更新一下，
            if (flippedLower) {
                // wordPos和mask按位异或
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }
        // 计算出此 position 里的 手续费总额；
        // 所有globalFee - （tickLower以下部分 + tickUpper以上部分）
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(
            tickLower,
            tickUpper,
            tick,
            _feeGrowthGlobal0X128, //所有刻度上的fee
            _feeGrowthGlobal1X128
        );

        // 更新头寸详情里的 流动性liquidityGross，liquidityNet，费用
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // clear any tick data that is no longer needed
        // 若这次的流动性是 减少的
        if (liquidityDelta < 0) {
            if (flippedLower) {
                // 并且流动性激活状态变化了，说明从有流动性变成了没有流动性
                // 那么要清空以下tick里的数据，减少激活的tick数量，降低未来计算复杂度
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    // 为给定的接收者/tickLower/tickUpper头寸增加流动性
    /// @inheritdoc IUniswapV3PoolActions
    // 无委托调用的限制 通过_modifyPosition函数间接调用了
    /// @dev noDelegateCall is applied indirectly via _modifyPosition
    function mint(
        address recipient, //流动性拥有者，nonfungiblePositionManager 合约地址
        int24 tickLower, //价格下限刻度的索引
        int24 tickUpper,
        uint128 amount, // 流动性 常数K的平方根，liquidity
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        // 根据流动性，头寸上下限tick,  算出需要多少token0和token1
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(amount).toInt128()
            })
        );
        // 从int256类型转换成无符号的uint256类型
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        // 之前的余额，balance0()表示 token0的ERC20合约里，当前池子地址的余额是多少
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        // 头寸供应商给pool地址 转token0 and token1代币
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        // balance0Before + 刚刚增加的amount0 ，需要小于 本合约里当前token0的实际余额  （一般是相等）
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    // 头寸拥有者（LP做市商） 提取应得的手续费
    /// @inheritdoc IUniswapV3PoolActions
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested, //想提取的token0数量
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        // 我们在这里不需要checkTicks，因为无效的位置永远不会有非零的标记。
        // we don't need to checkTicks here, because invalid positions will never have non-zero tokensOwed{0,1}
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            // position头寸里减少数量
            position.tokensOwed0 -= amount0;
            //d调用token0(ERC20)合约的transfer方法，将本池子的token0余额 转移amount0数量 给recipient地址
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    // 从发送方和账户代币中消耗流动性
    /// @inheritdoc IUniswapV3PoolActions
    /// @dev noDelegateCall is applied indirectly via _modifyPosition
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount //想要销毁的流动性额度
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 更新头寸
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int256(amount).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            // 增加应给头寸所有者响应的费用
            // 这里不是直接提取，提取还是通过collect函数
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    struct SwapCache {
        // 转入token的协议费用
        // the protocol fee for the input token
        uint8 feeProtocol;
        // 互换开始时的流动性
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // 当前块的时间戳
        // the timestamp of the current block
        uint32 blockTimestamp;
        // 刻度累加器的当前值，仅在经过初始化的刻度时计算
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // 每个流动性累加器的当前秒值，仅在经过初始化的刻度时计算
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // 是否计算并缓存了上面两个累加器
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
    }

    // 交换的顶层状态，交换的结果在最后被记录在存储中
    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // 在输入/输出资产中要交换的剩余金额
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // 已交换出/输入的输出/输入资产的数量
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // 当前价格的平方根
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // 与当前价格相关的刻度
        // the tick associated with the current price
        int24 tick;
        // 输入令牌的全球费用增长
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // 作为协议费支付的输入令牌数量
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        // 当前流动性在一定范围内
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    // 交易token0和token1
    /// @inheritdoc IUniswapV3PoolActions
    function swap(
        address recipient, //接收者
        bool zeroForOne, //是不是16进制地址数值小的token地址 转给大的token
        int256 amountSpecified, //想要交换的量,指定输出金额的时候，这里传入的是负值
        uint160 sqrtPriceLimitX96, //Q64.96格式的根号限价。如果token0换成token1，则交换后的价格不能小于此值。 如果1换成0,swap后的price不能大于此值
        bytes calldata data //带有path和payer
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        // 交易的金额不能为0
        require(amountSpecified != 0, 'AS');
        // 拷贝成 内存临时变量, 以后直接从内存里读取，后续的访问通过  汇编`MLOAD` 完成，节省 gas
        Slot0 memory slot0Start = slot0;

        // 池子 不能处于锁定状态
        require(slot0Start.unlocked, 'LOK');
        require(
            zeroForOne // token0兑换成token1时，传入的sqrtPriceLimitX96限价 需要小于sqrtPriceX96，并且大于MIN_SQRT_RATIO 4295128739
            // 如USDT兑换ETH，ETH的市场价为2000，限制的价格肯定是要小于2000的，并且限价大于tick最小值
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );
        // 锁定池子
        slot0.unlocked = false;

        // 交易缓存建立，储存在内存里.这里面的变量后面会经常需要读取/修改，so 储存在memory里
        SwapCache memory cache = SwapCache({
            liquidityStart: liquidity, //刚开始时的流动性
            blockTimestamp: _blockTimestamp(), //当前区块的时间戳
            //feeProtocol是协议要收取的手续费。 0换成1时，费用为feeProtocol/16的余数。
            //  token1换成0时，slot0Start.feeProtocol位右移4位，相当于除以2^4(除以16后的整数)
            // 这是设置协议手续费的时候，就是把两个协议费用，这样子的方式存入slot0的，见setFeeProtocol方法
            feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
            //  每个流动性累加器的当前秒值，仅在经过初始化的刻度时累加，刚开始时为0
            secondsPerLiquidityCumulativeX128: 0,
            // 刻度累加器的当前值，仅在经过初始化的刻度时计算
            tickCumulative: 0,
            //  是否计算并缓存了上面两个累加器
            computedLatestObservation: false
        });

        // 若是指定输出多少金额的情况，则amountSpecified<0，exactInput是负值
        bool exactInput = amountSpecified > 0;

        // 创建一个交易状态数据结构，这些值在交易的步骤中可能会发生变化
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified, //在输入/输出资产中要交换的剩余金额,刚开始就是输入的其中之一token的金额
            amountCalculated: 0, //已交换的 输出/输入 的资产的数量
            sqrtPriceX96: slot0Start.sqrtPriceX96, // 当前价格的平方根
            tick: slot0Start.tick, // 与当前价格相关的刻度,当前的刻度
            // 每单位流动性收取的token0/token1费用， token0换成token1，那么收的是0的费率
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0, //本合约要收的费率
            liquidity: cache.liquidityStart //流动性
        });

        // 只要我们没有用完整个输入/输出（想要兑换的量没用完），并且没有达到价格限制，就继续交换
        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        // 当发生交易时，此交易会拆分成多个，通过池中多个不同的流动性来进行交易，最后将交易结果聚合，完成最终的交易过程。
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            // 交易过程每一次循环的状态变量
            StepComputations memory step;

            // 交易的起始价格
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // 通过tick位图找到下一个可以选的交易价格tickNext，（下一个激活的tick，或者word边界tick)
            // 这个刻度 可能还在流动性范围内，也可能不在了
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne //token0兑换token1的话，就是向左移动，价格下降
            );

            // 确保我们没有超过tick最小/最大刻度，因为刻度位图不知道这些界限
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                // 若超越边界，则边界即为下一个tick
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            // 获知下一刻度的 平方根价格
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            // 计算当价格到达下一个交易价格时，tokenIn 是否被耗尽（tokenIn的amountRemain会减少），
            // 如果被耗尽，则这次将是最后一次循环，还需要重新计算出 tokenIn 耗尽时的价格
            // 返回这一次单步交易 需要消耗多少amountIn，输出多少amountOut，多少费用,到达的价格sqrtPriceX96是多少
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining, //想要兑换的量，输入的tokenIn的金额
                fee
            );

            // 更新 tokenIn 的余额，以及 tokenOut 数量，
            // 注意当指定 tokenIn 的数量进行交易时，这里的 tokenOut 是负数
            if (exactInput) {
                // 更新注入资金的余额，上次余额-（这单步交易消耗的amountIn，和费用）
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                // 输出token的累减，这里是负数的形式
                // 这里的amountCalculated是输出
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                // 如果是指定输出多少金额
                // 
                // 那注入资金加上 输出amountOut（负值）
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                // 累加值amountCalculated则是 输入金额amountIn了。
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // 如果协议费用是打开的，计算欠多少，减少feeAmount，增加protocolFee
            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // 更新全局费用跟踪器
            // update global fee tracker
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);

            // 如果我们达到下一个价格，就移位刻度(更新流动性 L 的值)
            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // 下一个刻度刻度是否已激活初始化
                // if the tick is initialized, run the tick transition
                // 检查tick index 是否为另一个流动性的边界
                if (step.initialized) {
                    // check for the placeholder value, which we replace with the actual value the first time the swap
                    // crosses an initialized tick
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    // 更新tick里的feeGrowthOutside0X128
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        cache.blockTimestamp
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    // 如果我们向左移动，我们将liquidityNet解释为相反的安全符号，因为liquidityNet不能是类型(int128).min
                    //  根据价格增加/减少，即向左或向右移动，增加/减少相应的流动性
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    // 更新流动性
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                // 这里更新tick，使得下一次循环的时候，让 tickBitmap 进入下一个 word 中查询
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // 重新计算，除非我们在一个较低的刻度边界(即已经过渡的刻度)，并且没有移动
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        } //循环结束

        // update tick and write an oracle entry if the tick change
        if (state.tick != slot0Start.tick) {
            // 如果tick发生变化，则写入oracle条目
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                // 交易前的最新 Oracle 索引
                slot0Start.observationIndex,
                // 当前区块时间
                cache.blockTimestamp,
                // 交易前的价格的tick，这样做是为了防止攻击
                slot0Start.tick,
                // 交易前的价格对应的流动性
                cache.liquidityStart,
                // 当前的Oracle数量
                slot0Start.observationCardinality,
                // 可用的Oracle数量
                slot0Start.observationCardinalityNext
            );
            // 更新当前平方价，tick， 最新Oracle指向的索引信息 以及当前Oracle数据的总数目
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            // otherwise just update the price
            // 如果tick没发生变化，那么只需要更新价格
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        // 如果流动性发生了变化，更新流动性
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        // 交易完成后，更新全局费用。如果有必要，协议费用溢出是可以接受的，
        // 协议必须在它达到类型uint128最大值之前提取费用
        // update fee growth global and, if necessary, protocol fees
        // overflow is acceptable, protocol has to withdraw before it hits type(uint128).max fees
        if (zeroForOne) {
            // token0换成token1，
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        // 确定最终用户支付的 token 数和得到的 token 数
        (amount0, amount1) = zeroForOne == exactInput // 如果指定交易的金额大于0，且是注入token0兑换token1
            ? // 那么要转账的amount0就是 注入金额-剩余金额； token1是循环中 累加的
            (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : // 如果是token1兑换token0(zeroForOne为false)，amountSpecified大于0(exactInput为true)
            // 或者token0兑换token1(zeroForOne为true),但是amountSpecified小于等于0(exactInput为false)
            // 那么累计值则反而是 amount0了
            (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // do the transfers and collect payment
        if (zeroForOne) {
            // 如果是token0兑换成token1,
            // 这里先给 recipient地址转账token1合约里的代币
            // 前面说过 tokenOut 记录的是负数，这里要取反一下
            // 由于是先给打款的，所以可以搞闪电贷
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));

            // 获取token0之前的余额，用于后续判断
            uint256 balance0Before = balance0();
            // 调用 IUniswapV3SwapCallback这个协议的uniswapV3SwapCallback方法。
            // msg.sender一般为外围合约，见v3-periphery仓库
            // 在这里面，要给Pool池子转账tokenIn，里面也可以做其他的操作（闪电贷）
            // 外围合约可以自己写，而不是用Uniswap提供的v3-periphery
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            // 最后校验，经过上面一步其他地方给pool地址的资金转入后的最新余额，要大于等于 (原本的余额balance0Before + 应该注入的amount0)
            require(balance0Before.add(uint256(amount0)) <= balance0(), 'IIA');
        } else {
            // token1兑换token0，先转token0给调用者
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), 'IIA');
        }

        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true;
    }

    /// @inheritdoc IUniswapV3PoolActions
    // 普通闪电贷
    function flash(
        address recipient, //借贷方地址，用于调用回调函数
        uint256 amount0, //借贷的token0的数量
        uint256 amount1, //借贷的token1的数量
        bytes calldata data //回调函数的参数
    ) external override lock noDelegateCall {
        uint128 _liquidity = liquidity; //当前池子里的流动性
        require(_liquidity > 0, 'L');

        // 借贷所需要扣除的手续费
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        // 记录下当前的余额
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        // 将要借的 token 发送给借贷方
        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        // 调用借贷方地址的回调函数，将函数用户传入的 data 参数传给这个回调函数
        // 参考periphery外围合约里的PairFlash.sol
        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        // 转账和调用了合约后的余额
        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        // sub is safe because we know balanceAfter is gt balanceBefore by at least fee
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) protocolFees.token0 += uint128(fees0);
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) protocolFees.token1 += uint128(fees1);
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    // 设置协议的手续费
    /// @inheritdoc IUniswapV3PoolOwnerActions
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
                (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    // 收取应计协议费
    /// @inheritdoc IUniswapV3PoolOwnerActions
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFees.token0) amount0--; // ensure that the slot is not cleared, for gas savings
            protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFees.token1) amount1--; // ensure that the slot is not cleared, for gas savings
            protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}

// 参考文章
// https://www.jianshu.com/p/c2adfb478b7f
// https://y1cunhui.github.io/uniswapV3-book-zh-cn/docs/milestone_3/more-on-fixed-point-numbers/

// 空的时候，会不断优化，加我微信loulan0176，
// 进群 更新代码，群里问问题，交流有趣的事情
