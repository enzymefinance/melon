pragma solidity ^0.4.4;

import "./dependencies/SafeMath.sol";
import "./dependencies/ERC20.sol";
import "./tokens/MelonVoucher.sol";

/// @title Contribution Contract
/// @author Melonport AG <team@melonport.com>
/// @notice This follows Condition-Orientated Programming as outlined here:
/// @notice   https://medium.com/@gavofyork/condition-orientated-programming-969f6ba0161a#.saav3bvva
contract Contribution is SafeMath {

    // FILEDS

    // Constant fields
    uint public constant ETHER_CAP = 250000 ether; // Max amount raised during first contribution; targeted amount CHF 2.5MN
    uint public constant MAX_CONTRIBUTION_DURATION = 4 weeks; // Max amount in seconds of contribution period
    uint public constant BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // Max melon voucher allocation for btcs before contribution period starts
    // Price Rates
    uint public constant PRICE_RATE_FIRST = 2000; // Four price tiers, each valid for two weeks
    uint public constant PRICE_RATE_SECOND = 1950;
    uint public constant PRICE_RATE_THIRD = 1900;
    uint public constant PRICE_RATE_FOURTH = 1850;
    uint public constant DIVISOR_PRICE = 1000; // Price rates are divided by this number
    // Addresses of Patrons
    address public constant FOUNDER_ONE = 0xF1;
    address public constant FOUNDER_TWO = 0xF2;
    address public constant EXT_COMPANY_ONE = 0xC1;
    address public constant EXT_COMPANY_TWO = 0xC2;
    address public constant ADVISOR_ONE = 0xA1;
    address public constant ADVISOR_TWO = 0xA2;
    // Stakes of Patrons
    uint public constant MELONPORT_COMPANY_STAKE = 1000; // 10% of all created melon voucher allocated to melonport company
    uint public constant EXT_COMPANY_STAKE_ONE = 300; // 3% of all created melon voucher allocated to external company
    uint public constant EXT_COMPANY_STAKE_TWO = 100; // 1% of all created melon voucher allocated to external company
    uint public constant FOUNDER_STAKE = 450; // 4.5% of all created melon voucher allocated to founder
    uint public constant ADVISOR_STAKE_ONE = 50; // 0.5% of all created melon voucher allocated to advisor
    uint public constant ADVISOR_STAKE_TWO = 25; // 0.25% of all created melon voucher allocated to advisor
    uint public constant DIVISOR_STAKE = 10000; // Stakes are divided by this number; Results to one basis point

    // Fields that are only changed in constructor
    address public melonport; // All deposited ETH will be instantly forwarded to this address.
    address public btcs; // Bitcoin Suisse address for their allocation option
    address public signer; // Signer address as on https://contribution.melonport.com
    uint public startTime; // Contribution start time in seconds
    uint public endTime; // Contribution end time in seconds
    MelonVoucher public melonVoucher; // Contract of the ERC20 compliant melon voucher

    // Fields that can be changed by functions
    uint public etherRaised; // This will keep track of the Ether raised during the contribution
    bool public halted; // The melonport address can set this to true to halt the contribution due to an emergency

    // EVENTS

    event VouchersBought(address indexed sender, uint eth, uint amount);

    // MODIFIERS

    modifier is_signer_signature(uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        assert(ecrecover(hash, v, r, s) == signer);
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

    modifier ether_cap_not_reached {
        assert(safeAdd(etherRaised, msg.value) <= ETHER_CAP);
        _;
    }

    modifier btcs_ether_cap_not_reached {
        assert(safeAdd(etherRaised, msg.value) <= BTCS_ETHER_CAP);
        _;
    }

    modifier is_not_earlier_than(uint x) {
        assert(now >= x);
        _;
    }

    modifier is_earlier_than(uint x) {
        assert(now < x);
        _;
    }

    // CONSTANT METHODS

    /// Pre: startTime, endTime specified in constructor,
    /// Post: Price rate at given blockTime; One ether equals priceRate() / DIVISOR_PRICE of melon vouchers
    function priceRate() constant returns (uint) {
        // Four price tiers
        if (startTime <= now && now < startTime + 1 weeks)
            return PRICE_RATE_FIRST;
        if (startTime + 1 weeks <= now && now < startTime + 2 weeks)
            return PRICE_RATE_SECOND;
        if (startTime + 2 weeks <= now && now < startTime + 3 weeks)
            return PRICE_RATE_THIRD;
        if (startTime + 3 weeks <= now && now < endTime)
            return PRICE_RATE_FOURTH;
        // Should not be called before or after contribution period
        assert(false);
    }

    // NON-CONSTANT METHODS

    /// Pre: All fields, except { melonport, btcs, signer, startTime } are valid
    /// Post: All fields, including { melonport, btcs, signer, startTime } are valid
    function Contribution(address setMelonport, address setBTCS, address setSigner, uint setStartTime) {
        melonport = setMelonport;
        btcs = setBTCS;
        signer = setSigner;
        startTime = setStartTime;
        endTime = startTime + MAX_CONTRIBUTION_DURATION;
        melonVoucher = new MelonVoucher(this, melonport, startTime, endTime); // Create Melon Voucher Contract
        var maxTotalVoucherAmount = melonVoucher.MAX_TOTAL_VOUCHER_AMOUNT();
        // Mint liquid vouchers for melonport company, liquid means tradeale
        melonVoucher.mintLiquidVoucher(melonport, MELONPORT_COMPANY_STAKE * maxTotalVoucherAmount / DIVISOR_STAKE);
        // Mint iced vouchers that are unable to trade for two years and allocate according to relevant stakes
        melonVoucher.mintIcedVoucher(FOUNDER_ONE, FOUNDER_STAKE * maxTotalVoucherAmount / DIVISOR_STAKE);
        melonVoucher.mintIcedVoucher(FOUNDER_TWO, FOUNDER_STAKE * maxTotalVoucherAmount / DIVISOR_STAKE);
        melonVoucher.mintIcedVoucher(EXT_COMPANY_ONE, EXT_COMPANY_STAKE_ONE * maxTotalVoucherAmount / DIVISOR_STAKE);
        melonVoucher.mintIcedVoucher(EXT_COMPANY_TWO, EXT_COMPANY_STAKE_TWO * maxTotalVoucherAmount / DIVISOR_STAKE);
        melonVoucher.mintIcedVoucher(ADVISOR_ONE, ADVISOR_STAKE_ONE * maxTotalVoucherAmount / DIVISOR_STAKE);
        melonVoucher.mintIcedVoucher(ADVISOR_TWO, ADVISOR_STAKE_TWO * maxTotalVoucherAmount / DIVISOR_STAKE);
    }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought melon vouchers according to priceRate() and msg.value
    function buy(uint8 v, bytes32 r, bytes32 s) payable { buyRecipient(msg.sender, v, r, s); }

    /// Pre: Valid signature received from https://contribution.melonport.com
    /// Post: Bought melon vouchers according to priceRate() and msg.value on behalf of recipient
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s)
        payable
        is_signer_signature(v, r, s)
        is_not_earlier_than(startTime)
        is_earlier_than(endTime)
        is_not_halted
        ether_cap_not_reached
    {
        uint amount = safeMul(msg.value, priceRate()) / DIVISOR_PRICE;
        melonVoucher.mintLiquidVoucher(recipient, amount);
        etherRaised = safeAdd(etherRaised, msg.value);
        assert(melonport.send(msg.value));
        VouchersBought(recipient, msg.value, amount);
    }

    /// Pre: BTCS before contribution period, BTCS has exclusive right to buy up to 25% of all melon vouchers
    /// Post: Bought melon vouchers according to PRICE_RATE_FIRST and msg.value on behalf of recipient
    function btcsBuyRecipient(address recipient)
        payable
        only_btcs
        is_earlier_than(startTime)
        is_not_halted
        btcs_ether_cap_not_reached
    {
        uint amount = safeMul(msg.value, PRICE_RATE_FIRST) / DIVISOR_PRICE;
        melonVoucher.mintLiquidVoucher(recipient, amount);
        etherRaised = safeAdd(etherRaised, msg.value);
        assert(melonport.send(msg.value));
        VouchersBought(recipient, msg.value, amount);
    }

    /// Pre: Emergency situation that requires contribution period to stop.
    /// Post: Contributing not possible anymore.
    function halt() only_melonport { halted = true; }

    /// Pre: Emergency situation resolved.
    /// Post: Contributing becomes possible again withing the outlined restrictions.
    function unhalt() only_melonport { halted = false; }

    /// Pre: Restricted to melonport.
    /// Post: New address set. To halt contribution and/or change minter in MelonVoucher contract.
    function changeMelonportAddress(address newAddress) only_melonport { melonport = newAddress; }
}
