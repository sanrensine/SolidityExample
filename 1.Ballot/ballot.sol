// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

/*
 *  投票系统，由合约创建者（主席）发起提案，主席拥有赋予指定选民投票的权利
 *  选民可以指定另一个选民作为自己的代表
 *  部署地址 https://rinkeby.etherscan.io/tx/0x08eb435a2c57bc552168aa109836b925589434b3ca12799f4852be9bae2eb64e
 */
contract Ballot {

    // 此结构代表了一个选民
    struct Voter {
        uint weight; // 累积的投票权重
        bool voted; // true则代表已经投过票
        address delegate; // 记录代表地址
        uint vote; // 确定投票第vote个提案，相当于proposals数组的索引index
    }

    // 此结构代表了一个提案
    struct Proposal {
        bytes32 name; // 提案的名称
        uint voteCount; // 累计的提案支持数量
    }

    address public chairperson; // 发起提案的合约拥有人 - 主席

    mapping(address => Voter) public voters; // 此状态变量，address映射到每个Voter的struct

    Proposal[] public proposals; // 数组的length是动态的，proposals保存了提案

    // constructor是初始化函数，只会在合约创建时调用一次 
    // 通过传入一个proposalNames数组来初始化添
    constructor(bytes32[] memory proposalNames) {
        // 合约创建时，指定chairperson
        chairperson = msg.sender;
        voters[chairperson].weight = 1;

        // 根据传入proposalNames数组
        // 循环创建Proposal提案，并添加到proposals
        for(uint i = 0; i < proposalNames.length; i++) {
            proposals.push(Proposal({
                name: proposalNames[i], // 提案名称
                voteCount: 0 // 初始化支持数是0
            }));
        }
    }

    // 给与指定地址拥有”表决权“
    // 此方法只有‘chairperson’可以调用
    function giveRightToVote(address voter) external {
        // require如果判定为false，则执行终止 && 回滚合约状态
        // 第二个参数则可以记录解释发生了什么问题（测试过 - 字符串不支持中文）
        require(
            msg.sender == chairperson,
            "Only chairperson can give right to vote." // 只有主席可以赋予表决权
        );
        require(
            !voters[voter].voted,
            "The voter already voted." // 选民已经投过票
        );
        require(voters[voter].weight == 0);
        voters[voter].weight = 1;
    }
    
    // 指定to为自己的代表
    function delegate(address to) external {
        // 从“已投票地址”voters数组 - 获取Voter选民  
        Voter storage sender = voters[msg.sender];
        require(!sender.voted, "Your already voted"); // 检查是否已参与过投票

        require(to != msg.sender, "Self-delegation is disallowed.");// 不允许指定自己为代表 

        // 一般来说使用此类循环是很危险的
        // 如果运行的时间过长，可能会需要消耗更多的gas
        // 甚至有可能会导致死循环
        // 此While是向上寻找顶层delegate（代表）
        while(voters[to].delegate != address(0)) { // 地址不为空
            // 此处意思是比如有多级delegate（代表），那么就需要不断向上寻找
            to = voters[to].delegate; 
            // 再向上寻找过程不允许“to”和“请求发起人”msg.sender重合
            require(to != msg.sender, "Found loop in delegation.");
        }

        Voter storage delegate_ = voters[to];

        // 检查是否又投票权
        require(delegate_.weight >= 1);
        // 更改发起人的投票状态和代理
        sender.voted = true;
        sender.delegate = to;
        // 检查代理的投票状态
        // 如果已经投票则直接为提案增加投票数、反之则增加delegate_代表的投票权重
        if(delegate_.voted) {
            proposals[delegate_.vote].voteCount += sender.weight;
        } else {
            delegate_.weight += sender.weight;
        }
    }

    // 为提案投票
    function vote(uint proposal) external {
        // 获取选民
        Voter storage sender = voters[msg.sender];
        // 判断是否有投票权
        require(sender.weight >= 0, "Has no rigth to vote.");
        // 判断是否已经投过票
        require(sender.voted, "Already vote.");

        // 通过校验后，则改变其自身状态
        sender.voted = true;
        sender.vote = proposal;

        // 为指定提案增加支持数量
        // 如果proposal超出数组范围，则会停止执行
        proposals[proposal].voteCount += sender.weight;
    }

    // 统计获胜提案
    function winningProposal() public view
        returns (uint winningProposal_) {
        uint winningVoteCount = 0;
        for(uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
                winningProposal_ = p;
            }
        }
    }

    // 通过winningProposal()方法获取获胜添的index
    // 再通过proposals数组获取提案object的name
    function winnerName() external view 
        returns (bytes32 winnerName_)
    {
        winnerName_ = proposals[winningProposal()].name;
    }
}