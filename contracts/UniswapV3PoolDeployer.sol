// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';

import './UniswapV3Pool.sol';

contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    // 规范；参数，  在流动性合约的构造函数时使用
    struct Parameters {
        address factory;//工厂地址
        address token0;
        address token1;
        uint24 fee;//手续费
        int24 tickSpacing;//瞬间间距/间隔
    }

    /// @inheritdoc IUniswapV3PoolDeployer
    Parameters public override parameters;

    //  通过临时设置参数存储槽，然后在部署池后将其清除，使用给定的参数部署池。 
    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    // Uniswap V3工厂的合同地址
    /// @param factory The contract address of the Uniswap V3 factory
    // 按地址排序顺序的池的第一个token
    /// @param token0 The first token of the pool by address sort order
    // 按地址排序顺序的池的第2个token
    /// @param token1 The second token of the pool by address sort order
    // 池中每一次交易所收取的费用，以百分之一bip为单位
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function deploy(
        address factory,//工厂合约地址
        address token0,
        address token1,
        uint24 fee,//手续费
        int24 tickSpacing//间隔
    ) internal returns (address pool) {
        // 新建一个Parameters构造的实例
        parameters = Parameters({factory: factory, 
        token0: token0, 
        token1: token1, 
        fee: fee, 
        tickSpacing: tickSpacing});
        // 创建UniswapV3Pool合约，形成一个流动性池子， 并取该合约的地址
        // new 关键字允许使用模板创建和部署新的合约实例，{}传入的参数是msg里的参数，()里是构造函数入参。 
        // 参考https://mirror.xyz/ninjak.eth/kojopp2CgDK3ehHxXc_2fkZe87uM0O5OmsEU6y83eJs   https://eth.antcave.club/solidity-1
        // salt: keccak256(abi.encode(token0, token1, fee) 指的是把token0,token1,fee拼在一起进行哈希加密，返回的哈希值和salt盐形成一个键值对
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        // 删除已经被用过的实例,因为仅在流动性池子构造函数里用了一下，后续便不再使用
        delete parameters;
    }
}
