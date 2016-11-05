pragma solidity ^0.4.4;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken.sol";
import "./tokens/PolkaDotToken.sol";

/// @title Contribution Contract
/// @author Melonport AG <team@melonport.com>
/// @notice This follows Condition-Orientated Programming as outlined here:
/// @notice   https://medium.com/@gavofyork/condition-orientated-programming-969f6ba0161a#.saav3bvva
contract Contribution is SafeMath {

    // FILEDS

    // Constant fields
    uint public constant ETHER_CAP = 1800000 ether; // max amount raised during contribution
    uint public constant ICED_ETHER_CAP = ETHER_CAP * 40 / 100 ; // iced means untradeable untill genesis blk or two years
    uint public constant LIQUID_ETHER_CAP = ETHER_CAP * 60 / 100; // liquid means tradeable
    uint public constant BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
    uint public constant MELONPORT_PERCENT_STAKE = 15; // 15% of all created token allocated to melonport
    uint constant ICED_RATE = 1125; // One iced tier, remains constant for the duration of the contribution
    uint constant UNIT = 10**3; // MILLI [m], msg.value is divided by this unit, used to avoid decimal numbers

    // Fields that are only changed in constructor
    address public melonport; // All deposited ETH will be instantly forwarded to this address.
    address public parity; // Token allocation for company
    address public btcs; // Bitcoin Suisse allocation option
    address public signer; // signer address see function() {} for comments
    uint public startTime; // contribution start block (set in constructor)
    uint public endTime; // contribution end block (set in constructor)
    MelonToken public melonToken; // Contract of the ERC20 compliant MLN
    PolkaDotToken public polkaDotToken; // Contract of the ERC20 compliant DOT

    // Fields that can be changed by functions
    uint public etherRaisedLiquid; // this will keep track of the Ether raised for the liquid tranche during the contribution
    uint public etherRaisedIced; // this will keep track of the Ether raised for the iced tranche during the contribution
    uint public totalMintedTokens;
    bool public melonportAllocated; // this will change to true when melonport tokens are minted and allocated
    bool public halted; // the melonport address can set this to true to halt the contribution due to an emergency

    // EVENTS

    event IcedTokenBought(address indexed sender, uint eth, uint tokens);
    event LiquidTokenBought(address indexed sender, uint eth, uint tokens);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        _;
    }

    modifier only_melonport {
        if (msg.sender != melonport) throw;
        _;
    }

    modifier only_btcs {
        if (msg.sender != btcs) throw;
        _;
    }

    modifier is_not_halted {
        if (halted) throw;
        _;
    }

    modifier iced_ether_cap_not_reached {
        if (safeAdd(etherRaisedIced, msg.value) > ICED_ETHER_CAP) throw;
        _;
    }

    modifier liquid_ether_cap_not_reached {
        if (safeAdd(etherRaisedLiquid, msg.value) > LIQUID_ETHER_CAP) throw;
        _;
    }

    modifier btcs_ether_cap_not_reached {
        if (safeAdd(etherRaisedIced, msg.value) > BTCS_ETHER_CAP) throw;
        _;
    }

    modifier melonport_not_allocated {
        if (melonportAllocated) throw;
        _;
    }

    modifier melonport_is_allocated {
        if (!melonportAllocated) throw;
        _;
    }

    modifier now_at_least(uint x) {
        if (now < x) throw;
        _;
    }

    modifier now_past(uint x) {
        if (now <= x) throw;
        _;
    }

    modifier now_at_most(uint x) {
        if (now > x) throw;
        _;
    }

    // CONSTANT METHODS

    /// Pre: startTime, endTime specified in constructor,
    /// Post: Liquid rate in m{MLN+DOT}/ETH, where 1 MLN == 1000 mMLN, 1 DOT == 1000 mDOT
    function liquidRate() constant returns (uint) {
        // Four liquid tiers
        if (startTime <= now && now < startTime + 2 weeks)
            return 1075;
        if (startTime + 2 weeks <= now && now < startTime + 4 weeks)
            return 1050;
        if (startTime + 4 weeks <= now && now < startTime + 6 weeks)
            return 1025;
        if (startTime + 6 weeks <= now && now < endTime)
            return 1000;
        // Before or after contribution period
        return 0;
    }

    function forMelon(uint contributionAmount) constant returns (uint) { return 1 * contributionAmount / 3; }

    function forPolkaDot(uint contributionAmount) constant returns (uint) { return 2 * contributionAmount / 3; }

    // NON-CONSTANT METHODS

    /// Pre: ALL fields, except { melonport, parity, btcs, signer, startTime } are valid
    /// Post: All fields, including { melonport, parity, btcs, signer, startTime } are valid
    function Contribution(address melonportInput, address parityInput, address btcsInput, address signerInput, uint startTimeInput) {
        melonport = melonportInput;
        parity = parityInput;
        btcs = btcsInput;
        signer = signerInput;
        startTime = startTimeInput;
        endTime = startTimeInput + 8 weeks;
        melonToken = new MelonToken(this, startTime); // Create Melon Token Contract
        polkaDotToken = new PolkaDotToken(this, startTime); // Create PolkaDot Token Contract
    }

    /// Pre: Generated signature (see Pre: text of buyLiquid())
    /// Post: Bought MLN and DPT tokens accoriding to ICED_RATE and msg.value of ICED tranche
    function buyIced(uint8 v, bytes32 r, bytes32 s) payable { buyIcedRecipient(msg.sender, v, r, s); }

    /// Pre: Generated signature (see Pre: text of buyLiquid()) for a specific address
    /// Post: Bought MLN and DOT tokens on behalf of recipient accoriding to ICED_RATE and msg.value of ICED tranche
    function buyIcedRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        now_at_least(startTime)
        now_at_most(endTime)
        is_not_halted
        iced_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, ICED_RATE) / UNIT; // rounded iced amount
        melonToken.mintIcedToken(recipient, forMelon(tokens));
        polkaDotToken.mintIcedToken(recipient, forPolkaDot(tokens));
        totalMintedTokens = safeAdd(totalMintedTokens, tokens);
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        if(!melonport.send(msg.value)) throw;
        IcedTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: Buy entry point. All contribution depositors must have read and accpeted the legal agreement on
    ///  https://contribution.melonport.com. By doing so they receive the signature sig.v, sig.r and sig.s needed to contribute.
    /// Post: Bought MLN and DOT tokens accoriding to liquidRate() and msg.value of LIQUID tranche
    function buyLiquid(uint8 v, bytes32 r, bytes32 s) payable { buyLiquidRecipient(msg.sender, v, r, s); }

    /// Pre: Generated signature (see Pre: text of buyLiquid()) for a specific address
    /// Post: Bought MLN and DOT tokens on behalf of recipient accoriding to liquidRate() and msg.value of LIQUID tranche
    function buyLiquidRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        now_at_least(startTime)
        now_at_most(endTime)
        is_not_halted
        liquid_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, liquidRate()) / UNIT;
        melonToken.mintLiquidToken(recipient, forMelon(tokens));
        polkaDotToken.mintLiquidToken(recipient, forPolkaDot(tokens));
        totalMintedTokens = safeAdd(totalMintedTokens, tokens);
        etherRaisedLiquid = safeAdd(etherRaisedLiquid, msg.value);
        if(!melonport.send(msg.value)) throw;
        LiquidTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: BTCS only before contribution period, BTCS has exclusiv right to buy up to 25% of all tokens
    /// Post: BTCS bought MLN and DPT tokens accoriding to ICED_RATE and msg.value of ICED tranche
    function btcsBuyIcedRecipient(address recipient)
        payable
        only_btcs
        now_at_most(startTime)
        is_not_halted
        btcs_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, ICED_RATE) / UNIT; // rounded iced amount
        melonToken.mintIcedToken(recipient, forMelon(tokens));
        polkaDotToken.mintIcedToken(recipient, forPolkaDot(tokens));
        totalMintedTokens = safeAdd(totalMintedTokens, tokens);
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        if(!melonport.send(msg.value)) throw;
        IcedTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: Melonport only once, after contribution period
    /// Post: Melonport mints and allocates Melonport Stake
    function allocateMelonportStake()
        only_melonport
        now_past(endTime)
        melonport_not_allocated
    {
        uint melonportStake = totalMintedTokens * MELONPORT_PERCENT_STAKE / 100;
        /* Remark:
         *  i) Insert Allocation List here esp:
         *    a) Direct allocation for Melonport Founders and Advisors
         *  ii) Everything minted in illiquid tranche
         *  iii) Parity Stake minted to "this" address
         */
        melonportAllocated = true;
    }

    /// Pre: Melonport only once, after contribution period
    /// Post: Melonport mints and allocates Melonport Stake
    function allocateParityStake()
        only_melonport
        now_past(endTime)
        melonport_is_allocated
    {
        melonToken.transferAllCreatorToken(parity);
        polkaDotToken.transferAllCreatorToken(parity);
    }

    function halt() only_melonport { halted = true; }

    function unhalt() only_melonport { halted = false; }

    function changeCreator(address newCreator) only_melonport { melonport = newCreator; }

}
