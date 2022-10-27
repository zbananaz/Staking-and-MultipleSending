// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PTAToken is ERC20 {
    constructor() ERC20("PhanAnh", "PTA") {
      _mint(msg.sender, 1000000);
    }
}