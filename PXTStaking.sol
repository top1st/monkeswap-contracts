pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PXTStaking is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public pxt;
    IERC20 public matic;
    address public lpAdmin;
    address public feeAddress;
    uint public withdrawFee; // PXT
    uint public totalFee;
    uint public totalDeposit; // PXT
    mapping(uint => uint) public totalReward; // MATIC, LP, LP ...

    bool enabled = true;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
        uint reward;
    }

    struct PoolInfo {
        IERC20 rewardToken;
        uint deposit;
        uint accTokenPerShare;
        uint minHoldRequest;
    }

    PoolInfo[] public poolInfo;
    mapping(uint => mapping(address => UserInfo)) public userInfo;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(IERC20 _pxt, IERC20 _matic, address _lpAdmin) {
        pxt = _pxt;
        matic = _matic;
        lpAdmin = _lpAdmin;
        poolInfo.push(PoolInfo({
        rewardToken : _matic,
        deposit : 0,
        accTokenPerShare : 0,
        minHoldRequest : 0
        }));
    }

    function setLpAdmin(address admin) external onlyOwner {
        lpAdmin = admin;
    }

    function setEnabled(bool action) external onlyOwner {
        enabled = action;
    }

    function setFeeAddress(address feeAddr) external onlyOwner {
        feeAddress = feeAddr;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function addPool(IERC20 rewardToken, uint minHoldRequest, bool update) external onlyOwner {
        if (update) {
            massUpdatePools();
        }
        poolInfo.push(PoolInfo({
        rewardToken : rewardToken,
        deposit : 0,
        accTokenPerShare : 0,
        minHoldRequest : minHoldRequest
        }));
    }

    function setPoolInfo(uint pid, uint minHoldRequest) external onlyOwner {
        require(pid > 0, "pid should gt 0");
        poolInfo[pid].minHoldRequest = minHoldRequest;
    }

    function setReplaceReward(uint pid, IERC20 rewardToken) external onlyOwner {
        require(pid > 0, "pid should gt 0");
        poolInfo[pid].rewardToken = rewardToken;
    }

    function setWithdrawFee(uint fee) external onlyOwner {
        withdrawFee = fee;
    }

    function poolLength() public view returns (uint) {return poolInfo.length;}

    function updatePool(uint pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if(pool.deposit == 0) {
            return;
        }
        uint adminBalance = pool.rewardToken.balanceOf(lpAdmin);
        if (adminBalance > 0) {
            pool.rewardToken.safeTransferFrom(lpAdmin, address(this), adminBalance);
            pool.accTokenPerShare = pool.accTokenPerShare + (adminBalance * 1e12 / pool.deposit);
        }
    }

    function sendToken(IERC20 token, address wallet) external onlyOwner {
        require(enabled == false, "pool is active");
        token.safeTransfer(wallet, token.balanceOf(address(this)));
    }

    function withdraw(uint pid, uint value) external {
        require(pid > 0, "pid Should be gt 0");
        require(value > withdrawFee, "Less Than Fee");
        require(enabled == true, "pool disabled");
        UserInfo storage user = userInfo[pid][msg.sender];
        UserInfo storage user0 = userInfo[0][msg.sender];
        uint pending;
        updatePool(pid);
        updatePool(0);

        require(poolInfo[pid].rewardToken.balanceOf(msg.sender) >= poolInfo[pid].minHoldRequest, "LP hold required" );

        pending = poolInfo[pid].accTokenPerShare * user.amount / 1e12 - user.rewardDebt;
        if (pending > 0) {
            poolInfo[pid].rewardToken.safeTransfer(msg.sender, pending);
            user.reward += pending;
            totalReward[pid] += pending;
        }

        pending = poolInfo[0].accTokenPerShare * user0.amount / 1e12 - user0.rewardDebt;
        if (pending > 0) {
            poolInfo[0].rewardToken.safeTransfer(msg.sender, pending);
            user0.reward += pending;
            totalReward[0] += pending;
        }

        pxt.safeTransferFrom(lpAdmin, msg.sender, value - withdrawFee);
        if(withdrawFee > 0) {
            if(feeAddress != address (0)) {
                pxt.safeTransferFrom(lpAdmin, feeAddress, withdrawFee);
            }
            totalFee += withdrawFee;
        }
        user.amount -= value;
        poolInfo[pid].deposit -= value;

        user0.amount -= value;
        poolInfo[0].deposit -= value;
        totalDeposit -= value;

        user.rewardDebt = poolInfo[pid].accTokenPerShare * user.amount / 1e12;
        user0.rewardDebt = poolInfo[0].accTokenPerShare * user0.amount / 1e12;
        emit Withdraw(msg.sender, pid, value);
    }

    function deposit(uint pid, uint value) external {
        require(pid > 0, "pid Should be gt 0");
        require(enabled == true, "pool disabled");
        UserInfo storage user = userInfo[pid][msg.sender];
        UserInfo storage user0 = userInfo[0][msg.sender];
        uint pending;
        updatePool(pid);
        updatePool(0);

        require(poolInfo[pid].rewardToken.balanceOf(msg.sender) >= poolInfo[pid].minHoldRequest, "LP hold required");

        pending = poolInfo[pid].accTokenPerShare * user.amount / 1e12 - user.rewardDebt;
        if (pending > 0) {
            poolInfo[pid].rewardToken.safeTransfer(msg.sender, pending);
            user.reward += pending;
            totalReward[pid] += pending;
        }

        pending = poolInfo[0].accTokenPerShare * user0.amount / 1e12 - user0.rewardDebt;
        if (pending > 0) {
            poolInfo[0].rewardToken.safeTransfer(msg.sender, pending);
            user0.reward += pending;
            totalReward[0] += pending;
        }

        if (value > 0) {
            pxt.safeTransferFrom(msg.sender, lpAdmin, value);
            user.amount += value;
            poolInfo[pid].deposit += value;

            user0.amount += value;
            poolInfo[0].deposit += value;
            totalDeposit += value;
        }

        user.rewardDebt = user.amount * poolInfo[pid].accTokenPerShare / 1e12;
        user0.rewardDebt = user0.amount * poolInfo[0].accTokenPerShare / 1e12;
        emit Deposit(msg.sender, pid, value);

    }

    function emergencyWithdraw(uint256 pid) public {
        require(pid > 0, "pid should be gt 0");
        UserInfo storage user = userInfo[pid][msg.sender];
        UserInfo storage user0 = userInfo[0][msg.sender];
        pxt.safeTransferFrom(lpAdmin, msg.sender, user.amount - withdrawFee);
        if(withdrawFee > 0) {
            if(feeAddress != address (0)) {
                pxt.safeTransferFrom(lpAdmin, feeAddress, withdrawFee);
            }
            totalFee += withdrawFee;
        }

        emit EmergencyWithdraw(msg.sender, pid, user.amount);

        user0.amount -= user.amount;
        poolInfo[0].deposit -= user.amount;
        user0.rewardDebt = user0.amount * poolInfo[0].accTokenPerShare / 1e12;

        poolInfo[pid].deposit -= user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function pendingReward(uint pid, address account) external view returns (uint) {
        UserInfo storage user = userInfo[pid][account];
        PoolInfo storage pool = poolInfo[pid];
        if(pool.deposit == 0) {
            return 0;
        }
        uint lpBalance = pool.rewardToken.balanceOf(lpAdmin);
        uint accTokenPerShare = pool.accTokenPerShare + lpBalance * 1e12 / pool.deposit;
        return user.amount * accTokenPerShare / 1e12 - user.rewardDebt;
    }
}
