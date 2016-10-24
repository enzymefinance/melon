pragma solidity ^0.4.2;

import "./MelonToken.sol";

/// @title Private Token Contract
/// @author Melonport AG <team@melonport.com>
contract PrivateToken is MelonToken {

    // FILEDS

    // Constant token specific fields
    string public constant NAME = "PrivateToken";
    string public constant SYMBOL = "DPT";
    uint public constant DECIMALS = 18;
    uint public constant TRANSFER_LOCKUP = 370285; // transfers are locked for this many blocks after endBlock (assuming 14 second blocks, this is 2 months)
    uint public constant THAWING_PERIOD = 2252571; // founder allocation cannot be created until this many blocks after endBlock (assuming 14 second blocks, this is 1 year)

    // Fields that are only changed in constructor
    address public creator;
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)

    // METHODS

    function PrivateToken(address createdBy, uint startBlockInput, uint endBlockInput) {
        creator = createdBy;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
    }

    function() {
        throw;
    }

}
