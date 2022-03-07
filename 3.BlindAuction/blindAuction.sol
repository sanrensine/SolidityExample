// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

/**
BlindAuction合约是基于上一份SampleAuction的扩展，在公开竞标的基础，增加隐藏竞标价格的功能
由于合约是公开透明的，并且每个人每次发送竞标‘金额’都可以通过区块链直接查看value金额，那怎么做到可以隐藏大家的‘竞标价’？
隐藏竞标价，则代表隐藏了调用合约竞标时发送的value，那么怎么确保他们赢得拍卖之后付款？
解决此问题使用了“加密付款金额”和“订金”的模式
调用者发起竞拍时，先把自己的实际竞投“金额”使用hash加密，用blindedBid参数记录，然后实际发送到合约的eth则作为“订金”
在竞投结束时，用户则发送解密的valueString、和密钥，如果blindedBid = hash('valueString','密钥')则代表valueString是真实的‘竞拍价‘
最后，如果赢得拍卖，可退回金额 = 订金 - 竞拍价，竞拍失败的用户，则全款可退回
部署地址 https://rinkeby.etherscan.io/tx/0x9c023537bb1038ba2f7e639ec4184010c9e32067ca4734d2e33bf5c063d3fff9
 */
contract BlindAuction {

    // 用户的竞标结构体
    struct Bid {
        bytes32 blindedBid; // 加密后的竞标价
        uint deposit; // 订金
    }

    address payable public beneficiary; // 受益人
    uint public biddingEnd; // 拍卖结束时间
    uint public revealEnd; // 拍卖结束后，公开实际竞标金额的时间
    bool public ended; // 拍卖时候结束

    mapping(address => Bid[]) public bids; // 通过用户address映射他的出价，出价用数组表示，可以出价多次

    address public highestBidder; // 最高出价人的address
    uint public highestBid; // 最高出价

    mapping(address => uint) pendingReturns; // 通过用户address映射他的可退金额

    event AuctionEnded(address winner, uint amount); // 通知外部，整场竞拍活动结束

    // 通过下列Error返回，告知调用者执行出错
    /// 函数末开放调用，请在`time`之后在尝试
    error TooEarly(uint time);
    /// 函数不允许在`time`之后调用
    error TooLate(uint time);
    /// 拍卖已结束
    error AuctionEndAlreadyCalled();

    // Modify修饰符是验证函数输入的便捷方法
    // 可以理解为先验证Modify里面的条件，通过之后，再执行旧函数的代码块，’_‘就代表旧函数的代码块

    // 检查block.timestamp当前时间是否在`time`之前
    modifier onlyBefore(uint time) {
        if (block.timestamp >= time) revert TooLate(time);
        _;
    }
    // 检查block.timestamp当前时间是否在`time`之后
    modifier onlyAfter(uint time) {
        if (block.timestamp <= time) revert TooEarly(time);
        _;
    }

    // 
    constructor (
        uint biddingTime, // 拍卖持续时间（秒为单位）
        uint revealTime, // 拍卖结束后，有多小时间可以解谜自己的实际竞投金额（秒为单位）
        address payable beneficiaryAddress // 结束后，受益人地址
    ) {
        beneficiary = beneficiaryAddress;
        biddingEnd = block.timestamp + biddingTime;
        revealEnd = biddingEnd + revealTime;
    }

    /// 竞拍时使用加密后的盲价，`blindedBid` = keccak256(abi.encodePacked(value, fake, secret)).
    /// 只有在拍卖公开大家竞标价的reveal阶段，正确的输入以上加密的值(包括value, fake, secret)，解谜成功，才能发起’提现‘退款
    /// 由于每个竞拍者都可以发起多次竞拍，只有当fake是true的时候，才会当作有效出价
    /// fake作用是给调用者多次出价，从而可以隐藏自己的真实出价
    function bid(bytes32 blindedBid) 
        external
        payable
        onlyBefore(biddingEnd) // Modify修饰符
    {
        bids[msg.sender].push(Bid({
            blindedBid: blindedBid, // 加密后的实际竞投金额
            deposit: msg.value // 实际收到的ETH则当做订金
        }));
    }

    /// 公开你的真实竞拍价，对于所有正确验证，但无效的出价，都会获得退款
    function revael(
        uint[] calldata values, // 多次出价的实际value数组
        bool[] calldata fakes, // 多次出价的fake数组，fake表示那次出价有效
        bytes32[] calldata secrets // 解谜密钥数组
    )  
        external
        onlyAfter(biddingEnd) // Modify修饰符 biddingEnd时间之后
        onlyBefore(revealEnd) // Modify修饰符 revealEnd时间之前
    {
        // length是用户出价次数
        uint length = bids[msg.sender].length;
        // 校验数组和出价次数是否匹配
        require(values.length == length);
        require(fakes.length == length);
        require(secrets.length == length);

        // 可退回金额
        uint refund;
        
        // 遍历，校验拍卖阶段加密过的出价，和解密后的值是否匹配，匹配则出价有效
        // 并且计算可退回金额refund
        for (uint i =0; i < length; i++) {
            // 获取用户在bids数组的历史竞价bid对象出来
            Bid storage bidToCheck = bids[msg.sender][i]; 
            // 获取对应index的值
            (uint value, bool fake, bytes32 secret) = (values[i], fakes[i], secrets[i]);
            
            // 校验加密的blindedBid和用户提供的元素加密后是否匹配
            if (bidToCheck.blindedBid != keccak256(abi.encodePacked(value, fake, secret))) {
                 // 如果不正确则无法退回订金，进行下一轮校验
                 continue;
            }

            // 来到这里 - 代表校验通过
            // 记录退款额度为当初预缴的订金
            refund += bidToCheck.deposit;
            // 判断预缴订金，是否比value出价高，并且fake为true，则代表真实出价
            if (!fake && bidToCheck.deposit > value) {
                // 判断是否最高出价
                if (placeBid(msg.sender, value)) {
                    // 则订金 - 投标价
                    refund -= value;
                }
            }
            // 把盲拍金额数据清0，防止重复提款
            bidToCheck.blindedBid = bytes32(0);
        }
        // 退回无效出价
        payable(msg.sender).transfer(refund);
    }

    /// 曾经成为最高价的竞拍者，但是最后落选，可以通过此函数取出竞拍金额
    function withdraw() external {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            
            // 先将可回退金额设置为0，防止在send()过程中，用户重复提款，又进入到此提款判断
            // 记住应该遵从 1.条件判断 -> 2.修改状态 3.与合约交互or转钱
            pendingReturns[msg.sender] = 0;

            payable(msg.sender).transfer(amount);
        }
    }

    /// 结束整个竞拍活动，并向受益人转账
    function auctionEnd() 
        external
        onlyAfter(revealEnd) 
    {
        // 判断整个竞拍活动是否已结束
        if (ended) revert AuctionEndAlreadyCalled();
        // 告知获胜竞拍人address和amount
        emit AuctionEnded(highestBidder, highestBid);
        // 修改状态
        ended = true;
        // 向受益人转账
        beneficiary.transfer(highestBid);
    }

    // ’internal’关键字
    // 意思是，这个函数属于内部可以访问的函数，即只能本合约（或继承的合约）调用
    // 此函数是对比当前最高价，并记录
    function placeBid(address bidder, uint value) internal returns (bool success){
        
        // 对比最高价
        if (value < highestBid) {
            return false;
        }
        // 之前知否有最高出价人
        if (highestBidder != address(0)) {
            // 有则把之前最高出价人的address和amount记录在pendingReturns，到时“提现“时使用
            pendingReturns[highestBidder] += highestBid;
        }
        // 记录最高价和最高出价人address
        highestBidder = bidder;
        highestBid = value;
        return true;
    }
}