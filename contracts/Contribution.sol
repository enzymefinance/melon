pragma solidity ^0.4.4;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken.sol";
import "./tokens/DotToken.sol";

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
    uint public constant MELONPORT_STAKE_MELON = 1200; // 12% of all created melon token allocated to melonport
    uint public constant MELONPORT_STAKE_DOT = 75; // 0.75% of all created dot token allocated to melonport
    uint public constant THIS_STAKE_MELON = 300; // 3% of all created melon token minted to "this" contract
    uint public constant THIS_STAKE_DOT = 1425; // 14.25% of all created dot token minted to "this" contract
    uint public constant DIVISOR_STAKE = 10**4; // stakes are divided by this number
    uint public constant ICED_RATE = 1125; // One iced tier, remains constant for the duration of the contribution
    uint public constant DIVISOR_RATE = 10**3; // price rates are divided by this number
    uint public constant MAX_CONTRIBUTION_DURATION = 8 weeks; // max amount in seconds of contribution period

    // Fields that are only changed in constructor
    address public melonport; // All deposited ETH will be instantly forwarded to this address.
    address public parity; // Token allocation for company
    address public btcs; // Bitcoin Suisse allocation option
    address public signer; // signer address see function() {} for comments
    uint public startTime; // contribution start block (set in constructor)
    uint public endTime; // contribution end block (set in constructor)
    MelonToken public melonToken; // Contract of the ERC20 compliant MLN
    DotToken public dotToken; // Contract of the ERC20 compliant DOT

    // Fields that can be changed by functions
    uint public etherRaisedLiquid; // this will keep track of the Ether raised for the liquid tranche during the contribution
    uint public etherRaisedIced; // this will keep track of the Ether raised for the iced tranche during the contribution
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
    /// Post: Liquid rate, one ether equals a combined total of liquidRate() / DIVISOR_RATE mln and dot tokens
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

    function forDot(uint contributionAmount) constant returns (uint) { return 2 * contributionAmount / 3; }

    // NON-CONSTANT METHODS

    /// Pre: ALL fields, except { melonport, parity, btcs, signer, startTime } are valid
    /// Post: All fields, including { melonport, parity, btcs, signer, startTime } are valid
    function Contribution(address melonportInput, address parityInput, address btcsInput, address signerInput, uint startTimeInput) {
        melonport = melonportInput;
        parity = parityInput;
        btcs = btcsInput;
        signer = signerInput;
        startTime = startTimeInput;
        endTime = startTimeInput + MAX_CONTRIBUTION_DURATION;
        melonToken = new MelonToken(this, startTime, endTime); // Create Melon Token Contract
        dotToken = new DotToken(this, startTime, endTime); // Create Dot Token Contract
    }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought mln and dot tokens of iced tranche accoriding to ICED_RATE and msg.value
    function buyIced(uint8 v, bytes32 r, bytes32 s) payable { buyIcedRecipient(msg.sender, v, r, s); }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought mln and dot tokens of iced tranche accoriding to ICED_RATE and msg.value on behalf of recipient
    function buyIcedRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        now_at_least(startTime)
        now_at_most(endTime)
        is_not_halted
        iced_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, ICED_RATE) / DIVISOR_RATE;
        melonToken.mintIcedToken(recipient, forMelon(tokens));
        dotToken.mintIcedToken(recipient, forDot(tokens));
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        if(!melonport.send(msg.value)) throw;
        IcedTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought mln and dot tokens of liquid tranche accoriding to liquidRate() and msg.value
    function buyLiquid(uint8 v, bytes32 r, bytes32 s) payable { buyLiquidRecipient(msg.sender, v, r, s); }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought mln and dot tokens of liquid tranche accoriding to liquidRate() and msg.value on behlf of recipient
    function buyLiquidRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        now_at_least(startTime)
        now_at_most(endTime)
        is_not_halted
        liquid_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, liquidRate()) / DIVISOR_RATE;
        melonToken.mintLiquidToken(recipient, forMelon(tokens));
        dotToken.mintLiquidToken(recipient, forDot(tokens));
        etherRaisedLiquid = safeAdd(etherRaisedLiquid, msg.value);
        if(!melonport.send(msg.value)) throw;
        LiquidTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: BTCS before contribution period, BTCS has exclusiv right to buy up to 25% of all tokens
    /// Post: Bought mln and dot tokens of iced tranche accoriding to ICED_RATE and msg.value on behalf of recipient
    function btcsBuyIcedRecipient(address recipient)
        payable
        only_btcs
        now_at_most(startTime)
        is_not_halted
        btcs_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, ICED_RATE) / DIVISOR_RATE;
        melonToken.mintIcedToken(recipient, forMelon(tokens));
        dotToken.mintIcedToken(recipient, forDot(tokens));
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        if(!melonport.send(msg.value)) throw;
        IcedTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: Melonport only once, after contribution period
    /// Post: Melonport mints all outstanding tokens and allocates Melonport and "this"
    function mintAndAllocateMelonportToken()
        only_melonport
        now_past(endTime)
        melonport_not_allocated
    {
        // Melon mint and allocate
        uint melonSupply = melonToken.totalSupply();
        melonToken.mintIcedToken(melonport, melonSupply * MELONPORT_STAKE_MELON / DIVISOR_STAKE);
        melonToken.mintIcedToken(this, melonSupply * THIS_STAKE_MELON / DIVISOR_STAKE);
        // Dot mint and allocate
        uint dotSupply = dotToken.totalSupply();
        dotToken.mintIcedToken(melonport, dotSupply * MELONPORT_STAKE_DOT / DIVISOR_STAKE);
        dotToken.mintIcedToken(this, dotSupply * THIS_STAKE_DOT / DIVISOR_STAKE);
        melonportAllocated = true;
    }

    /// Pre: Melonport only once, after contribution period
    /// Post: Melonport transfers all tokens from "this" to parity
    function transferParityToken()
        only_melonport
        now_past(endTime)
        melonport_is_allocated
    {
        melonToken.transferAllCreatorToken(parity);
        dotToken.transferAllCreatorToken(parity);
    }

    function halt() only_melonport { halted = true; }

    function unhalt() only_melonport { halted = false; }

    function changeCreator(address newCreator) only_melonport { melonport = newCreator; }

}
