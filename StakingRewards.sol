// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingRewards is ReentrancyGuard { //Let's define some state variable.

  /* Only owner able to set the duration of staking reward and 
  amount for the duration so let's create it. */
 
 
  /* ========== STATE VARIABLES ========== */

  IERC20 public immutable stakingToken;
  IERC20 public immutable rewardsToken;

  struct StakeInfo {
    uint256 amount;
    uint256 startTS; 
    uint256 endTS;
    uint256 reward;
  }

  address public owner;

  uint8 public stakerCount;
  uint public duration; // We need to keep track of the rewards.
  uint public finishAt; // We also store the time that the reward finishes.
  uint public rewardRate; // I think I don't need to explain this one.
  uint public totalSupply;
  uint public totalRewardPool;

  
  //We need to keep track of the reward for tokens store per user.
  mapping(address => uint) public userRewardPerTokenPaid;
  mapping(address => uint) public rewards; //Keep track of the rewards that the user earn
  mapping(address => StakeInfo[]) public stakeInfos;
  /* We need to define some state variables that keep track of
  the total supply of the staking token and amount stake per user.*/
  mapping(address => uint) public balanceOf; //To keep track of the staking token that is state per user.
  mapping(address => bool) public isStaker;
  mapping(uint8 => address) public stakeAddrs;

  modifier onlyOwner() {
    require(msg.sender == owner, "You're not the owner?");
    _;
  }
  modifier onlyStaker() {
    if(!isStaker[msg.sender]) {
      revert();
    }
    _;
  }


  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _stakingToken,
    address _rewardToken
    ) {
    owner = msg.sender;
    stakingToken = IERC20(_stakingToken);
    rewardsToken = IERC20(_rewardToken);
    rewardRate = 20;
    duration = 360 * 24 * 60 * 60;
  }


    /* ========== FUNCTION ========== */

  function setRewardsDuration(uint _duration) external onlyOwner {
    require(finishAt < block.timestamp, "Can't do that");
    duration = _duration;

  }

  function stake(uint _amount) external {
    require(_amount > 0, "amount = 0");
    stakingToken.transferFrom(msg.sender, address(this), _amount);
    stakerCount++;
    totalSupply += _amount;
    isStaker[msg.sender] = true;
    stakeAddrs[stakerCount] = msg.sender;
    stakeInfos[msg.sender].push(
      StakeInfo({
        amount: _amount,
        startTS: block.timestamp,
        endTS: block.timestamp + duration,
        reward: caculateRewardStake(_amount)
      })
    );
    emit Stake(msg.sender, _amount);
  }

  function claimToken() external payable onlyStaker nonReentrant {
    uint256 reward;
    for (uint256 _timeStake = 0; _timeStake < stakeInfos[msg.sender].length; _timeStake++) {
      if(stakeInfos[msg.sender][_timeStake].endTS < block.timestamp && stakeInfos[msg.sender][_timeStake].reward > 0) {
        reward += stakeInfos[msg.sender][_timeStake].reward;
        stakeInfos[msg.sender][_timeStake].reward = 0;
        SafeERC20.safeTransfer(stakingToken, msg.sender, stakeInfos[msg.sender][_timeStake].amount);
        totalSupply -= stakeInfos[msg.sender][_timeStake].amount;
        emit Claim(msg.sender, reward);
      }
    }
    require(reward > 0, "Not Enough time to claim reward token");
    require(totalRewardPool >= reward, "Not enough reward token in pool to claim");
    SafeERC20.safeTransfer(rewardsToken, msg.sender, reward);
    totalRewardPool -= reward;
    emit Claim(msg.sender, reward);
  }

  function addPoolRewardStake(uint256 _amount) external onlyOwner {
    rewardsToken.transferFrom(msg.sender, address(this), _amount);
    totalRewardPool += _amount;
  }

  function caculateRewardStake(uint256 _amount) internal view returns(uint256) {
    uint256 _reward;
    for (uint256 _month = 0; _month < 12; _month++) {
      _reward += _amount * (rewardRate - _month) * 30 / (100 * 360);
    }
    return _reward;
  }

  event Stake(
    address indexed from,
    uint256 amount
  );

  event Claim(
    address indexed from,
    uint256 amount
  );

}