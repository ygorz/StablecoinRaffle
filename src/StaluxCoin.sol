// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 ______  ________   ______   __       __    __  __    __ 
 /      \|        \ /      \ |  \     |  \  |  \|  \  |  \
|  $$$$$$\\$$$$$$$$|  $$$$$$\| $$     | $$  | $$| $$  | $$
| $$___\$$  | $$   | $$__| $$| $$     | $$  | $$ \$$\/  $$
 \$$    \   | $$   | $$    $$| $$     | $$  | $$  >$$  $$ 
 _\$$$$$$\  | $$   | $$$$$$$$| $$     | $$  | $$ /  $$$$\ 
|  \__| $$  | $$   | $$  | $$| $$_____| $$__/ $$|  $$ \$$\
 \$$    $$  | $$   | $$  | $$| $$     \\$$    $$| $$  | $$
  \$$$$$$    \$$    \$$   \$$ \$$$$$$$$ \$$$$$$  \$$   \$$
                                                  
*/

contract StaluxCoin is ERC20, Ownable {
    /*\/-\/-\/-\/-\/-\/-\/-\/-\/-\/-\/-- FUNCTIONS --\/-\/-\/-\/-\/-\/-\/-\/-\/-\/*/

    /*--------------- CONSTRUCTOR ------------------------------------------------*/
    constructor() ERC20("StaluxCoin", "STALUX") Ownable(msg.sender) {}

    /*--------------- EXTERNAL FUNCTIONS -----------------------------------------*/
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
