pragma solidity ^0.4.8;

import "./dependencies/Assertive.sol";

/// @title Simple multi signature contract
/// @author Melonport AG <team@melonport.com>
/// @notice Allows multiple owners to agree on any given transaction before execution
/// @notice Inspired by https://github.com/ethereum/dapp-bin/blob/master/wallet/wallet.sol
/// @notice Only to be used with Ethereum addresses that are used uniquely for this Multi Sig Wallet!
contract MultiSigWallet is Assertive {

    // TYPES

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        uint nonce;
        bool executed;
    }

    // FIELDS

    // Fields that are only changed in constructor
    address[] multiSigOwners; // Addresses with signing authority
    mapping (address => bool) public isMultiSigOwner; // Has address siging authority
    uint public requiredSignatures; // Number of required signatures to execute a transaction

    // Fields that can be changed by functions
    bytes32[] transactionList; // Array of transactions hashes
    mapping (bytes32 => Transaction) public transactions; // Maps transaction hash [bytes32] to a Transaction [struct]
    mapping (bytes32 => mapping (address => bool)) public confirmations; // Whether [bool] transaction hash [bytes32] has been confirmed by owner [address]

    // EVENTS

    event Confirmation(address sender, bytes32 txHash);
    event Revocation(address sender, bytes32 txHash);
    event Submission(bytes32 txHash);
    event Execution(bytes32 txHash);
    event Deposit(address sender, uint value);

    // MODIFIERS

    modifier only_multi_sig_owner {
        assert(isMultiSigOwner[msg.sender]);
        _;
    }

    modifier owner_has_confirmed(bytes32 txHash, address owner) {
        assert(confirmations[txHash][owner]);
        _;
    }

    modifier owner_has_not_confirmed(bytes32 txHash, address owner) {
        assert(!confirmations[txHash][owner]);
        _;
    }

    modifier transaction_is_not_executed(bytes32 txHash) {
        assert(!transactions[txHash].executed);
        _;
    }

    modifier address_not_null(address destination) {
        assert(destination != 0);
        _;
    }

    modifier valid_amount_of_required_signatures(uint ownerCount, uint required) {
        assert(required != 0);
        assert(required <= ownerCount);
        _;
    }

    modifier transaction_is_confirmed(bytes32 txHash) {
        assert(isConfirmed(txHash));
        _;
    }

    // CONSTANT METHODS

    function isConfirmed(bytes32 txHash) constant returns (bool)
    {
        uint count = 0;
        // TODO check i += 1
        for (uint i = 0; i < multiSigOwners.length && count < requiredSignatures; i += 1)
            if (confirmations[txHash][multiSigOwners[i]])
                count += 1;
        return requiredSignatures <= count;
    }

    function getPendingTransactions() constant returns (bytes32[]) { return filterTransactions(true); }

    function getExecutedTransactions() constant returns (bytes32[]) { return filterTransactions(false); }

    function filterTransactions(bool isPending) constant returns (bytes32[] transactionListFiltered)
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

    // NON-CONSTANT INTERNAL METHODS

    /// Pre: Transaction has not already been submitted
    /// Post: New transaction in transactions and transactionList fields
    function addTransaction(address destination, uint value, bytes data, uint nonce)
        internal
        address_not_null(destination)
        returns (bytes32 txHash)
    {
        txHash = sha3(destination, value, data, nonce);
        if (transactions[txHash].destination == 0) {
            transactions[txHash] = Transaction({
                destination: destination,
                value: value,
                data: data,
                nonce: nonce,
                executed: false
            });
            transactionList.push(txHash);
            Submission(txHash);
        }
    }

    /// Pre: Transaction has not already been approved by msg.sender
    /// Post: Transaction w transaction hash: txHash approved by msg.sender
    function addConfirmation(bytes32 txHash, address owner)
        internal
        owner_has_not_confirmed(txHash, owner)
    {
        confirmations[txHash][owner] = true;
        Confirmation(owner, txHash);
    }

    // NON-CONSTANT PUBLIC METHODS

    /// Pre: Multi sig owner; Transaction has not already been submited
    /// Post: Propose and confirm transaction parameters for multi sig owner (msg.sender)
    function submitTransaction(address destination, uint value, bytes data, uint nonce)
        returns (bytes32 txHash)
    {
        txHash = addTransaction(destination, value, data, nonce);
        confirmTransaction(txHash);
    }

    /// Pre: Multi sig owner
    /// Post: Confirm approval to execute transaction
    function confirmTransaction(bytes32 txHash)
        only_multi_sig_owner
    {
        addConfirmation(txHash, msg.sender);
        if (isConfirmed(txHash))
            executeTransaction(txHash);
    }

    /// Pre: Multi sig owner who has confirmed pending transaction
    /// Post: Revokes approval of multi sig owner
    function revokeConfirmation(bytes32 txHash)
        only_multi_sig_owner
        owner_has_confirmed(txHash, msg.sender)
        transaction_is_not_executed(txHash)
    {
        confirmations[txHash][msg.sender] = false;
        Revocation(msg.sender, txHash);
    }

    /// Pre: Multi sig owner quorum has been reached
    /// Post: Executes transaction from this contract account
    function executeTransaction(bytes32 txHash)
        transaction_is_not_executed(txHash)
        transaction_is_confirmed(txHash)
    {
        Transaction tx = transactions[txHash];
        tx.executed = true;
        assert(tx.destination.call.value(tx.value)(tx.data));
        Execution(txHash);
    }

    /// Pre: All fields, except { multiSigOwners, requiredSignatures } are valid
    /// Post: All fields, including { multiSigOwners, requiredSignatures } are valid
    function MultiSigWallet(address[] setOwners, uint setRequiredSignatures)
        valid_amount_of_required_signatures(setOwners.length, setRequiredSignatures)
    {
        for (uint i = 0; i < setOwners.length; i++)
            isMultiSigOwner[setOwners[i]] = true;
        multiSigOwners = setOwners;
        requiredSignatures = setRequiredSignatures;
    }

    /// Pre: All fields, including { multiSigOwners, requiredSignatures } are valid
    /// Post: Received sent funds into wallet
    function() payable { Deposit(msg.sender, msg.value); }
}
