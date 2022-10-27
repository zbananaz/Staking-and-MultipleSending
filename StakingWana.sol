//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "hardhat/console.sol";

contract WanaFarmV3 is Ownable {

    ERC20 public stakeToken;
    ERC20 public rewardToken;
    uint256 public totalStakedAmount = 0;
    uint256 public totalUnStakedAmount = 0;
    uint256 public totalDebtAmount = 0;
    uint256 public totalFundAmount = 0;

    // +----------+---Rank1---+---Rank2-----+----Rank3-----+----Rank4-----+-------------+
    // |          |  min 0    |  min 250    |  min 20,000  |  min 40,000  | Pool Limit  | 
    // +----------+-----------+-------------+--------------+--------------+-------------+
    // |   7 days |      _    |     _       |      _       |      _       |      _      |
    // +----------+-----------+-------------+--------------+--------------+-------------+
    // |  30 days |     09    |     12      |      15      |      17      |  2,115,000  |
    // +----------+-----------+-------------+--------------+--------------+-------------+
    // |  90 days |     11    |     16      |      20      |      22      |  3,145,000  |
    // +----------+-----------+-------------+--------------+--------------+-------------+
    // | 180 days |     15    |     19      |      23      |      25      |  unlimited  |
    // +----------+-----------+-------------+--------------+--------------+-------------+

    uint256 constant private INVALID_INDEX = 999;

    uint[4][4] public APR = [
    [800,900,1300,1500],
    [900,1200,1500,1700],
    [1100,1600,2000,2200],
    [1500,1900,2300,2500]
    ]; // value/10000 = num %

    uint[4] public stakedPool = [0,0,0,0];
    bool[4] public stakePoolActive = [true, true, true, true];

    uint public multiple = 95; // 95%
    uint public periodTimeReduceApr = 30 days; // 30 days
    uint256 public timeExecuteReduce = block.timestamp;

    uint[4][4] public detailStakedPool = [
    [0,0,0,0],
    [0,0,0,0],
    [0,0,0,0],
    [0,0,0,0]
    ];

    uint256 constant public oneWeekPoolLimit = 10**6;

    // limit 2,115,000
    uint256 constant public oneMonthPoolLimit = 2115*10**3;

    // limit 3,145,000
    uint256 constant public threeMonthPoolLimit = 3145*10**3;

    struct StakerInfo {
        uint256 amount;
        uint releaseDate;
        bool isRelease;
        uint256 rewardDebt;
        uint termOption;
        uint apr;
    }
    event Stake(address indexed _from, uint _duration , uint _value, uint _apr);
    event UnStake(address indexed _from, uint _duration, uint _value);
    event ChangeMinAmountLevel(uint32 _level, uint256 _amount);
    event ChangeAprValue(uint32 _x, uint32 _y, uint _apr);
    event ReduceAllApr(uint timestamp, uint256 timeExecuteReduce);

    mapping (address => StakerInfo[]) public stakers;

    uint public minAmountDiamond = 30000;
    uint public minAmountGold = 15000;
    uint public minAmountSilver = 5000;
    uint public minAmountBronze = 250;

    modifier underOneWeekPoolRemain(uint256 _amount) {
        require(oneWeekPoolRemain() >= _amount, "One week pool limit reached");
        _;
    }

    modifier underOneMonthPoolRemain(uint256 _amount) {
        require(oneMonthPoolRemain() >= _amount, "One month pool limit reached");
        _;
    }

    modifier underThreeMonthPoolRemain(uint256 _amount) {
        require(threeMonthPoolRemain() >= _amount, "Three month pool limit reached");
        _;
    }

    constructor (ERC20 _stakeToken, ERC20 _rewardToken, uint _multiple) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        multiple = _multiple;
        timeExecuteReduce = block.timestamp;
    }

    function changeAmountMinStake(uint32 _level, uint _amount) external onlyOwner returns(bool isValid){
        require(_level == 0 || _level == 1 || _level == 2 || _level == 3, "Invalid level index");
        if (_level == 3) {
            minAmountDiamond = _amount;
            isValid = true;
        }
        else if (_level == 2) {
            minAmountGold = _amount;
            isValid = true;
        }
        else if (_level == 1) {
            minAmountSilver = _amount;
            isValid = true;
        }
        else if(_level == 0) {
            minAmountBronze = _amount;
            isValid = true;
        }
        emit ChangeMinAmountLevel(_level, _amount);
    }

    function changeAprStake(uint32 _x, uint32 _y, uint _apr) external onlyOwner {
        require(APR[_x][_y] > 0, "Invalid level apr");
        require(_apr >= 0, "Invalid amount value");
        APR[_x][_y] = _apr;
        emit ChangeAprValue(_x, _y, _apr);
    }

    function changeActivePool(uint _stakePoolIndex, bool _status) external onlyOwner {
        require(_stakePoolIndex == 0 || _stakePoolIndex == 1 || _stakePoolIndex == 2 || _stakePoolIndex == 3, "Invalid index pool");
        stakePoolActive[_stakePoolIndex] = _status;
    }

    function _checkReduceAllAprPool() internal {
        uint256 _latestTime = block.timestamp;
        if (_latestTime - timeExecuteReduce <= periodTimeReduceApr) return;
        uint256 _difTime = _latestTime - timeExecuteReduce;
        uint256 _roundPassed = _difTime / periodTimeReduceApr;
        if (_roundPassed == 0) return;
        uint256 _reducePercent = 1;
        uint256 _percent = 1;
        for (uint i=0; i< _roundPassed; i++){
            _reducePercent = _reducePercent * multiple;
            _percent = _percent * 100;
            timeExecuteReduce = timeExecuteReduce + periodTimeReduceApr;
        }
        for(uint i=0; i< APR.length; i++){
            for(uint k=0; k< APR[i].length; k++){
                APR[i][k] = APR[i][k] * _reducePercent / _percent;
            }
        }
        emit ReduceAllApr(_latestTime, timeExecuteReduce);
    }

    function getAPRIndex(uint256 _amount) external view returns (uint256 _index) {
        return _getAPRIndex(_amount);
    }

    function _getAPRIndex(uint256 _amount) private view returns (uint256 _index) {
        if (_amount >= minAmountDiamond * 10**stakeToken.decimals()) {
            return 3;
        }
        if (_amount >= minAmountGold * 10**stakeToken.decimals()) {
            return 2;
        }
        if (_amount >= minAmountSilver * 10**stakeToken.decimals()) {//0
            return 1;
        }
        if (_amount >= minAmountBronze * 10**stakeToken.decimals()) {
            return 0;
        }
        return INVALID_INDEX; // Reject
    }

    function getStakedPoolIndex(uint256 termOption) public pure returns (uint256) {
        if (termOption == 7) {
            return 0;
        }
        if (termOption == 30) {
            return 1;
        }
        if (termOption == 90) {
            return 2;
        }
        if (termOption == 180) {
            return 3;
        }
        return INVALID_INDEX; // Never reach
    }

    function oneWeekStake(uint256 _amount) underOneWeekPoolRemain(_amount) external {
        _stake(_amount, 7);
    }
    function oneMonthStake(uint256 _amount) underOneMonthPoolRemain(_amount) external {
        _stake(_amount, 30);
    }
    function threeMonthStake(uint256 _amount) underThreeMonthPoolRemain(_amount) external {
        _stake(_amount, 90);
    }
    function sixMonthStake(uint256 _amount) external {
        _stake(_amount, 180);
    }

    function _stake(uint256 _amount, uint _termOption) internal {
        uint256 _APRIndex = _getAPRIndex(_amount);
        uint256 _stakedPoolIndex = getStakedPoolIndex(_termOption);

        require(_APRIndex != INVALID_INDEX, "Invalid stake amount");

        require(_stakedPoolIndex != INVALID_INDEX, "Invalid term option");

        require(stakePoolActive[_stakedPoolIndex] == true, "Pool is inactive");

        _checkReduceAllAprPool();

        uint _apr = APR[_stakedPoolIndex][_APRIndex];
        StakerInfo memory _stakerInfo = StakerInfo(
            _amount,
            block.timestamp + _termOption * 1 days,
            false,
            _termOption * _amount * _apr / 10000 / 365,
            _termOption,
            _apr
        );
        stakers[msg.sender].push(_stakerInfo);

        totalStakedAmount += _amount;
        totalDebtAmount += _stakerInfo.rewardDebt;
        stakedPool[_stakedPoolIndex] += _amount;
        detailStakedPool[_stakedPoolIndex][_APRIndex] += _amount;

        SafeERC20.safeTransferFrom(stakeToken, msg.sender, address(this), _amount);

        emit Stake(msg.sender, _termOption, _amount, _apr);
    }

    function unStake(uint _index) external {

        require(_index < stakers[msg.sender].length, "Index out of bounds");

        StakerInfo storage _stakerInfo = stakers[msg.sender][_index];
        require(_stakerInfo.amount > 0 , "Stake amount must be greater than zero");
        require(_stakerInfo.isRelease == false , "Stake has already been released");

        require(_stakerInfo.releaseDate <= block.timestamp , "You can not unstake before release date");

        _stakerInfo.isRelease = true;

        totalUnStakedAmount += _stakerInfo.amount;
        if (totalDebtAmount > _stakerInfo.rewardDebt) totalDebtAmount -= _stakerInfo.rewardDebt;
        if (totalFundAmount >= _stakerInfo.rewardDebt) totalFundAmount -= _stakerInfo.rewardDebt;

        stakedPool[getStakedPoolIndex(_stakerInfo.termOption)] -= _stakerInfo.amount;
        detailStakedPool[getStakedPoolIndex(_stakerInfo.termOption)][_getAPRIndex(_stakerInfo.amount)] -= _stakerInfo.amount;

        SafeERC20.safeTransfer(stakeToken, msg.sender, _stakerInfo.amount);
        SafeERC20.safeTransfer(rewardToken, msg.sender, _stakerInfo.rewardDebt);

        emit UnStake(msg.sender, _stakerInfo.termOption, _stakerInfo.amount);

    }

    function getStakerInfo(address _staker, uint _from, uint _to) external view returns (StakerInfo[] memory result){
        StakerInfo[] memory _stakerInfo = stakers[_staker];
        if (_stakerInfo.length == 0) return result;
        if (_to >= _stakerInfo.length) _to = _stakerInfo.length - 1;
        require(_from <= _to, "From must be equal or less than To");

        uint length = _to - _from + 1;
        result = new StakerInfo[](length);

        for (uint i = _from; i <= _to; i++) {
            result[i - _from] = _stakerInfo[i];
        }
        return result;
    }

    function getStakerInfoByTermOption(address _staker, uint _termOption, uint _from, uint _to)
    external view returns (StakerInfo[] memory){

        StakerInfo[] memory _stakerInfo = stakers[_staker];

        require(_from <= _to, "From must be less than To");

        uint length = 0;
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption) {
                length ++;
            }
        }

        require(0 <= _from && _from < length, "Invalid From index");
        require(0 <= _to && _to < length, "Invalid To index");

        uint count = 0;
        uint index = 0;
        StakerInfo[] memory result = new StakerInfo[](_to - _from + 1);
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption) {
                if (_from <= count && count <= _to) {
                    result[index++] = _stakerInfo[i];
                }
                if (count == _to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getStakerInfoByRelease(address _staker, bool _isRelease, uint _from, uint _to)
    external view returns (StakerInfo[] memory){

        StakerInfo[] memory _stakerInfo = stakers[_staker];

        require(_from <= _to, "From must be less than To");

        uint length = 0;
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == _isRelease) {
                length ++;
            }
        }

        require(0 <= _from && _from < length, "Invalid From index");
        require(0 <= _to && _to < length, "Invalid To index");

        uint count = 0;
        uint index = 0;
        StakerInfo[] memory result = new StakerInfo[](_to - _from + 1);
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == _isRelease) {
                if (_from <= count && count <= _to) {
                    result[index++] = _stakerInfo[i];
                }
                if (count == _to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getStakerInfoByTermOptionAndRelease(address _staker, uint _termOption, bool _isRelease, uint _from, uint _to)
    external view returns (StakerInfo[] memory){

        StakerInfo[] memory _stakerInfo = stakers[_staker];

        require(_from <= _to, "From must be less than To");

        uint length = 0;
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption && _stakerInfo[i].isRelease == _isRelease) {
                length ++;
            }
        }

        require(0 <= _from && _from < length, "Invalid From index");
        require(0 <= _to && _to < length, "Invalid To index");

        uint count = 0;
        uint index = 0;
        StakerInfo[] memory result = new StakerInfo[](_to - _from + 1);
        for (uint i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption && _stakerInfo[i].isRelease == _isRelease) {
                if (_from <= count && count <= _to) {
                    result[index++] = _stakerInfo[i];
                }
                if (count == _to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getDetailStakedPool() external view returns (uint256[4][4] memory){
        return detailStakedPool;
    }

    function getDetailAllApr() external view returns (uint256[4][4] memory){
        return APR;
    }

    function totalStakeByAddress(address _address) external view returns(uint) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_address];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == false) {
                total += _stakerInfo[i].amount;
            }
        }
        return total;
    }

    function totalRewardDebtByAddress(address _address) external view returns(uint _staked) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_address];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == true) {
                total += _stakerInfo[i].rewardDebt;
            }
        }
        return total;
    }

    function getStakeCount(address _address) external view returns (uint) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_address];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == false) {
                total += 1;
            }
        }
        return total;
    }

    function getStakeInfo(address _staker,uint _index) external view returns (uint256 _amount,uint _releaseDate,bool _isRelease,uint256 _rewardDebt) {
        return (stakers[_staker][_index].amount, stakers[_staker][_index].releaseDate, stakers[_staker][_index].isRelease, stakers[_staker][_index].rewardDebt);
    }

    function getStakeInfoByIndex(uint _index) external view returns (address _staker, uint256 _amount, uint _releaseDate, bool _isRelease, uint256 _rewardDebt) {
        StakerInfo storage _stakerInfo = stakers[msg.sender][_index];
        return (_staker, _stakerInfo.amount, _stakerInfo.releaseDate, _stakerInfo.isRelease, _stakerInfo.rewardDebt);
    }

    function totalStakerInfoByTermOption(address _staker, uint _termOption) external view returns (uint) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_staker];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption) {
                total ++;
            }
        }
        return total;
    }

    function totalStakerInfoByTermOptionAndRelease(address _staker, uint _termOption, bool _isRelease) external view returns (uint) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_staker];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].termOption == _termOption && _stakerInfo[i].isRelease == _isRelease) {
                total ++;
            }
        }
        return total;
    }

    function totalStakerInfoByRelease(address _staker, bool _isRelease) external view returns (uint) {
        uint total = 0;
        StakerInfo[] storage _stakerInfo = stakers[_staker];
        for (uint256 i = 0; i < _stakerInfo.length; i++) {
            if (_stakerInfo[i].isRelease == _isRelease) {
                total ++;
            }
        }
        return total;
    }

    function oneWeekPoolRemain() public view returns(uint256) {
        return oneWeekPoolLimit * 10**stakeToken.decimals() - stakedPool[0];
    }

    function oneMonthPoolRemain() public view returns(uint256) {
        return oneMonthPoolLimit * 10**stakeToken.decimals() - stakedPool[1];
    }

    function threeMonthPoolRemain() public view returns(uint256) {
        return threeMonthPoolLimit * 10**stakeToken.decimals() - stakedPool[2];
    }

    function depositFunds(uint256 _amount) external {
        SafeERC20.safeTransferFrom(rewardToken, msg.sender, address(this), _amount);
        totalFundAmount += _amount;
    }

    function rescueFunds(
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_amount <= totalFundAmount, "Amount is out of range");
        SafeERC20.safeTransfer(rewardToken, _to, _amount);
    }
}
