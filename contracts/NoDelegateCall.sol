// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

// abstract 定义抽象合约，供其他合约继承使用，继承这个抽象合约的其他合约，
// 必须复写抽象合约里面的方法，否则也将被定义为抽象合约
// 抽象合约不能通过 new 操作符创建，并且不能在编译期生成字节码（bytecode）。


//  防止委托调用到某个合同
/// @title Prevents delegatecall to a contract
// 提供修饰符以防止将调用委托给子契约中的方法的基础合约
/// @notice Base contract that provides a modifier for preventing delegatecall to methods in a child contract
abstract contract NoDelegateCall {
    // immutable 表示这个变量除了在构造函数里可以定义外，其他时候不可变，不能被修改
    /// @dev The original address of this contract 本合同初始地址
    // 当前智能合约的地址（不是第一个msg.sender，不是指管理员）
    // private 表示这个变量只能在当前合约里被调用访问，子合约都不行
    address private immutable original;

    constructor() {
        // 不可变变量在合约的init代码中计算，然后内联到部署的字节码中。
        // Immutables are computed in the init code of the contract, and then inlined into the deployed bytecode.
        // 换句话说，这个变量在运行时 被检查时不会改变。
        // In other words, this variable won't change when it's checked at runtime.
        original = address(this);
    }

    // 使用Private方法而不是内联到修饰符，因为修饰符被复制到每个方法中，
    // 而使用immutable意味着地址字节被复制到使用修饰符的每个地方。
    /// @dev Private method is used instead of inlining into modifier because modifiers are copied into each method,
    ///     and the use of immutable means the address bytes are copied in every place the modifier is used.
    function checkNotDelegateCall() private view {
        // 要求调用方法时候的合约地址，必须是构造函数 部署时候写入的合约地址
        // 这样的话，该方法无法再去使用delegateCall委托调用其他合约了。 委托调用的时候，address(this)是受委托的合约的地址，不是original里储存的地址
        require(address(this) == original);
    }

    // 防止委托调用到修改的方法
    /// @notice Prevents delegatecall into the modified method
    modifier noDelegateCall() {
        // 调用上面的函数
        checkNotDelegateCall();
    }
}
