// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
/*
tickSpacing 表示刻度，价格的万分之一

*/

// interface指的用了这个接口的合约，必须实现内部定义的合约，并遵从 输入返回参数
// 用来定义部署 流动性池子，该有哪些函数（定义这些函数的出入参）

// Uniswap V3工厂接口,  interface里的所有函数默认virtual可被覆写
/// @title The interface for the Uniswap V3 Factory
// Uniswap V3 Factory方便了Uniswap V3池的创建和协议费用的控制
/// @notice The Uniswap V3 Factory facilitates creation of Uniswap V3 pools and control over the protocol fees
interface IUniswapV3Factory {
    // 更改工厂所有者时触发
    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    // 创建流动池时 发射 记录日志
    /// @notice Emitted when a pool is created
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param pool The address of the created pool
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    // 当通过工厂合约  为流动性池子 创建弃用新的费用金额时触发，  具体场景看这个event用在哪
    /// @notice Emitted when a new fee amount is enabled for pool creation via the factory
    /// @param fee The enabled fee, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks for pools created with the given fee
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice Returns the current owner of the factory  返回当前工厂函数的拥有者
    /// @dev Can be changed by the current owner via setOwner
    /// @return The address of the factory owner
    function owner() external view returns (address);

    // 如果启用，则返回给定费用金额的刻度间距;如果未启用，则返回0
    /// @notice Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled
    // 费用金额永远不能被删除，因此这个值应该硬编码或缓存在调用上下文中
    /// @dev A fee amount can never be removed, so this value should be hard coded or cached in the calling context
    // fee： 启用费用，以百分之一bip为单位。如果未启用费用，则返回0
    /// @param fee The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee
    /// @return The tick spacing 刻度间距
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    // 返回给定token对和费用的 流动性池子合约的地址，如果不存在则返回地址0
    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @return pool The pool address
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    // 为给定的两个币和 指定的费用 创建一个流动性池子合约
    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param fee The desired fee for the pool
    // tokenA和tokenB可以按任意顺序传递:token0/token1或token1/token0。
    //  从费用中检索tickSpacing。如果池已经存在或者费用无效或令牌参数无效，则本次调用出错 回滚。
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved
    /// from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments
    /// are invalid.
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    // 更新工厂合约的所有者
    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner 必须由当前所有者调用
    /// @param _owner The new owner of the factory 新的所有者
    function setOwner(address _owner) external;

    /// @notice Enables a fee amount with the given tickSpacing 启用给定tickSpacing的费用金额
    // 一旦启用，金额可能永远不会被删除
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)
    /// @param tickSpacing The spacing between ticks to be enforced for all pools created with the given fee amount
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}
