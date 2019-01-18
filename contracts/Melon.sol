pragma solidity ^0.4.24;

import "./openzeppelin/ERC20Burnable.sol";
import "./openzeppelin/ERC20Detailed.sol";
import "./openzeppelin/SafeMath.sol";

contract Melon is ERC20Burnable, ERC20Detailed {
    using SafeMath for uint;

    uint public constant BASE_UNITS = 10 ** 18;
    uint public constant INFLATION_ENABLE_DATE = 1551398400;
    uint public constant INITIAL_TOTAL_SUPPLY = uint(932613).mul(BASE_UNITS);
    uint public constant YEARLY_MINTABLE_AMOUNT = uint(300600).mul(BASE_UNITS);
    uint public constant MINTING_INTERVAL = 365 days;

    address public council;
    address public deployer;
    uint public lastMinting;
    bool public initialSupplyMinted;

    modifier onlyDeployer {
        require(msg.sender == deployer, "Only deployer can call this");
        _;
    }

    modifier onlyCouncil {
        require(msg.sender == council, "Only council can call this");
        _;
    }

    modifier anIntervalHasPassed {
        require(
            block.timestamp >= uint(lastMinting).add(MINTING_INTERVAL),
            "Please wait until an interval has passed"
        );
        _;
    }

    modifier inflationEnabled {
        require(
            block.timestamp >= INFLATION_ENABLE_DATE,
            "Inflation is not enabled yet"
        );
        _;
    }

    constructor(
        string _name,
        string _symbol,
        uint8 _decimals,
        address _council
    ) ERC20Detailed(_name, _symbol, _decimals) {
        deployer = msg.sender;
        council = _council;
    }

    function changeCouncil(address _newCouncil) public onlyCouncil {
        council = _newCouncil;
    }

    function mintInitialSupply(address _initialReceiver) public onlyDeployer {
        require(!initialSupplyMinted, "Initial minting already complete");
        _mint(_initialReceiver, INITIAL_TOTAL_SUPPLY);
        initialSupplyMinted = true;
    }

    function mintInflation() public anIntervalHasPassed inflationEnabled {
        require(initialSupplyMinted, "Initial minting not complete");
        lastMinting = block.timestamp;
        _mint(council, YEARLY_MINTABLE_AMOUNT);
    }
}
