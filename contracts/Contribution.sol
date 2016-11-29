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
    uint public constant MIN_CONTRIBUTION_DURATION = 1 hours; // min amount in seconds of contribution period
    uint public constant MAX_CONTRIBUTION_DURATION = 8 weeks; // max amount in seconds of contribution period
    uint public constant MAX_TOTAL_TOKEN_AMOUNT = 1971000; // max amount of total tokens raised during contribution
    uint public constant ICED_ETHER_CAP = ETHER_CAP * 40 / 100 ; // iced means untradeable untill genesis blk or two years
    uint public constant LIQUID_ETHER_CAP = ETHER_CAP * 60 / 100; // liquid means tradeable
    uint public constant BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
    uint public constant MELONPORT_STAKE_MELON = 1200; // 12% of all created melon token allocated to melonport
    uint public constant MELONPORT_STAKE_DOT = 75; // 0.75% of all created dot token allocated to melonport
    uint public constant PARITY_STAKE_MELON = 300; // 3% of all created melon token minted to "this" contract
    uint public constant PARITY_STAKE_DOT = 1425; // 14.25% of all created dot token minted to "this" contract
    uint public constant DIVISOR_STAKE = 10000; // stakes are divided by this number; results to one basis point
    uint public constant ICED_RATE = 1125; // One iced tier, remains constant for the duration of the contribution
    uint public constant LIQUID_RATE_FIRST = 1075; // Four liquid tiers, each valid for two weeks
    uint public constant LIQUID_RATE_SECOND = 1050;
    uint public constant LIQUID_RATE_THIRD = 1025;
    uint public constant LIQUID_RATE_FOURTH = 1000;
    uint public constant DIVISOR_RATE = 1000; // price rates are divided by this number

    // Fields that are only changed in constructor
    address public melonport; // All deposited ETH will be instantly forwarded to this address.
    address public parity; // Token allocation for company
    address public btcs; // Bitcoin Suisse allocation option
    address public signer; // signer address see function() {} for comments
    uint public startTime; // contribution start time in seconds
    uint public minDurationTime; // contribution minimum duration in seconds
    uint public endTime; // contribution end time in seconds
    MelonToken public melonToken; // Contract of the ERC20 compliant MLN
    DotToken public dotToken; // Contract of the ERC20 compliant DOT

    // Fields that can be changed by functions
    uint public etherRaisedIced; // this will keep track of the Ether raised for the iced tranche during the contribution
    uint public etherRaisedLiquid; // this will keep track of the Ether raised for the liquid tranche during the contribution
    mapping (address => uint) etherIcedContributors; // how much a contributor contributed to the iced tier in ether
    mapping (address => uint) etherLiquidContributors; // how much a contributor contributed to the liquid tier in ether
    mapping (address => bool) isRefundedIced; // In the event of ether cap reached before min contribution period, contributors can refund excess amount
    mapping (address => bool) isRefundedLiquid; // In the event of ether cap reached before min contribution period, contributors can refund excess amount
    bool public excessCompanyTokenBurned; // this will change to true when melonport tokens are minted and allocated
    bool public halted; // the melonport address can set this to true to halt the contribution due to an emergency

    // EVENTS

    event IcedTokenBought(address indexed sender, uint eth, uint tokens);
    event LiquidTokenBought(address indexed sender, uint eth, uint tokens);

    // MODIFIERS

    modifier is_signer(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        assert(ecrecover(hash,v,r,s) == signer);
        _;
    }

    modifier only_melonport {
        assert(msg.sender == melonport);
        _;
    }

    modifier only_btcs {
        assert(msg.sender == btcs);
        _;
    }

    modifier is_not_halted {
        assert(!halted);
        _;
    }

    modifier iced_ether_cap_not_reached_or_now_before_min_duration {
        assert(safeAdd(etherRaisedIced, msg.value) <= ICED_ETHER_CAP || now < minDurationTime);
        _;
    }

    modifier raised_past_iced_ether_cap {
        assert(etherRaisedIced > ICED_ETHER_CAP);
        _;
    }

    modifier liquid_ether_cap_not_reached_or_now_before_min_duration {
        assert(safeAdd(etherRaisedLiquid, msg.value) <= LIQUID_ETHER_CAP || now < minDurationTime);
        _;
    }

    modifier raised_past_liquid_ether_cap {
        assert(etherRaisedLiquid > LIQUID_ETHER_CAP);
        _;
    }

    modifier btcs_ether_cap_not_reached {
        assert(safeAdd(etherRaisedIced, msg.value) <= BTCS_ETHER_CAP);
        _;
    }

    modifier excess_company_token_not_burned {
        assert(!excessCompanyTokenBurned);
        _;
    }

    modifier msg_sender_not_refunded_iced {
        assert(!isRefundedIced[msg.sender]);
        _;
    }

    modifier msg_sender_not_refunded_liquid {
        assert(!isRefundedLiquid[msg.sender]);
        _;
    }

    modifier now_at_least(uint x) {
        assert(now >= x);
        _;
    }

    modifier now_past(uint x) {
        assert(now > x);
        _;
    }

    modifier now_at_most(uint x) {
        assert(now <= x);
        _;
    }

    // CONSTANT METHODS

    /// Pre: startTime, endTime specified in constructor,
    /// Post: Liquid rate, one ether equals a combined total of liquidRate() / DIVISOR_RATE mln and dot tokens
    function liquidRate() constant returns (uint) {
        // Four liquid tiers
        if (startTime <= now && now < startTime + 2 weeks)
            return LIQUID_RATE_FIRST;
        if (startTime + 2 weeks <= now && now < startTime + 4 weeks)
            return LIQUID_RATE_SECOND;
        if (startTime + 4 weeks <= now && now < startTime + 6 weeks)
            return LIQUID_RATE_THIRD;
        if (startTime + 6 weeks <= now && now < endTime)
            return LIQUID_RATE_FOURTH;
        // Before or after contribution period
        return 0;
    }

    /// Pre: Amount contributed gets allocated in both melon and dot token
    /// Post: One third of the contribution amount is allocated to melon token
    function oneThirdOf(uint amount) constant returns (uint) { return 1 * amount / 3; }

    /// Pre: Amount contributed gets allocated in both melon and dot token
    /// Post: Two thirds of the contribution amount is allocated to dot token
    function twoThirdsOf(uint amount) constant returns (uint) { return 2 * amount / 3; }

    // NON-CONSTANT METHODS

    /// Pre: ALL fields, except { melonport, parity, btcs, signer, startTime } are valid
    /// Post: All fields, including { melonport, parity, btcs, signer, startTime } are valid
    function Contribution(address melonportInput, address parityInput, address btcsInput, address signerInput, uint startTimeInput) {
        melonport = melonportInput;
        parity = parityInput;
        btcs = btcsInput;
        signer = signerInput;
        startTime = startTimeInput;
        minDurationTime = startTime + MIN_CONTRIBUTION_DURATION;
        endTime = startTime + MAX_CONTRIBUTION_DURATION;
        melonToken = new MelonToken(this, startTime, endTime); // Create Melon Token Contract
        dotToken = new DotToken(this, startTime, endTime); // Create Dot Token Contract
        // Mint melon and dot token and allocate stakes to companies
        uint maxMelonSupply = oneThirdOf(MAX_TOTAL_TOKEN_AMOUNT);
        melonToken.mintIcedToken(melonport, maxMelonSupply * MELONPORT_STAKE_MELON / DIVISOR_STAKE);
        melonToken.mintIcedToken(parity, maxMelonSupply * PARITY_STAKE_MELON / DIVISOR_STAKE);
        uint maxDotSupply = twoThirdsOf(MAX_TOTAL_TOKEN_AMOUNT);
        dotToken.mintIcedToken(melonport, maxDotSupply * MELONPORT_STAKE_DOT / DIVISOR_STAKE);
        dotToken.mintIcedToken(parity, maxDotSupply * PARITY_STAKE_DOT / DIVISOR_STAKE);
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
        iced_ether_cap_not_reached_or_now_before_min_duration
    {
        uint tokens = safeMul(msg.value, ICED_RATE) / DIVISOR_RATE;
        melonToken.mintIcedToken(recipient, oneThirdOf(tokens));
        dotToken.mintIcedToken(recipient, twoThirdsOf(tokens));
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        assert(melonport.send(msg.value));
        etherIcedContributors[msg.sender] = safeAdd(etherIcedContributors[msg.sender], msg.value);
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
        liquid_ether_cap_not_reached_or_now_before_min_duration
    {
        uint tokens = safeMul(msg.value, liquidRate()) / DIVISOR_RATE;
        melonToken.mintLiquidToken(recipient, oneThirdOf(tokens));
        dotToken.mintLiquidToken(recipient, twoThirdsOf(tokens));
        etherRaisedLiquid = safeAdd(etherRaisedLiquid, msg.value);
        assert(melonport.send(msg.value));
        etherLiquidContributors[msg.sender] = safeAdd(etherLiquidContributors[msg.sender], msg.value);
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
        melonToken.mintIcedToken(recipient, oneThirdOf(tokens));
        dotToken.mintIcedToken(recipient, twoThirdsOf(tokens));
        etherRaisedIced = safeAdd(etherRaisedIced, msg.value);
        assert(melonport.send(msg.value));
        IcedTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: Anybody can trigger this but only once and only after contribution period
    /// Post: This burns of all to excess tokens created and allocated to the respective companies at contract creation
    function burnCompanyExcessToken()
        now_past(endTime)
        excess_company_token_not_burned
    {
        // Calculate differences for melon token allocation to companies
        uint maxMelonSupply = oneThirdOf(MAX_TOTAL_TOKEN_AMOUNT); // Max melon token amount
        uint melonSupply = melonToken.totalSupply(); // Actual melon token amount
        assert(melonSupply < maxMelonSupply); // Assert that not all melon tokens have been sold
        uint melonExcessAmount = maxMelonSupply - melonSupply; // Difference between the two above
        // Calculate differences for dot token allocation to companies
        uint maxDotSupply = twoThirdsOf(MAX_TOTAL_TOKEN_AMOUNT); // Max dot token amount
        uint dotSupply = dotToken.totalSupply(); // Actual dot token amount
        assert(dotSupply < maxDotSupply); // Assert that not all dot tokens have been sold
        uint dotExcessAmount = maxDotSupply - dotSupply; // Diffrence between the two above
        // Let there be fire
        melonToken.burnCompanyToken(melonport, melonExcessAmount * MELONPORT_STAKE_MELON / DIVISOR_STAKE);
        melonToken.burnCompanyToken(parity, melonExcessAmount * PARITY_STAKE_MELON / DIVISOR_STAKE);
        dotToken.burnCompanyToken(melonport, dotExcessAmount * MELONPORT_STAKE_DOT / DIVISOR_STAKE);
        dotToken.burnCompanyToken(parity, dotExcessAmount * PARITY_STAKE_DOT / DIVISOR_STAKE);
        excessCompanyTokenBurned = true;
    }

    // Pre: Contributor only once, after contribution period if more contributions received than ICED_ETHER_CAP
    // Post: Refunds the excess amount received proportionally with ether amount contributed by Contributor
    function refund_iced()
        now_past(endTime)
        raised_past_iced_ether_cap
        msg_sender_not_refunded_iced
    {
        address contributor = msg.sender;
        uint etherExcessAmount = etherRaisedIced - ICED_ETHER_CAP;
        uint refundAmount = etherExcessAmount * etherIcedContributors[contributor] / ICED_ETHER_CAP;
        assert(contributor.send(refundAmount));
        isRefundedIced[contributor] = true;
    }

    // Pre: Contributor only once, after contribution period if more contributions received than LIQUID_ETHER_CAP
    // Post: Refunds the excess amount received proportionally with ether amount contributed by Contributor
    function refund_liquid()
        now_past(endTime)
        raised_past_liquid_ether_cap
        msg_sender_not_refunded_liquid
    {
        address contributor = msg.sender;
        uint etherExcessAmount = etherRaisedLiquid - LIQUID_ETHER_CAP;
        uint refundAmount = etherExcessAmount * etherLiquidContributors[contributor] / LIQUID_ETHER_CAP;
        assert(contributor.send(refundAmount));
        isRefundedLiquid[contributor] = true;
    }

    function halt() only_melonport { halted = true; }

    function unhalt() only_melonport { halted = false; }

    function changeMelonportAddress(address newAddress) only_melonport { melonport = newAddress; }
}
