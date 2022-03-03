// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

/*
SimpleAuction合约的功能类似于价高者得的竞标系统，
每个人都可以在规定时间内支付竞投，如果竞投价钱比最高价低，则可以提现退回
最终在竞投结束后，把钱转给发起者（合约是不会自己发起的，最后结束时，需要主动发起并确定获胜者，结束合约）
部署地址 https://rinkeby.etherscan.io/tx/0x5c221acb6545560d77db5ae4c17f7c9ede02f1810115bed3ee2863e72e7bef11
 */
contract SimpleAuction {
    // 受益人，在这个合约受益人是发起者
    address payable public beneficiary;

    // 时间是unix的绝对时间戳（自1970-01-01开始以来的秒数）
    // 竞投结束时间
    uint public auctionEndTime;

    // 最高出价的address
    address public highestBidder;
    // 最高出价
    uint public highestBid;

    // 地址映射金额 - 记录还末退钱的address
    mapping(address => uint) pendingReturns;

    // 标记竞投是否已经结束，初始化为false
    bool ended;

    // Event事件，通过emit发出通知
    // 告知调用合约的竞投者：发起竞投成功，当前为最高价
    event HighestBidIncreased(address bidder, uint amount);
    // 告知调用合约的竞投者：竞投已经结束，竞投成功的地址是winner，最高价是amount
    event AuctionEnded(address winner, uint amount);
    
    // Error事件 - 合约执行终止，并传递错误数据给调用者
    // 必须跟revert一起使用，revert让合约回滚到调用时的初始状态 - 具体参考https://docs.soliditylang.org/en/latest/contracts.html#errors

    // 下面的注释使用了三个斜杆，是solidity语法的NatSpec格式（eg: /// ）
    // 使用NatSpec格式可以利用注释去生成用户说明文档、开发说明文档 - 具体参考https://docs.soliditylang.org/en/latest/natspec-format.html

    /// 竞投已结束
    error AuctionAlreadyEnded();
    /// 发起的投标金额比当前最高价低,并返回当前最高价
    error BidNoHighEnough(uint highestBid);
    /// 竞投末结束，获取不了竞投获胜者
    error AurtionNotYetEnded();
    /// 竞投已结束
    error AuctionEndAlreadyCalled();

    /// 合约发布时初始化函数、只在发布时调用一次
    /// '设置beneficiaryAddress'设置收益人地址、
    /// 'biddingTime'以秒为单位，设置竞投时间
    constructor (
        uint biddingTime,
        address payable beneficiaryAddress
    ) {
        beneficiary = beneficiaryAddress;
        auctionEndTime = block.timestamp + biddingTime; // 根据区块时间 + 竞投持续时间
    }

    /// 参加竞投交易时，竞投者会把value一起发送过来（此处value可以理解成钱，比如是以太坊的代币ETH）
    /// 只有当竞投失败时，才可把value退回
    function bid() external payable {
        // 此处参数不是必须的，因为函数需要用到的所有的信息都已经包含在交易中
        // 如果函数需要接收以太币ETH，需要加上关键字'payable'

        // 如果是超过竞投时间，则停止执行并回滚状态
        if(block.timestamp > auctionEndTime) {
            revert AuctionAlreadyEnded();
        }
        // 如果竞投价低于当前最高价，则停止执行并回滚状态
        // revert会还原此次调用合约的所有状态更改（包括已收到的资金）- 智能合约要么全部执行成功、要么执行失败还原初始状态 只有这两种情况
        if(msg.value <= highestBid) {
            revert BidNoHighEnough(highestBid);
        }

        // 下面判断是当已经有人参与过竞投
        if (highestBid != 0) {
            //来到这一步，逻辑则表示这次调用竞投的value是最高价，那么就把上一个出价最高的address记录在pendingReturns，以便之后退钱
            pendingReturns[highestBidder] += highestBid;

            // 此处有个问题，为什么需要在pendingReturns记录退钱地址个金额，能不能直接在这一步使用highestBidder.send(highestBid)直接退钱了事呢？
            // highestBidder.send(highestBid) - 意思是向highestBidder地址发送highestBid金额
            // 答案是不行的，因为这样做会有安全风险，它有可能会执行一个不信任的合约 具体解释 - https://ethereum.stackexchange.com/questions/10976/questions-about-simpleauction-contract-example/10980
            // 更安全的方法，是让可以退钱的用户自己发起‘提现’
        }

        // 记录当前最高价的地址和金额
        highestBid = msg.value;
        highestBidder = msg.sender;
        // 告知调用者 - 参与竞投成功，目前出价最高
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    /// 竞投失败的调用者，可以提现取回
    function withdraw() external returns (bool) {
        // 根据调用者地址msg.sender获取记录在pendingReturns的退款金额
        uint amount = pendingReturns[msg.sender];
        
        if (amount > 0) {
            // 先将调用者退款金额amount设置为0，这一步很重要
            // 想象一下，如果把这一步放在下面的转账成功之后，当send()退钱在没执行完，调用者再次发起‘提现’，则会重复进入此判断，又再次发起提现
            // 所以需要先执行
            pendingReturns[msg.sender] = 0;
            
            // msg.send 类型不是‘address payable’,所以先显示转换,才能使用send()函数
            if (!payable(msg.sender).send(amount)) {
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    /// 竞标结束，并将最高的竞价金额，发送给受益人
    function auctionEnd() external {
        // 对于可以和其他合约交互的函数（如调用第三方函数或发送以太币）
        // 建议遵从一下三点的指引
        // 1.检查条件
        // 2.执行条件（可能会条件）
        // 3.再与其他合约交互
        // 如果以上步骤混淆，其他合约可能会重新调用当前合约，并且多次修改状态、或导致某些效果（如支付以太坊）多次生效
        // 如果调用内部函数包含外部合约交互，则应该当作是与外部函数交易的

        // 1.检查条件，判断当前是否再在竞标期内
        if (block.timestamp < auctionEndTime) {
            revert AurtionNotYetEnded();
        }

        // 2.修改状态
        ended = true;
        emit AuctionEnded(highestBidder,highestBid);

        // 3.转账
        // transfer()如果执行失败会throw()抛出异常，由外部接收、并且状态回滚
        beneficiary.transfer(highestBid);
    }
}