pragma solidity ^0.4.4;

import "./MelonToken.sol";

/// @title PolkaDot Token Contract
/// @author Melonport AG <team@melonport.com>
contract PolkaDotToken is MelonToken {

    // FILEDS

    // Constant token specific fields
    string public constant name = "PolkaDotToken";
    string public constant symbol = "DOT";
    uint public constant decimals = 18;

    // METHODS

    function PolkaDotToken(address createdBy, uint startTimeInput)
        MelonToken(createdBy, startTimeInput)
    {}

}
