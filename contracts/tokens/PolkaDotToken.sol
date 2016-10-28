pragma solidity ^0.4.2;

import "./MelonToken.sol";

/// @title PolkaDot Token Contract
/// @author Melonport AG <team@melonport.com>
contract PolkaDotToken is MelonToken {

    // FILEDS

    // Constant token specific fields
    string public constant NAME = "PolkaDotToken";
    string public constant SYMBOL = "DOT";
    uint public constant DECIMALS = 18;

    // METHODS

    function PolkaDotToken(address createdBy, uint startBlockInput, uint endBlockInput)
        //TODO check this is correct
        MelonToken(createdBy, startBlockInput, endBlockInput)
    {}

}
