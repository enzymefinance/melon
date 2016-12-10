pragma solidity ^0.4.4;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonToken.sol";

/// @title Contribution Contract
/// @author Melonport AG <team@melonport.com>
/// @notice This follows Condition-Orientated Programming as outlined here:
/// @notice   https://medium.com/@gavofyork/condition-orientated-programming-969f6ba0161a#.saav3bvva
contract Contribution is SafeMath {

    // FILEDS

    // Constant fields
    uint public constant ETHER_CAP = 250000 ether; // max amount raised during contribution
    uint public constant MAX_CONTRIBUTION_DURATION = 4 weeks; // max amount in seconds of contribution period
    uint public constant MAX_TOTAL_TOKEN_AMOUNT = 1250000; // max amount of total tokens raised during contribution
    uint public constant LIQUID_ETHER_CAP = ETHER_CAP * 100 / 100; // liquid means tradeable
    uint public constant BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
    uint public constant FOUNDER_STAKE = 450; // 4.5% of all created melon token allocated to melonport
    uint public constant EXT_COMPANY_STAKE_ONE = 300; // 3% of all created melon token allocated to melonport
    uint public constant EXT_COMPANY_STAKE_TWO = 100; // 3% of all created melon token allocated to melonport
    uint public constant ADVISOR_STAKE_ONE = 50; // 0.5% of all created melon token allocated to melonport
    uint public constant ADVISOR_STAKE_TWO = 25; // 0.25% of all created melon token allocated to melonport
    uint public constant DIVISOR_STAKE = 10000; // stakes are divided by this number; results to one basis point
    uint public constant ICED_RATE = 1125; // One iced tier, remains constant for the duration of the contribution
    uint public constant LIQUID_RATE_FIRST = 1075; // Four liquid tiers, each valid for two weeks
    uint public constant LIQUID_RATE_SECOND = 1050;
    uint public constant LIQUID_RATE_THIRD = 1025;
    uint public constant LIQUID_RATE_FOURTH = 1000;
    uint public constant DIVISOR_RATE = 1000; // price rates are divided by this number

    // Fields that are only changed in constructor
    address public melonport; // All deposited ETH will be instantly forwarded to this address.
    address public btcs; // Bitcoin Suisse allocation option
    address public signer; // signer address see function() {} for comments
    uint public startTime; // contribution start time in seconds
    uint public minDurationTime; // contribution minimum duration in seconds
    uint public endTime; // contribution end time in seconds
    MelonToken public melonToken; // Contract of the ERC20 compliant MLN

    // Fields that can be changed by functions
    uint public etherRaisedLiquid; // this will keep track of the Ether raised for the liquid tranche during the contribution
    bool public halted; // the melonport address can set this to true to halt the contribution due to an emergency

    // EVENTS

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

    modifier liquid_ether_cap_not_reached {
        assert(safeAdd(etherRaisedLiquid, msg.value) <= LIQUID_ETHER_CAP);
        _;
    }

    modifier btcs_ether_cap_not_reached {
        assert(safeAdd(etherRaisedLiquid, msg.value) <= BTCS_ETHER_CAP);
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
    /// Post: Liquid rate, one ether equals a combined total of liquidRate() / DIVISOR_RATE of melon tokens
    function liquidRate() constant returns (uint) {
        // Four liquid tiers
        if (startTime <= now && now < startTime + 1 weeks)
            return LIQUID_RATE_FIRST;
        if (startTime + 1 weeks <= now && now < startTime + 2 weeks)
            return LIQUID_RATE_SECOND;
        if (startTime + 2 weeks <= now && now < startTime + 3 weeks)
            return LIQUID_RATE_THIRD;
        if (startTime + 3 weeks <= now && now < endTime)
            return LIQUID_RATE_FOURTH;
        // Before or after contribution period
        return 0;
    }

    // NON-CONSTANT METHODS

    /// Pre: ALL fields, except { melonport, btcs, signer, startTime } are valid
    /// Post: All fields, including { melonport, btcs, signer, startTime } are valid
    function Contribution(address setMelonport, address setBTCS, address setSigner, uint setStartTime) {
        melonport = setMelonport;
        btcs = setBTCS;
        signer = setSigner;
        startTime = setStartTime;
        endTime = startTime + MAX_CONTRIBUTION_DURATION;
        melonToken = new MelonToken(this, startTime, endTime); // Create Melon Token Contract
        // Mint token and allocate stakes
        uint maxMelonSupply = MAX_TOTAL_TOKEN_AMOUNT;
        melonToken.mintIcedToken(0xF1, maxMelonSupply * FOUNDER_STAKE / DIVISOR_STAKE);
        melonToken.mintIcedToken(0xF2, maxMelonSupply * FOUNDER_STAKE / DIVISOR_STAKE);
        melonToken.mintIcedToken(0xC1, maxMelonSupply * EXT_COMPANY_STAKE_ONE / DIVISOR_STAKE);
        melonToken.mintIcedToken(0xC2, maxMelonSupply * EXT_COMPANY_STAKE_TWO / DIVISOR_STAKE);
        melonToken.mintIcedToken(0xA1, maxMelonSupply * ADVISOR_STAKE_ONE / DIVISOR_STAKE);
        melonToken.mintIcedToken(0xA2, maxMelonSupply * ADVISOR_STAKE_TWO / DIVISOR_STAKE);
    }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought melon tokens of liquid tranche accoriding to liquidRate() and msg.value
    function buyLiquid(uint8 v, bytes32 r, bytes32 s) payable { buyLiquidRecipient(msg.sender, v, r, s); }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought melon tokens of liquid tranche accoriding to liquidRate() and msg.value on behlf of recipient
    function buyLiquidRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer(v, r, s)
        now_at_least(startTime)
        now_at_most(endTime)
        is_not_halted
        liquid_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, liquidRate()) / DIVISOR_RATE;
        melonToken.mintLiquidToken(recipient, tokens);
        etherRaisedLiquid = safeAdd(etherRaisedLiquid, msg.value);
        assert(melonport.send(msg.value));
        LiquidTokenBought(recipient, msg.value, tokens);
    }

    /// Pre: BTCS before contribution period, BTCS has exclusiv right to buy up to 25% of all tokens
    /// Post: Bought melon tokens of liquid tranche accoriding to ICED_RATE and msg.value on behalf of recipient
    function btcsBuyLiquidRecipient(address recipient)
        payable
        only_btcs
        now_at_most(startTime)
        is_not_halted
        btcs_ether_cap_not_reached
    {
        uint tokens = safeMul(msg.value, liquidRate()) / DIVISOR_RATE;
        melonToken.mintLiquidToken(recipient, tokens);
        etherRaisedLiquid = safeAdd(etherRaisedLiquid, msg.value);
        assert(melonport.send(msg.value));
        LiquidTokenBought(recipient, msg.value, tokens);
    }

    function halt() only_melonport { halted = true; }

    function unhalt() only_melonport { halted = false; }

    function changeMelonportAddress(address newAddress) only_melonport { melonport = newAddress; }
}
