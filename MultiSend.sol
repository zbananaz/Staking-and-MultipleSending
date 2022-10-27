// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {
  
}

contract Token {
    Token ptaToken;
    
    uint8 public decimals;

    function transfer(address _to, uint256 _value) public returns (bool success) {}
    
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {}

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {}
}

contract BulkSend {
    using SafeMath for uint256;

    Token ptaToken;
    
    address public owner;
    uint public tokenSendFee; // in wei
    uint  total;
    
    mapping(address => uint) public _balances;
    
    modifier onlyOwner() {
      require(msg.sender == owner);
      _;
    }
    constructor(Token _tokenAddress) {
        require(
            address(_tokenAddress) != address(0),
            "Token Address cannot be address 0"
        );
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        ptaToken = _tokenAddress;
        // emit OwnerSet(address(0), owner);
    }

    /**
    * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */

    // charge enable the owner to store ether in the smart-contract
    function addTokenToPool(uint256 amount) external onlyOwner {
        // adding the message value to the smart contract

        ptaToken.transferFrom(msg.sender, address(this), amount);
        total += amount;
    }

    event Transfered(address indexed from, address indexed to, uint value);

    function transfer(address to, uint value) public returns (bool){
        require(value <= _balances[msg.sender]);
        require(to != address(0));

        _balances[msg.sender] = _balances[msg.sender] - value;
        _balances[to] = _balances[to] + value;
        emit Transfered(msg.sender, to, value);
        return true;
    }

    function sub(uint a, uint b) internal pure returns (uint){
        return a - b;
    }

    //use unsafe math to save gas
    function unsafe_inc(uint x) private pure returns (uint) {
        unchecked {
        return x + 1;
        }
    }

    function sum(uint[] memory amounts) public pure returns(uint) {
        uint totalAmount = 0;

        for(uint i = 0; i < amounts.length; i = unsafe_inc(i)) {
            totalAmount += amounts[i];
        }
        return totalAmount;
    }
    
    function getbalance(address addr) public view returns (uint value){
        return addr.balance;
    }
    
    function deposit() payable public returns (bool){
        return true;
    }
    
    function withdraw(address tokenAddr, uint _amount) public onlyOwner returns(bool success){
        ptaToken.transfer(tokenAddr, _amount);
        return true;
    }

    function withdrawlMulti(address[] memory addresses, uint256[] memory amounts)
        external
        onlyOwner
    {
        uint _total = total;
        uint totalAmount;

        // the addresses and amounts should be same in length
        require(
            addresses.length == amounts.length,
            "The length of two array should be the same"
        );

        // the value of the message in addition to sorted value should be more than total amounts
        totalAmount = sum(amounts);

        require(
            total >= totalAmount,
            "The value is not sufficient or exceed"
        );
        //call unsafe_inc() để save gas
        for (uint i = 0; i < addresses.length; i = unsafe_inc(i)) {
            //nếu dùng total thì nó sẽ tốn nhiều gas hơn cho mỗi lần gọi đến vì là biến global,
            //tạo _total để gọi r update lần cuối vào total sẽ mất ít gas hơn
            _total -= amounts[i];

            // send the specified amount to the recipient
            withdraw(addresses[i], amounts[i]);
        }

        total = _total;
    }
    
    function setTokenFee(uint _tokenSendFee) public onlyOwner returns(bool success){
        tokenSendFee = _tokenSendFee;
        return true;
    }


    /*===================Test event listener===================*/

    event Transfer(address indexed from, address indexed to, uint value);
    
 
}