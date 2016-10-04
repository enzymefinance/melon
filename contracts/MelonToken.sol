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
    uint public constant ETHER_CAP = 500000 ether; //max amount raised during contribution (5.5M USD worth of ether will be measured with market price at beginning of the contribution)
    uint public constant TRANSFER_LOCKUP = 370285; //transfers are locked for this many blocks after endBlock (assuming 14 second blocks, this is 2 months)
    uint public constant FOUNDER_LOCKUP = 2252571; //founder allocation cannot be created until this many blocks after endBlock (assuming 14 second blocks, this is 1 year)
    uint public constant MELONPORT_ALLOCATION = 20 * 10**16; //20% of token supply allocated post-contribution for the melonport fund
	// ^^^ consider "uint public constant MELONPORT_PERCENT_ALLOCATION = 20;" as simpler.
    uint public constant FOUNDER_ALLOCATION = 20 * 10**16; //20% of token supply allocated post-contribution for the founder allocation
	// ^^^ consider "uint public constant FOUNDER_PERCENT_ALLOCATION = 20;" as simpler.

    // Fields that are only changed in constructor
    uint public startBlock; //contribution start block (set in constructor)
    uint public endBlock; //contribution end block (set in constructor)
    address public founder = 0x0; // All deposited ETH will be instantly forwarded to this address.
    address public signer = 0x0; // signer address (for clickwrap agreement); see function() {} for comments

    // Fields that can be changed by functions
    bool public melonportAllocated = false; //this will change to true when the melonport fund is allocated
    bool public founderAllocated = false; //this will change to true when the founder fund is allocated
    uint public presaleTokenSupply = 0; //this will keep track of the token supply created during the contribution
    uint public presaleEtherRaised = 0; //this will keep track of the Ether raised during the contribution
    bool public halted = false; //the founder address can set this to true to halt the contribution due to emergency

    // EVENTS

    event Buy(address indexed sender, uint eth, uint fbt);
    event Withdraw(address indexed sender, address to, uint eth);
    event AllocateFounderTokens(address indexed sender);
    event AllocateMelonportTokens(address indexed sender);

    // MODIFIERS

    modifier isSigner(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _
    }

    modifier onlyFounder() {
        if (msg.sender != founder) throw;
        _
    }

    modifier isNotHalted() {
        if (halted) throw;
        _
    }

    modifier etherCapNotReached() {
        if (safeAdd(presaleEtherRaised, msg.value) > ETHER_CAP) throw;
        _
    }

	// CHOOSE ONE FOR MODIFIERS: SNAKE OR CAMEL (i prefer snake for modifiers, camel for functions/fields)
    modifier block_number_at_least(uint x) {
        if (block.number >= x) throw;
        _
    }

    modifier block_number_past(uint x) {
        if (block.number > x) throw;
        _
    }

    modifier block_number_at_most(uint x) {
        if (block.number <= x) throw;
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
    /// Post: Contribution price in MLN/ETH; No state transition
    function price() constant returns(uint) {
        if (block.number>=startBlock && block.number<startBlock+250) return 170; //power hour
        if (block.number<startBlock || block.number>endBlock) return 100; //default price
		// ^^^ THIS MAKES NO SENSE. BETTER DEFINITION OF startBlock/endBlock REQUIRED.
        return 100 + 4*(endBlock - block.number)/(endBlock - startBlock + 1)*67/4; //contribution price
		// ^^^ this is integer arithmetic, including division, on values within the same range - does it work properly under all circumstances? 		
    }

    /// Pre: Buy entry point
    /// Post: Buy MLN
    function buy(uint8 v, bytes32 r, bytes32 s) {
        buyRecipient(msg.sender, v, r, s);
    }

    /// Pre: Buy on behalf of a recipient
    /// Post: Buy MLN, send msg.value to founder address
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        isSigner(v, r, s)
        block_number_at_least(startBlock)
        block_number_at_most(endBlock)
        isNotHalted()
        etherCapNotReached()
    {
        uint tokens = safeMul(msg.value, price());
		// ^^^ provide invariant over range of price.
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);
	    if (!founder.call.value(msg.value)()) throw; //immediately send Ether to founder address
    	// ^^^ Consider the gas-bounded .send  
        Buy(recipient, msg.value, tokens);
    }

    /// Pre: Founder, after freeze period plus founder lockup period is over
    /// Post: Set up founder address token balance w founder allocation,
    function allocateFounderTokens()
        onlyFounder()
        block_number_past(endBlock + FOUNDER_LOCKUP)
    {
        if (founderAllocated) throw;
		// ^^^ use condition "when_founder_not_allocated"
        if (!melonportAllocated) throw;
		// ^^^ use condition "when_melonport_is_allocated"
        balances[founder] = safeAdd(balances[founder], presaleTokenSupply * FOUNDER_ALLOCATION / (1 ether));
		// ^^^ consider:
		// var founder_allocation = presaleTokenSupply * FOUNDER_PERCENT_ALLOCATION / 100;
		// balances[founder] = safeAdd(balances[founder], founder_allocation);
        totalSupply = safeAdd(totalSupply, presaleTokenSupply * FOUNDER_ALLOCATION / (1 ether));
		// ^^^ consider: 
		// totalSupply = safeAdd(totalSupply, founder_allocation);
        founderAllocated = true;
        AllocateFounderTokens(msg.sender);
    }

    /// Pre: Founder, after freeze period is over
    /// Post: Set up founder address token balance w melonport allocation,
    function allocateMelonportTokens()
        onlyFounder()
        block_number_past(endBlock)
    {
        if (melonportAllocated) throw;
		// ^^^ use condition "when_melonport_not_allocated"
        presaleTokenSupply = totalSupply;
        balances[founder] = safeAdd(balances[founder], presaleTokenSupply * MELONPORT_ALLOCATION / (1 ether));
		// ^^^ consider:
		// var melonport_allocation = presaleTokenSupply * MELONPORT_PERCENT_ALLOCATION / 100;
		// balances[founder] = safeAdd(balances[founder], melonport_allocation);
        totalSupply = safeAdd(totalSupply, presaleTokenSupply * MELONPORT_ALLOCATION / (1 ether));
		// ^^^ consider: 
		// totalSupply = safeAdd(totalSupply, melonport_allocation);
        melonportAllocated = true;
        AllocateMelonportTokens(msg.sender);
    }

    function halt() onlyFounder() { halted = true; }

    function unhalt() onlyFounder() { halted = false; }

    function changeFounder(address newFounder) onlyFounder() { founder = newFounder; }

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
