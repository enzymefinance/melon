pragma solidity ^0.4.2;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken.sol";
import "./tokens/PolkaDotToken.sol";

/// @title Contribution_test Contract
/// @author Melonport AG <team@melonport.com>
/// @notice This follows Condition-Orientated Programming guideline as outlined here:
/// @notice   https://medium.com/@gavofyork/condition-orientated-programming-969f6ba0161a#.saav3bvva
contract Contribution_test is SafeMath {

    // FILEDS

    // Constant contribution specific fields
    uint public constant ETHER_CAP = 1800000 ether; // max amount raised during contribution
    uint public constant EARLY_BIRD = 250; // highest discount for the first 250 blks or roughly first hour
    uint constant BLKS_PER_WEEK = 41710;
    uint constant UNIT = 10**3; // MILLI [m]

    // Fields that are only changed in constructor
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)
    address public melonport = 0x0; // All deposited ETH will be instantly forwarded to this address.
    address public parity = 0x0; // Token allocation for company
    address public signer = 0x0; // signer address (for clickwrap agreement); see function() {} for comments

    // Fields that can be changed by functions
    uint public presaleEtherRaised = 0; // this will keep track of the Ether raised during the contribution
    uint public presaleTokenSupply = 0; // this will keep track of the token supply created during the contribution
    bool public companyAllocated = false; // this will change to true when the company funds are allocated
    bool public halted = false; // the melonport address can set this to true to halt the contribution due to emergency

    // Fields representing external contracts
    MelonToken public melonToken = new MelonToken(this, startBlock, endBlock);
    PolkaDotToken public polkaDotToken = new PolkaDotToken(this, startBlock, endBlock);

    // EVENTS

    event Buy(address indexed sender, uint eth, uint tokens);
    event AllocateCompanyTokens(address indexed sender);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _;
    }

    modifier only_melonport() {
        if (msg.sender != melonport) throw;
        _;
    }

    modifier is_not_halted() {
        if (halted) throw;
        _;
    }

    modifier ether_cap_not_reached() {
        if (safeAdd(presaleEtherRaised, msg.value) > ETHER_CAP) throw;
        _;
    }

    modifier msg_value_well_formed() {
        if (msg.value < UNIT || msg.value % UNIT != 0) throw;
        _;
    }

    modifier block_number_at_least(uint x) {
        if (!(x <= blockNumber)) throw;
        _;
    }

    modifier block_number_past(uint x) {
        if (!(x < blockNumber)) throw;
        _;
    }

    modifier block_number_at_most(uint x) {
        if (!(blockNumber <= x)) throw;
        _;
    }

    modifier when_company_not_allocated() {
        if (companyAllocated) throw;
        _;
    }

    // FUNCTIONAL METHODS

    /// Pre: startBlcok, endBlock specified in constructor
    /// Post: Contribution_test price in m{MLN+DPT}/ETH, where 1 MLN == 1000 mMLN, 1 DPT == 1000 mDPT
    function price(bool wantLiquidity) constant returns(uint)
    {
        // One illiquid tier
        if (wantLiquidity == false && block.number>=startBlock && block.number < endBlock)
            return 1125;
        // Four liquid tiers
        if (block.number>=startBlock && block.number < startBlock + 2*BLKS_PER_WEEK)
            return 1075;
        if (block.number>=startBlock + 2*BLKS_PER_WEEK && block.number < startBlock + 4*BLKS_PER_WEEK)
            return 1050;
        if (block.number>=startBlock + 4*BLKS_PER_WEEK && block.number < startBlock + 6*BLKS_PER_WEEK)
            return 1025;
        if (block.number>=startBlock + 6*BLKS_PER_WEEK && block.number < endBlock)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Price for a given blockNumber (!= block.number)
    /// Post: Externally defined blockNumber
    function testPrice(bool wantLiquidity) constant returns(uint)
    {
        // One illiquid tier
        if (wantLiquidity == false && blockNumber>=startBlock && blockNumber < endBlock)
            return 1125;
        // Four liquid tiers
        if (blockNumber>=startBlock && blockNumber < startBlock + 2*BLKS_PER_WEEK)
            return 1075;
        if (blockNumber>=startBlock + 2*BLKS_PER_WEEK && blockNumber < startBlock + 4*BLKS_PER_WEEK)
            return 1050;
        if (blockNumber>=startBlock + 4*BLKS_PER_WEEK && blockNumber < startBlock + 6*BLKS_PER_WEEK)
            return 1025;
        if (blockNumber>=startBlock + 6*BLKS_PER_WEEK && blockNumber < startBlock + 8*BLKS_PER_WEEK)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // NON-CONDITIONAL IMPERATIVAL METHODS

    /// Pre: ALL fields, except { melonport, signer, startBlock, endBlock } IS_VALID
    /// Post: `melonport` IS_VALID, `signer` ID_VALID, `startBlock` IS_VALID, `end_block` IS_VALID.
    function Contribution_test(address melonportInput, address parityInput, address signerInput, uint startBlockInput, uint endBlockInput) {
        melonport = melonportInput;
        parity = parityInput;
        signer = signerInput;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
    }

    /// Pre: All contribution depositors must have read the legal agreement.
    ///  This is confirmed by having them signing the terms of service on the website.
    /// Post: Rejects sent amount, buy() takes this signature as input and rejects
    ///  all deposits that do not have signature you receive after reading terms.
    function() {}

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Assuming parts of code used where block.number is replaced (testcase) w blockNumber
    /// Post: Sets blockNumber for testing
    uint public blockNumber = 0;
    function setBlockNumber(uint blockNumberInput) {
        blockNumber = blockNumberInput;
    }

    /// Pre: Buy entry point, msg.value non-zero multiplier of 1000 WEI
    /// Post: Buy MLN
    function buy(bool wantLiquidity, uint8 v, bytes32 r, bytes32 s)
        payable
    {
        buyRecipient(wantLiquidity, msg.sender, v, r, s);
    }

    /// Pre: Buy on behalf of a recipient, msg.value non-zero multiplier of 1000 WEI
    /// Post: Buy MLN, send msg.value to melonport address
    function buyRecipient(bool wantLiquidity, address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        is_not_halted()
        msg_value_well_formed()
        ether_cap_not_reached()
    {
        // FOR TESTING PURPOSES ONLY: testPrice()
        uint tokens = safeMul(msg.value / UNIT, testPrice(wantLiquidity)); // to avoid decimal numbers
        if (wantLiquidity == true) {
            //TODO: check if functions execute
            melonToken.mintLiquidToken(recipient, tokens / 3);
            polkaDotToken.mintLiquidToken(recipient, 2 * tokens / 3);
        } else {
            //TODO: check if functions execute
            melonToken.mintIlliquidToken(recipient, tokens / 3);
            polkaDotToken.mintIlliquidToken(recipient, 2 * tokens / 3);
        }
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
        if(!melonport.send(msg.value)) throw; //immediately send Ether to melonport address
        Buy(recipient, msg.value, tokens);
    }

    /// Pre: Melonport even before contribution period
    /// Post: Allocate funds of the two companies to their company address.
    function allocateCompanyTokens()
        only_melonport()
        when_company_not_allocated()
    {
        melonToken.mintIlliquidToken(melonport, ETHER_CAP * 1200 / 30000); // 12 percent for melonport
        melonToken.mintIlliquidToken(parity, ETHER_CAP * 300 / 30000); // 3 percent for parity
        polkaDotToken.mintIlliquidToken(melonport, 2 * ETHER_CAP * 75 / 30000); // 0.75 percent for melonport
        polkaDotToken.mintIlliquidToken(parity, 2 * ETHER_CAP * 1425 / 30000); // 14.25 percent for parity
        companyAllocated = true;
        AllocateCompanyTokens(msg.sender);
    }

    function halt() only_melonport() { halted = true; }

    function unhalt() only_melonport() { halted = false; }

    function changeFounder(address newFounder) only_melonport() { melonport = newFounder; }

}
