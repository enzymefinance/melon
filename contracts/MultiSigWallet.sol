pragma solidity ^0.4.4;

import "./dependencies/Assertive.sol";

/// @title Simple multi signature contract
/// @author Melonport AG <team@melonport.com>
/// @notice Allows multiple parties to agree on transactions before execution
contract MultiSigWallet is Assertive {

    // TYPES

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        uint nonce;
        bool executed;
    }

    // FILEDS

    // Fields that are only changed in constructor
    address[] multiSigOwners;
    mapping (address => bool) public isMultiSigOwner;
    uint public requiredSignatures;

    // Fields that can be changed by functions
    bytes32[] transactionList; // Array of transactions hashes
    mapping (bytes32 => Transaction) public transactions; // Maps transaction hash to transaction struct
    mapping (bytes32 => mapping (address => bool)) public confirmations;

    // EVENTS

    event Confirmation(address sender, bytes32 transactionHash);
    event Revocation(address sender, bytes32 transactionHash);
    event Submission(bytes32 transactionHash);
    event Execution(bytes32 transactionHash);
    event Deposit(address sender, uint value);

    // MODIFIERS

    modifier is_multi_sig_owners_signature(bytes32 transactionHash, uint8[] v, bytes32[] rs) {
        for (uint i = 0; i < v.length; i++)
            assert(isMultiSigOwner[ecrecover(transactionHash, v[i], rs[i], rs[v.length + i])]);
        _;
    }

    modifier is_owner(address owner) {
        assert(isMultiSigOwner[owner]);
        _;
    }

    modifier is_confirmed(bytes32 transactionHash, address owner) {
        //TODO use msg.sender
        assert(confirmations[transactionHash][owner]);
        _;
    }

    modifier is_not_confirmed(bytes32 transactionHash, address owner) {
        //TODO use msg.sender
        assert(!confirmations[transactionHash][owner]);
        _;
    }

    modifier transaction_is_not_executed(bytes32 transactionHash) {
        assert(!transactions[transactionHash].executed);
        _;
    }

    modifier address_not_null(address destination) {
        //TODO: Test empty input
        assert(destination != 0);
        _;
    }

    modifier valid_amount_of_required_signatures(uint ownerCount, uint required) {
        assert(ownerCount != 0);
        assert(required != 0);
        assert(required <= ownerCount);
        _;
    }

    modifier transaction_is_approved(bytes32 transactionHash) {
        assert(requiredSignatures <= confirmationCount(transactionHash));
        _;
    }

    // CONSTANT METHODS

    function confirmationCount(bytes32 transactionHash) constant returns (uint count)
    {
        for (uint i = 0; i < multiSigOwners.length; i++)
            if (confirmations[transactionHash][multiSigOwners[i]])
                count += 1;
    }

    function isConfirmed(bytes32 transactionHash) constant returns (bool) { return requiredSignatures <= confirmationCount(transactionHash); }

    function getPendingTransactions() external constant returns (bytes32[]) { return filterTransactions(true); }

    function getExecutedTransactions() external constant returns (bytes32[]) { return filterTransactions(false); }

    // NON-CONSTANT INTERNAL METHODS

    function addTransaction(address destination, uint value, bytes data, uint nonce)
        private
        address_not_null(destination)
        returns (bytes32 transactionHash)
    {
        transactionHash = sha3(destination, value, data, nonce);
        if (transactions[transactionHash].destination == 0) {
            transactions[transactionHash] = Transaction({
                destination: destination,
                value: value,
                data: data,
                nonce: nonce,
                executed: false
            });
            transactionList.push(transactionHash);
            Submission(transactionHash);
        }
    }

    function addConfirmation(bytes32 transactionHash, address owner)
        private
        is_not_confirmed(transactionHash, owner)
    {
        confirmations[transactionHash][owner] = true;
        Confirmation(owner, transactionHash);
    }

    function filterTransactions(bool isPending)
        private
        returns (bytes32[] transactionListFiltered)
    {
        bytes32[] memory transactionListTemp = new bytes32[](transactionList.length);
        uint count = 0;
        for (uint i = 0; i < transactionList.length; i++)
            if (   isPending && !transactions[transactionList[i]].executed
                || !isPending && transactions[transactionList[i]].executed)
            {
                transactionListTemp[count] = transactionList[i];
                count += 1;
            }
        transactionListFiltered = new bytes32[](count);
        for (i = 0; i < count; i++)
            if (transactionListTemp[i] > 0)
                transactionListFiltered[i] = transactionListTemp[i];
    }

    // NON-CONSTANT EXTERNAL METHODS

    function submitTransaction(address destination, uint value, bytes data, uint nonce)
        external
        returns (bytes32 transactionHash)
    {
        transactionHash = addTransaction(destination, value, data, nonce);
        confirmTransaction(transactionHash);
    }

    function submitTransactionWithSignatures(address destination, uint value, bytes data, uint nonce, uint8[] v, bytes32[] rs)
        external
        returns (bytes32 transactionHash)
    {
        transactionHash = addTransaction(destination, value, data, nonce);
        confirmTransactionWithSignatures(transactionHash, v, rs);
    }

    // NON-CONSTANT PUBLIC METHODS

    function confirmTransaction(bytes32 transactionHash)
        is_owner(msg.sender)
    {
        addConfirmation(transactionHash, msg.sender);
        executeTransaction(transactionHash);
    }

    function confirmTransactionWithSignatures(bytes32 transactionHash, uint8[] v, bytes32[] rs)
        is_multi_sig_owners_signature(transactionHash, v, rs)
    {
        for (uint i = 0; i < v.length; i++)
            addConfirmation(transactionHash, ecrecover(transactionHash, v[i], rs[i], rs[i + v.length]));
        executeTransaction(transactionHash);
    }

    function revokeConfirmation(bytes32 transactionHash)
        external
        is_owner(msg.sender)
        is_confirmed(transactionHash, msg.sender)
        transaction_is_not_executed(transactionHash)
    {
        confirmations[transactionHash][msg.sender] = false;
        Revocation(msg.sender, transactionHash);
    }

    function executeTransaction(bytes32 transactionHash)
        transaction_is_not_executed(transactionHash)
        transaction_is_approved(transactionHash)
    {
        Transaction tx = transactions[transactionHash];
        tx.executed = true;
        assert(tx.destination.call.value(tx.value)(tx.data));
        Execution(transactionHash);
    }

    function MultiSigWallet(address[] setOwners, uint setRequiredSignatures)
        valid_amount_of_required_signatures(setOwners.length, setRequiredSignatures)
    {
        for (uint i = 0; i < setOwners.length; i++)
            isMultiSigOwner[setOwners[i]] = true;
        multiSigOwners = setOwners;
        requiredSignatures = setRequiredSignatures;
    }

    function() payable { Deposit(msg.sender, msg.value); }

}
