pragma solidity ^0.4.2;

import "../dependencies/SafeMath.sol";
import "../dependencies/ERC20.sol";

/// @title Melon Token Contract
/// @author Melonport AG <team@melonport.com>
contract MelonToken_test is ERC20, SafeMath {

    // FILEDS

    // Constant token specific fields
    string public constant NAME = "Melon Token";
    string public constant SYMBOL = "MLN";
    uint public constant DECIMALS = 18;
    uint public constant TRANSFER_LOCKUP = 370285; // transfers are locked for this many blocks after endBlock (assuming 14 second blocks, this is 2 months)
    uint public constant THAWING_PERIOD = 2252571; // founder allocation cannot be created until this many blocks after endBlock (assuming 14 second blocks, this is 1 year)


    // Fields that are only changed in constructor
    address public creator;
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)

    // Fields that can be changed by functions
    mapping (address => uint) lockedBalances;

    // MODIFIERS

    modifier only_creator() {
        if (msg.sender != creator) throw;
        _;
    }

    modifier block_number_past(uint x) {
        if (!(x < block.number)) throw;
        _;
    }

    // METHODS

    function MelonToken_test(address createdBy, uint startBlockInput, uint endBlockInput) {
        creator = createdBy;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
    }

    function() {
        throw;
    }

    uint public test = 0;

    // Pre: Address of creator is known, i.e. Contribution contract
    // Post: Mints Token
    function mintToken(address recipient, uint tokens)
        external
        only_creator
    {
        test = 1;
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    // Pre: Thawing period has passed
    // Post: All funds available for trade
    function unlockBalance(address _who)
        block_number_past(endBlock + THAWING_PERIOD)
    {
        balances[_who] = safeAdd(balances[_who], lockedBalances[_who]);
        lockedBalances[_who] = 0;
    }

    /// Pre: Prevent transfers until freeze period is over.
    /// Post: Transfer MLN from msg.sender
    /// Note: ERC 20 Standard Token interface transfer function
    function transfer(address _to, uint256 _value)
        block_number_past(endBlock + TRANSFER_LOCKUP)
        returns (bool success)
    {
        return super.transfer(_to, _value);
    }

    /// Pre: Prevent transfers until freeze period is over.
    /// Post: Transfer MLN from arbitrary address
    /// Note: ERC 20 Standard Token interface transferFrom function
    function transferFrom(address _from, address _to, uint256 _value)
        block_number_past(endBlock + TRANSFER_LOCKUP)
        returns (bool success)
    {
        return super.transferFrom(_from, _to, _value);
    }

}
