pragma solidity ^0.4.24;

import "./openzeppelin/IERC20.sol";

contract Alchemist {
    address public LEAD;
    address public GOLD;

    constructor(address _lead, address _gold) {
        LEAD = _lead;
        GOLD = _gold;
    }

    function transmute(uint _mass) {
        require(
            IERC20(LEAD).transferFrom(msg.sender, address(this), _mass),
            "LEAD transfer failed"
        );
        require(
            IERC20(GOLD).transfer(msg.sender, _mass),
            "GOLD transfer failed"
        );
    }
}

