pragma solidity ^0.4.2;

import "./MelonToken_test.sol";

/// @title PolkaDot_test Token Contract
/// @author Melonport AG <team@melonport.com>
contract PolkaDotToken_test is MelonToken_test {

    // FILEDS

    // Constant token specific fields
    string public constant name = "PolkaDotToken_test";
    string public constant symbol = "PDT";
    uint8 public constant decimals = 18;

    // METHODS

    function PolkaDotToken_test(address createdBy, uint startBlockInput, uint endBlockInput)
        //TODO check this is correct
        MelonToken_test(createdBy, startBlockInput, endBlockInput)
    {}

}
