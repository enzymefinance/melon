import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";

/// @title Melon Token Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Original taken from https://github.com/Firstbloodio/token
contract MelonToken is ERC20, SafeMath {

    // FILEDS

    // Constant token specific fields
    string public constant NAME = "Melon Token";
    string public constant SYMBOL = "MLN";
    uint public constant DECIMALS = 18;

    // Constant contribution specific fields
    uint public constant ETHER_CAP = 2000000 ether; // max amount raised during contribution
    uint public constant POWER_HOUR = 250; // highest discount for the first 250 blks or roughly first hour
    uint public constant TRANSFER_LOCKUP = 370285; // transfers are locked for this many blocks after endBlock (assuming 14 second blocks, this is 2 months)
    uint public constant FOUNDER_LOCKUP = 2252571; // founder allocation cannot be created until this many blocks after endBlock (assuming 14 second blocks, this is 1 year)
    uint public constant MELONPORT_PERCENT_ALLOCATION = 10; // 10% of token supply allocated post-contribution for the melonport fund
    uint public constant FOUNDER_PERCENT_ALLOCATION = 15; // 15% of token supply allocated post-contribution for the founder allocation

    // Fields that are only changed in constructor
    uint public startBlock; // contribution start block (set in constructor)
    uint public endBlock; // contribution end block (set in constructor)
    address public founder = 0x0; // All deposited ETH will be instantly forwarded to this address.
    address public signer = 0x0; // signer address (for clickwrap agreement); see function() {} for comments

    // Fields that can be changed by functions
    uint public presaleEtherRaised = 0; // this will keep track of the Ether raised during the contribution
    uint public presaleTokenSupply = 0; // this will keep track of the token supply created during the contribution
    bool public melonportAllocated = false; // this will change to true when the melonport fund is allocated
    bool public founderAllocated = false; // this will change to true when the founder fund is allocated
    bool public halted = false; // the founder address can set this to true to halt the contribution due to emergency

    // EVENTS

    event Buy(address indexed sender, uint eth, uint fbt);
    event Withdraw(address indexed sender, address to, uint eth);
    event AllocateFounderTokens(address indexed sender);
    event AllocateMelonportTokens(address indexed sender);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _
    }

    modifier only_founder() {
        if (msg.sender != founder) throw;
        _
    }

    modifier is_not_halted() {
        if (halted) throw;
        _
    }

    modifier ether_cap_not_reached() {
        if (safeAdd(presaleEtherRaised, msg.value) > ETHER_CAP) throw;
        _
    }

    modifier msg_value_well_formed() {
        if (msg.value < 1000 || msg.value % 1000 != 0) throw;
        _
    }

    modifier block_number_at_least(uint x) {
        if (!(x <= block.number)) throw;
        _
    }

    modifier block_number_past(uint x) {
        if (!(x < block.number)) throw;
        _
    }

    modifier block_number_at_most(uint x) {
        if (!(block.number <= x)) throw;
        _
    }

    modifier when_melonport_not_allocated() {
        if (melonportAllocated) throw;
        _
    }

    modifier when_melonport_is_allocated() {
        if (!melonportAllocated) throw;
        _
    }

    modifier when_founder_not_allocated() {
        if (founderAllocated) throw;
        _
    }

    // METHODS

    /// Pre: ALL fields, except { founder, signer, startBlock, endBlock } IS_VALID
    /// Post: `founder` IS_VALID, `signer` ID_VALID, `startBlock` IS_VALID, `end_block` IS_VALID.
    function MelonToken(address founderInput, address signerInput, uint startBlockInput, uint endBlockInput) {
        founder = founderInput;
        signer = signerInput;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
    }

    /// Pre: All contribution depositors must have read the legal agreement.
    ///  This is confirmed by having them signing the terms of service on the website.
    /// Post: Rejects sent amount, buy() takes this signature as input and rejects
    ///  all deposits that do not have signature you receive after reading terms.
    function() {
        throw;
    }

    /// Pre: startBlcok, endBlock specified in constructor
    /// Post: Contribution price in mMLN/ETH, where 1 MLN == 1000 mMLN
    function price() constant returns(uint)
    {
        if (block.number>=startBlock && block.number<startBlock+POWER_HOUR) return 1100; //power hour
        if (block.number<startBlock || block.number>endBlock) return 1000; //default price
        return 1000 + 4*(endBlock - block.number)/(endBlock - startBlock + 1)*100/4; //contribution price
    }

    /// Pre: Buy entry point
    /// Post: Buy MLN
    function buy(uint8 v, bytes32 r, bytes32 s) {
        buyRecipient(msg.sender, v, r, s);
    }

    /// Pre: Buy on behalf of a recipient, msg.value multiplier of 1000 WEI
    /// Post: Buy MLN, send msg.value to founder address
    /// Invariant: 1000 mMLN/ETH <= price() <= 1100 mMLN/ETH
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        is_signer(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        is_not_halted()
        msg_value_well_formed()
        ether_cap_not_reached()
    {
        uint tokens = safeMul(msg.value / 1000, price()); // to avoid decimal numbers
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
        if(!founder.send(msg.value)) throw; //immediately send Ether to founder address
        Buy(recipient, msg.value, tokens);
    }

    /// Pre: Fixed presaleTokenSupply. Founder, after freeze period plus founder lockup period is over
    /// Post: Allocate funds of Founders and Advisors to founder address.
    function allocateFounderTokens()
        only_founder()
        block_number_past(endBlock + FOUNDER_LOCKUP)
        when_melonport_is_allocated()
        when_founder_not_allocated()
    {
        var founder_allocation = presaleTokenSupply * FOUNDER_PERCENT_ALLOCATION / 100;
        balances[founder] = safeAdd(balances[founder], founder_allocation);
        totalSupply = safeAdd(totalSupply, founder_allocation);
        founderAllocated = true;
        AllocateFounderTokens(msg.sender);
    }

    /// Pre: Everybody (to prevent inflation gains), after contribution period has ended.
    /// Post: Fix presaleTokenSupply raised. Allocate funds of Melonport to founder address.
    function allocateMelonportTokens()
        block_number_past(endBlock)
        when_melonport_not_allocated()
    {
        presaleTokenSupply = totalSupply;
        var melonport_allocation = presaleTokenSupply * MELONPORT_PERCENT_ALLOCATION / 100;
        balances[founder] = safeAdd(balances[founder], melonport_allocation);
        totalSupply = safeAdd(totalSupply, melonport_allocation);
        melonportAllocated = true;
        AllocateMelonportTokens(msg.sender);
    }

    function halt() only_founder() { halted = true; }

    function unhalt() only_founder() { halted = false; }

    function changeFounder(address newFounder) only_founder() { founder = newFounder; }

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
