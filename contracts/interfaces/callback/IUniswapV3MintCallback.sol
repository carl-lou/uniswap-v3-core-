// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Callback for IUniswapV3PoolActions#mint
// 任何调用IUniswapV3PoolActions#mint的契约都必须实现这个接口
/// @notice Any contract that calls IUniswapV3PoolActions#mint must implement this interface
interface IUniswapV3MintCallback {
    // 在铸造流动性到池子里后 调用调用者
    /// @notice Called to `msg.sender` after minting liquidity to a position from IUniswapV3Pool#mint.
    // 在实现中，您必须为铸造的流动性支付所欠的池代币。此方法的调用者必须检查为由规范的UniswapV3Factory部署的UniswapV3Pool。
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.

    /// @param amount0Owed The amount of token0 due to the pool for the minted liquidity 由于生成的流动性池而产生的token0的数量
    /// @param amount1Owed The amount of token1 due to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#mint call
    function uniswapV3MintCallback(
        uint256 amount0Owed,//由于生成的流动性池而产生的token0的数量
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
