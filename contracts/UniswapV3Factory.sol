/*
uniswap 是什么？
What Is Uniswap?
协议（智能合约），界面（web前端界面），实验室（公司）
Protocol, Interface, Labs

首先，我们应该明确“Uniswap”不同领域之间的区别，其中一些可能会让新用户感到困惑。
To begin, we should make clear the distinctions between the different areas of "Uniswap", 
some of which may confuse new users.

uniswap 实验室：开发Uniswap协议和web界面的公司。
Uniswap Labs: The company which developed the Uniswap protocol, along with the web interface.

Uniswap协议： 一套持久的、不可升级的智能合约，共同创建了一个自动化的做市商，
这是一种在以太坊区块链上促进点对点做市和交换ERC-20token的协议。
The Uniswap Protocol: A suite of persistent, non-upgradable smart contracts 
that together create an automated market maker, a protocol that facilitates 
peer-to-peer market making and swapping of ERC-20 tokens on the Ethereum blockchain.

Uniswap接口:一个允许与Uniswap协议进行简单交互的web界面。接口只是与Uniswap协议交互的多种方式之一。
The Uniswap Interface: A web interface that allows for easy interaction with the 
Uniswap protocol. The interface is only one of many ways one may interact with 
the Uniswap protocol.

Uniswap治理:一个治理Uniswap协议的治理系统，由UNI token来决议。（token作为股权 投票权）
Uniswap Governance: A governance system for governing the Uniswap Protocol, enabled by the UNI token.
*/


// 想要这些笔记+注释过的代码， 加我**微信loulan0176**进群获取

// 觉得我讲得还行，也可以关注我  

// 微信公众号/抖音/bilibili 

// **逐星web3** 区块恋

// 会不断发表市场上比较稀缺的一些 项目案例分析，代码分析。



// 代码是23年的，和以前的代码会不同；  国内也有其他解析uniswap的，不过最新的几乎没有，逐行讲解的，我也还没找到过。

// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

// 规范标准的 Uniswap V3工厂，  用于部署一系列流动性池子的合约（合约部署合约）
/// @title Canonical Uniswap V3 factory
// 部署Uniswap V3流动性池子，管理池协议费用的所有权和控制
/// @notice Deploys Uniswap V3 pools and manages ownership and 
// control over pool protocol fees
contract UniswapV3Factory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    // override 表示重写了IUniswapV3Factory父合约的 function owner() 
    // public 可以重写 external， 因为返回都是address，都没有入参。
    address public override owner;//等同于function owner() public returns(address)

    /// @inheritdoc IUniswapV3Factory
    // tickSpacing 每段间隔的交易费金额
    mapping(uint24 => int24) public override feeAmountTickSpacing;

    /// @inheritdoc IUniswapV3Factory
    // 覆写 IUniswapV3Factory父合约的 function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool) 
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        // 部署合约的人 成为拥有者
        owner = msg.sender;
        // 改变owner所有人 的日志，从0地址改为部署者的地址
        emit OwnerChanged(address(0), msg.sender);
        
        // 以 1000000 为基数，即5%为500
        // 初始化写死三种费率，以及费率对应的刻度间隔，
        //  每个实际用到的tick之间 跳过几个 不用的tick
        // 用于三种情况 稳定币对稳定币， 稳定币对波动大的币， 波动大的币对波动大的币
        feeAmountTickSpacing[500] = 10;//稳定币对稳定币，万分之5,    稳定币波动小，需要比较密集的价格刻度，刻度间隔为10,10个tick作为一个实际的间距
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;//稳定币对波动大的币，千分之3
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;//波动大的币对波动大的币，万分之一。 价格刻度间隔 是稳定币的20倍
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    // 创建一个流动性池子，这个池子由tokenA和tokenB组成，并设定交易手续费
    function createPool(
        address tokenA,//WETH  ERC20
        address tokenB,//USDC
        uint24 fee//500，或者3000，10000 ，也可以其他
    ) external override noDelegateCall returns (address pool) {
        // 两个token的地址不能一样
        require(tokenA != tokenB);
        // 小的地址在前面，也就是无论传入的参数调换，这里token0都是地址数值小一些的那个
        // （地址是16位的，可以进行大小比较，详见https://juejin.cn/post/7135329160171847694）
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 不能是0地址
        require(token0 != address(0));
        // 刻度间隔 是10，或者60，200,  每个实际用到的tick之间 跳过几个 不用的tick
        int24 tickSpacing = feeAmountTickSpacing[fee];
        // 也就是fee不能是500，3000，10000之外的数字，因为构造函数里只存了这三个数，
        // 若传入的fee是另外的数字，则feeAmountTickSpacing[fee]会是0
        require(tickSpacing != 0);
        // 要求没有存入过流动性池子Pool地址
        require(getPool[token0][token1][fee] == address(0));

        // UniswapV3PoolDeployer合约里的函数
        // 部署一个流动性池子合约
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        // 把部署后的流动性池子地址，写入到getPool里
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        //调换token1，token0顺序, 在相反的方向填充映射,故意选择避免比较地址的成本
        getPool[token1][token0][fee] = pool;
        // 流动性池子创建好了 的日志记录
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    function setOwner(address _owner) external override {
        // 调用者必须是 原来的owner所有者
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        // 变更储存器里的地址 交接大权
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    // 开启交易手续费，可以增加手续费种类
    // 也就是同一组代币交易对，会有多种费率，这样会更灵活，但是也会导致流动性分散
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        // 必须是合约所有者
        require(msg.sender == owner);
        // 传入的fee需要小于100万
        require(fee < 1000000);
        // tickSpacing刻度间隔 上限为16384，以防止tickSpacing太大，
        // TickBitmap下一个初始化tick Within One Word从有效tick溢出int24容器的情况。
        // 16384 tick表示>5倍价格变化，tick为1 bips
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        // 要求原来的fee必须是0，也就是不能修改原来已经有的费率标准
        require(feeAmountTickSpacing[fee] == 0);

        // 在构造函数初始化的手续费 对应的tickSpacing之外，增加
        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
