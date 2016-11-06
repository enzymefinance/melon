pragma solidity ^0.4.4;

import "../dependencies/SafeMath.sol";
import "../dependencies/ERC20.sol";

/// @title Melon Token Contract
/// @author Melonport AG <team@melonport.com>
contract MelonToken is ERC20, SafeMath {

    // FILEDS

    // Constant token specific fields
    string public constant name = "Melon Token";
    string public constant symbol = "MLN";
    uint public constant decimals = 18;

    // Fields that are only changed in constructor
    address public creator; // Contribution contract
    uint public startTime; // contribution start block (set in constructor)
    uint public endTime; // contribution end block (set in constructor)

    // Fields that can be changed by functions
    mapping (address => uint) lockedBalances;

    // MODIFIERS

    modifier only_creator {
        if (msg.sender != creator) throw;
        _;
    }

    modifier now_past(uint x) {
        if (now <= x) throw;
        _;
    }

    // CONSTANT METHODS

    function lockedBalanceOf(address _owner) constant returns (uint256 balance) {
        return lockedBalances[_owner];
    }

    // METHODS

    function MelonToken(address createdBy, uint startTimeInput, uint endTimeInput) {
        creator = createdBy;
        startTime = startTimeInput;
        endTime = endTimeInput;
    }

    // Pre: Address of Contribution contract (creator) is known
    // Post: Mints Token into liquid tranche
    function mintLiquidToken(address recipient, uint tokens)
        external
        only_creator
    {
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    // Pre: Address of Contribution contract (creator) is known
    // Post: Mints Token into iced tranche. They will become liquid once the Genesis block has been launched
    function mintIcedToken(address recipient, uint tokens)
        external
        only_creator
    {
        lockedBalances[recipient] = safeAdd(lockedBalances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    // Pre: Address of Contribution contract (creator) is known
    // Post: Creator transfers all its tokens to recipient address, only once possible
    function transferAllCreatorToken(address recipient)
        external
        only_creator
    {
        lockedBalances[recipient] = safeAdd(lockedBalances[recipient], lockedBalances[creator]);
        lockedBalances[creator] = 0;
    }

    // Pre: Thawing period has passed - iced funds have turned into liquid ones
    // Post: All funds available for trade
    function unlockBalance(address _who)
        now_past(endTime + 2 years)
    {
        balances[_who] = safeAdd(balances[_who], lockedBalances[_who]);
        lockedBalances[_who] = 0;
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from msg.sender
    /// Note: ERC 20 Standard Token interface transfer function
    function transfer(address _to, uint256 _value)
        now_past(endTime)
        returns (bool success)
    {
        return super.transfer(_to, _value);
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from arbitrary address
    /// Note: ERC 20 Standard Token interface transferFrom function
    function transferFrom(address _from, address _to, uint256 _value)
        now_past(endTime)
        returns (bool success)
    {
        return super.transferFrom(_from, _to, _value);
    }

}
