pragma solidity ^0.4.4;

import "./dependencies/SafeMath.sol";

/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Melonport AG <team@melonport.com>
/// @notice Inspired by Stefan George - <stefan.george@consensys.net>
contract MultiSigWallet is SafeMath {

    // TYPES

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        uint nonce;
        bool executed;
    }

    // FILEDS

    // Fields that can be changed by functions
    mapping (bytes32 => Transaction) public transactions;
    mapping (bytes32 => mapping (address => bool)) public confirmations;
    mapping (address => bool) public isOwner;
    address[] owners;
    bytes32[] transactionList;
    uint public requiredSignatures;

    // EVENTS

    event Confirmation(address sender, bytes32 transactionHash);
    event Revocation(address sender, bytes32 transactionHash);
    event Submission(bytes32 transactionHash);
    event Execution(bytes32 transactionHash);
    event Deposit(address sender, uint value);
    event OwnerAddition(address owner);
    event OwnerRemoval(address owner);
    event RequiredUpdate(uint requiredSignatures);

    // MODIFIERS

    modifier only_wallet {
        assert(msg.sender == address(this));
        _;
    }

    modifier is_owners_signature(bytes32 transactionHash, uint8[] v, bytes32[] rs) {
        for (uint i = 0; i < v.length; i++)
            assert(isOwner[ecrecover(transactionHash, v[i], rs[i], rs[v.length + i])]);
        _;
    }

    modifier is_owner(address owner) {
        assert(isOwner[owner]);
        _;
    }

    modifier is_not_owner(address owner) {
        assert(!isOwner[owner]);
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
        for (uint i = 0; i < owners.length; i++)
            if (confirmations[transactionHash][owners[i]])
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
        returns (bytes32[] _transactionList)
    {
        bytes32[] memory _transactionListTemp = new bytes32[](transactionList.length);
        uint count = 0;
        for (uint i = 0; i < transactionList.length; i++)
            if (   isPending && !transactions[transactionList[i]].executed
                || !isPending && transactions[transactionList[i]].executed)
            {
                _transactionListTemp[count] = transactionList[i];
                count += 1;
            }
        _transactionList = new bytes32[](count);
        for (i = 0; i < count; i++)
            if (_transactionListTemp[i] > 0)
                _transactionList[i] = _transactionListTemp[i];
    }

    // NON-CONSTANT EXTERNAL METHODS

    function addOwner(address owner)
        external
        only_wallet
        is_not_owner(owner)
    {
        isOwner[owner] = true;
        owners.push(owner);
        OwnerAddition(owner);
    }

    function removeOwner(address owner)
        external
        only_wallet
        is_owner(owner)
    {
        isOwner[owner] = false;
        for (uint i = 0; i < owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (requiredSignatures > owners.length)
            updateRequiredSignatures(owners.length);
        OwnerRemoval(owner);
    }

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

    function updateRequiredSignatures(uint required)
        only_wallet
        valid_amount_of_required_signatures(owners.length, required)
    {
        requiredSignatures = required;
        RequiredUpdate(requiredSignatures);
    }

    function confirmTransaction(bytes32 transactionHash)
        is_owner(msg.sender)
    {
        addConfirmation(transactionHash, msg.sender);
        executeTransaction(transactionHash);
    }

    function confirmTransactionWithSignatures(bytes32 transactionHash, uint8[] v, bytes32[] rs)
        is_owners_signature(transactionHash, v, rs)
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

    function MultiSigWallet(address[] setOwners, uint required)
        valid_amount_of_required_signatures(setOwners.length, required)
    {
        for (uint i = 0; i < setOwners.length; i++)
            isOwner[setOwners[i]] = true;
        owners = setOwners;
        requiredSignatures = required;
    }

    function() payable { Deposit(msg.sender, msg.value); }

}
