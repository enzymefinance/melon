pragma solidity ^0.4.2;

import "./MelonToken.sol";

/// @title PolkaDot Token Contract
/// @author Melonport AG <team@melonport.com>
contract PolkaDotToken is MelonToken {

    // FILEDS

    // Constant token specific fields
    string public constant name = "PolkaDotToken";
    string public constant symbol = "PDT";
    uint8 public constant decimals = 18;

    // METHODS

    function PolkaDotToken()
        //TODO check this is correct
        MelonToken()
    {}

}
