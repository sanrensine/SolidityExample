// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

/*
此合约是一个类似”网购“的功能，通常我们使用的网购存在一个可信任的第三方中介，当买家收货确认后，卖家才收到钱
但是此合约由于没有第三方中介，所以使用了押金的方式，当双方都有押金在合约中锁定，可有意愿去解决出现的末知问题
由卖家发起网购合约，设定商品的价钱value，然后双方都支付两倍value的价钱作为押金，并锁定。
完成交易收到货后，卖家可以退回3倍value（押金+货款），买家可以退回1倍value（押金）
部署地址 https://rinkeby.etherscan.io/tx/0x641a0f38bf11b377cd7fe926a4ed508769e7d643bf1cb9a4f4268f1757e66558
 */

contract Purchase {

    uint public value; // 约定的商品价钱
    uint public value2; // 约定的商品价钱
    address payable public seller; // 卖家地址
    address payable public buyer; // 买家地址

    enum State { Created, Locked, Release, Inactive } // 订单状态枚举
    State public state; // 当前订单状态

    // 条件判断修饰符
    modifier condition(bool condition_) {
        require(condition_);
        _;
    }

    /// 只有买家可以调用此函数
    error OnlyBuyer();
    /// 只有卖家可以调用此函数
    error OnlySeller(); 
    /// 当前订单状态不允许调用此函数
    error InvalidState();
    /// 传入的参数必须是偶数
    error ValueNotEven();

    // modifier修饰符：判断是否买家在调用函数
    modifier onlyBuyer() {
        if (msg.sender != buyer) {
            revert OnlyBuyer(); // 不是则回滚状态、向外报错
        }
        _;
    }

    // modifier修饰符：判断是否买家在调用函数
    modifier onlySeller() {
        if(msg.sender != seller) {
            revert OnlySeller(); // 不是则回滚状态、向外报错
        }
        _;
    }

    // modifier修饰符：判断是否在`state`状态
    modifier inState(State state_) {
        if (state != state_) {
            revert InvalidState(); // 不是则回滚状态、向外报错
        }
        _;
    }

    event Aborted(); // 交易结束
    event PurchaseConfirmed(); // 交易确定
    event ItemReceived(); // 已收到货
    event SellerRefunded(); // 卖家退款
    
    /// 需要确定`msg.value`是一个偶数
    /// 因为solidity在除法计数中，小数会直接截断（如 99 / 2 = 49.5 会截断为49）
    /// 使用乘法 * 2去判断传入的value是否偶数
    constructor() payable {
        seller = payable(msg.sender);
        value = msg.value / 2;
        if ((2 * value) != msg.value) {
            revert ValueNotEven();
        }
    }

    /// 中止交易，并取回以太币。
    /// 只能在合同开始前，由卖方调用
    function abort() 
        external
        onlySeller
        inState(State.Created)
    {
        emit Aborted();
        state = State.Inactive;// 更改合约状态为Inactive

        // 我们直接在这里使用转账。它是重入安全的，
        // 因为我们是最后一行调用transfer的，并且已经在之前修改了State状态。
        seller.transfer(address(this).balance);
    }

    /// 以买家身份确定交易
    /// 交易必须包含`2 * value`的以太币（value是constructor方法卖家确定的）
    /// 这些以太币会锁定直到交易完成（confirmReceived函数被调用）
    function confirmPurchase() 
        external
        inState(State.Created)
        condition(msg.value == (2 * value))
        payable
    {
        emit PurchaseConfirmed(); // 告知交易确认
        buyer = payable(msg.sender); // 记录买家
        state = State.Locked; // 更改合约状态为Locked
    }

    /// 确认收货，这将会解锁以太币
    function confirmReceived() 
        external
        onlyBuyer
        inState(State.Locked)
    {
        emit ItemReceived(); // 告知已收货
        // 首先更改状态是很重要的，否则再次调用此函数，会再次发起transfer转账
        state = State.Release;
        // 留下货款，取回押金
        buyer.transfer(value);
    }

    /// 此函数给卖家退回押金和货款
    function refundSeller() 
        external
        onlySeller
        inState(State.Release)
    {
        emit SellerRefunded();
        // 首先更改状态是很重要的，否则再次调用此函数，会再次发起transfer转账
        state = State.Inactive;
        // 取回押金和货款
        seller.transfer(3 * value);
    }
}