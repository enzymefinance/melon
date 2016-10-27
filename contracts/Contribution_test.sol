pragma solidity ^0.4.2;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken.sol";
import "./tokens/PrivateToken.sol";

/// @title Contribution_test Contract
/// @author Melonport AG <team@melonport.com>
contract Contribution_test is SafeMath {

    // FILEDS

    // Constant contribution specific fields
    uint public constant ETHER_CAP = 2000000 ether; // max amount raised during contribution
    uint public constant EARLY_BIRD = 250; // highest discount for the first 250 blks or roughly first hour
    uint public constant TRANSFER_LOCKUP = 370285; // transfers are locked for this many blocks after endBlock (assuming 14 second blocks, this is 2 months)
    uint public constant FOUNDER_LOCKUP = 2252571; // founder allocation cannot be created until this many blocks after endBlock (assuming 14 second blocks, this is 1 year)
    uint public constant FOUNDATION_PERCENT_ALLOCATION = 10; // 10% of token supply allocated post-contribution for the foundation fund
    uint public constant COMPANY_PERCENT_ALLOCATION = 15; // 15% of token supply allocated post-contribution for the companies allocation
    uint constant BLKS_PER_WEEK = 41710;
    uint constant UNIT = 10**3; // MILLI [m]

    // Fields that are only changed in constructor
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)
    address public founder = 0x0; // All deposited ETH will be instantly forwarded to this address.
    address public signer = 0x0; // signer address (for clickwrap agreement); see function() {} for comments

    // Fields that can be changed by functions
    uint public presaleEtherRaised = 0; // this will keep track of the Ether raised during the contribution
    uint public presaleTokenSupply = 0; // this will keep track of the token supply created during the contribution
    bool public foundationAllocated = false; // this will change to true when the foundation fund is allocated
    bool public companyAllocated = false; // this will change to true when the founder fund is allocated
    bool public halted = false; // the founder address can set this to true to halt the contribution due to emergency

    // Fields representing external contracts
    // TODO: Own contract instance for PrivateToken
    MelonToken public melonToken;
    MelonToken public privateToken;

    // EVENTS

    event Buy(address indexed sender, uint eth, uint fbt);
    event AllocateFounderTokens(address indexed sender);
    event AllocateMelonportTokens(address indexed sender);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _;
    }

    modifier only_founder() {
        if (msg.sender != founder) throw;
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

    modifier when_foundation_not_allocated() {
        if (foundationAllocated) throw;
        _;
    }

    modifier when_foundation_is_allocated() {
        if (!foundationAllocated) throw;
        _;
    }

    modifier when_company_not_allocated() {
        if (companyAllocated) throw;
        _;
    }

    // METHODS

    /// Pre: ALL fields, except { founder, signer, startBlock, endBlock } IS_VALID
    /// Post: `founder` IS_VALID, `signer` ID_VALID, `startBlock` IS_VALID, `end_block` IS_VALID.
    function Contribution_test(address founderInput, address signerInput, uint startBlockInput, uint endBlockInput) {
        founder = founderInput;
        signer = signerInput;
        startBlock = startBlockInput;
        endBlock = endBlockInput;

        // TODO: Own contract instance for PrivateToken
        melonToken = new MelonToken(this, startBlock, endBlock);
        privateToken = new MelonToken(this, startBlock, endBlock);
    }

    /// Pre: All contribution depositors must have read the legal agreement.
    ///  This is confirmed by having them signing the terms of service on the website.
    /// Post: Rejects sent amount, buy() takes this signature as input and rejects
    ///  all deposits that do not have signature you receive after reading terms.
    function() {
        throw;
    }

    /// Pre: startBlcok, endBlock specified in constructor
    /// Post: Contribution_test price in m{MLN+DPT}/ETH, where 1 MLN == 1000 mMLN, 1 DPT == 1000 mDPT
    function price() constant returns(uint)
    {
        // Discount tiers
        if (block.number>=startBlock && block.number<startBlock+EARLY_BIRD)
            return 1100;
        if (block.number>=startBlock + EARLY_BIRD && block.number < startBlock + 2*BLKS_PER_WEEK)
            return 1066;
        if (block.number>=startBlock + 2*BLKS_PER_WEEK && block.number < startBlock + 4*BLKS_PER_WEEK)
            return 1033;
        if (block.number>=startBlock + 4*BLKS_PER_WEEK && block.number < startBlock + 6*BLKS_PER_WEEK)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Price for a given blockNumber (!= block.number)
    /// Post: Externally defined blockNumber
    function testPrice() constant returns(uint)
    {
        // Discount tiers
        if (blockNumber>=startBlock && blockNumber<startBlock+EARLY_BIRD)
            return 1100;
        if (blockNumber>=startBlock + EARLY_BIRD && blockNumber < startBlock + 2*BLKS_PER_WEEK)
            return 1066;
        if (blockNumber>=startBlock + 2*BLKS_PER_WEEK && blockNumber < startBlock + 4*BLKS_PER_WEEK)
            return 1033;
        if (blockNumber>=startBlock + 4*BLKS_PER_WEEK && blockNumber < startBlock + 6*BLKS_PER_WEEK)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    // FOR TESTING PURPOSES ONLY:
    /// Pre: Assuming parts of code used where block.number is replaced (testcase) w blockNumber
    /// Post: Sets blockNumber for testing
    uint public blockNumber = 0;
    function setBlockNumber(uint blockNumberInput) {
        blockNumber = blockNumberInput;
    }

    /// Pre: Buy entry point, msg.value non-zero multiplier of 1000 WEI
    /// Post: Buy MLN
    function buy(uint8 v, bytes32 r, bytes32 s) {
        buyRecipient(msg.sender, v, r, s);
    }

    /// Pre: Buy on behalf of a recipient, msg.value non-zero multiplier of 1000 WEI
    /// Post: Buy MLN, send msg.value to founder address
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        is_signer(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        is_not_halted()
        msg_value_well_formed()
        ether_cap_not_reached()
    {
        uint tokens = safeMul(msg.value / UNIT, price()); // to avoid decimal numbers
        melonToken.mintToken(recipient, tokens);
        privateToken.mintToken(recipient, tokens);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
        if(!founder.send(msg.value)) throw; //immediately send Ether to founder address
        Buy(recipient, msg.value, tokens);
    }

    /// Pre: Fixed presaleTokenSupply. Founder, after freeze period plus founder lockup period is over
    /// Post: Allocate funds of Founders and Advisors to founder address.
    function allocateCompanyTokens()
        only_founder()
        block_number_past(endBlock + FOUNDER_LOCKUP)
        when_foundation_is_allocated()
        when_company_not_allocated()
    {
        var founder_allocation = presaleTokenSupply * COMPANY_PERCENT_ALLOCATION / 100;
        melonToken.mintToken(founder, founder_allocation);
        privateToken.mintToken(founder, founder_allocation);
        companyAllocated = true;
        AllocateFounderTokens(msg.sender);
    }

    /// Pre: Everybody (to prevent inflation gains), after contribution period has ended.
    /// Post: Fix presaleTokenSupply raised. Allocate funds of Melonport to founder address.
    function allocateFoundationTokens()
        block_number_past(endBlock)
        when_foundation_not_allocated()
    {
        // TODO: Consider, that totalSupply differs btw Tokens!
        presaleTokenSupply = melonToken.totalSupply() + privateToken.totalSupply();
        var foundation_allocation = presaleTokenSupply * FOUNDATION_PERCENT_ALLOCATION / 100;
        // TODO mint foundation token to illiquid part
        melonToken.mintToken(founder, foundation_allocation);
        privateToken.mintToken(founder, foundation_allocation);
        foundationAllocated = true;
        AllocateMelonportTokens(msg.sender);
    }

    function halt() only_founder() { halted = true; }

    function unhalt() only_founder() { halted = false; }

    function changeFounder(address newFounder) only_founder() { founder = newFounder; }

}
