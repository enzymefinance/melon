pragma solidity ^0.4.2;

import "../dependencies/SafeMath.sol";
import "../dependencies/ERC20.sol";

/// @title Melon Token Contract
/// @author Melonport AG <team@melonport.com>
contract MelonToken is ERC20, SafeMath {

    // FILEDS

    // Constant token specific fields
    string public constant NAME = "Melon Token";
    string public constant SYMBOL = "MLN";
    uint public constant DECIMALS = 18;

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

    function MelonToken(address createdBy, uint startBlockInput, uint endBlockInput) {
        creator = createdBy;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
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
    // Post: Mints Token into illiquid tranche. They will become liquid once the Genesis block has been launched
    function mintIlliquidToken(address recipient, uint tokens)
        external
        only_creator
    {
        lockedBalances[recipient] = safeAdd(lockedBalances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from msg.sender
    /// Note: ERC 20 Standard Token interface transfer function
    function transfer(address _to, uint256 _value)
        block_number_past(endBlock)
        returns (bool success)
    {
        return super.transfer(_to, _value);
    }

    /// Pre: Prevent transfers until contribution period is over.
    /// Post: Transfer MLN from arbitrary address
    /// Note: ERC 20 Standard Token interface transferFrom function
    function transferFrom(address _from, address _to, uint256 _value)
        block_number_past(endBlock)
        returns (bool success)
    {
        return super.transferFrom(_from, _to, _value);
    }

}
