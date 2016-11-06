pragma solidity ^0.4.4;

import "./MelonToken.sol";

/// @title Dot Token Contract
/// @author Melonport AG <team@melonport.com>
contract DotToken is MelonToken {

    // FILEDS

    // Constant token specific fields
    string public constant name = "DotToken";
    string public constant symbol = "DOT";
    uint public constant decimals = 18;

    // METHODS

    function DotToken(address createdBy, uint startTimeInput, uint endTimeInput)
        MelonToken(createdBy, startTimeInput, endTimeInput)
    {}

}
