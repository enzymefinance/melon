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
    uint public constant THAWING_DURATION = 2 years; // time needed for iced tokens to thaw into liquid tokens
    uint public constant MAX_TOTAL_TOKEN_AMOUNT = 1250000; // max amount of total tokens raised during all contributions

    // Fields that are only changed in constructor
    address public minter; // Contribution contract(s)
    address public melonport; // Can change to other minting contribution contracts but only until total amount of token minted
    uint public startTime; // contribution start block (set in constructor)
    uint public endTime; // contribution end block (set in constructor)

    // Fields that can be changed by functions
    mapping (address => uint) lockedBalances;

    // MODIFIERS

    modifier only_minter {
        assert(msg.sender == minter);
        _;
    }

    modifier only_melonport {
        assert(msg.sender == melonport);
        _;
    }

    modifier now_past(uint x) {
        assert(now > x);
        _;
    }

    modifier max_total_token_amount_not_reached(uint tokens) {
        assert(safeAdd(totalSupply, tokens) <= MAX_TOTAL_TOKEN_AMOUNT);
        _;
    }

    // CONSTANT METHODS

    function lockedBalanceOf(address _owner) constant returns (uint256 balance) {
        return lockedBalances[_owner];
    }

    // METHODS

    /// Pre: All fields, except { minter, melonport, startTime, endTime } are valid
    /// Post: All fields, including { minter, melonport, startTime, endTime } are valid
    function MelonToken(address setMinter, address setMelonport, uint setStartTime, uint setEndTime) {
        minter = setMinter;
        melonport = setMelonport;
        startTime = setStartTime;
        endTime = setEndTime;
    }

    /// Pre: Address of Contribution contract (minter) is known
    /// Post: Mints Token into liquid tranche
    function mintLiquidToken(address recipient, uint tokens)
        external
        only_minter
        max_total_token_amount_not_reached(tokens)
    {
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    /// Pre: Address of Contribution contract (minter) is known
    /// Post: Mints Token into iced tranche. Become liquid after completion of the melonproject or two years.
    function mintIcedToken(address recipient, uint tokens)
        external
        only_minter
        max_total_token_amount_not_reached(tokens)
    {
        lockedBalances[recipient] = safeAdd(lockedBalances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    /// Pre: Thawing period has passed - iced funds have turned into liquid ones
    /// Post: All funds available for trade
    function unlockBalance(address ofContributor)
        now_past(endTime + THAWING_DURATION)
    {
        balances[ofContributor] = safeAdd(balances[ofContributor], lockedBalances[ofContributor]);
        lockedBalances[ofContributor] = 0;
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

    /// Pre: Melonport address is set.
    /// Post: New minter can now create tokens up to MAX_TOTAL_TOKEN_AMOUNT.
    /// Note: This allows additional contribution periods at a later stage, while stile using the same ERC20 compliant token contract.
    function changeMintingAddress(address newAddress) only_melonport { minter = newAddress; }
}
