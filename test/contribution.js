var async = require('async');
var assert = require('assert');
var BigNumber = require('bignumber.js');
var sha256 = require('js-sha256').sha256;

//Config
var startBlock = 2377200; //11-01-2016 midnight UTC assuming 14 second blocks
var endBlock = 2384400; //11-29-2016 midnight UTC assuming 14 second blocks


function sign(web3, address, value, callback) {
  web3.eth.sign(address, value, (err, sig) => {
    if (!err) {
      try {
        var r = sig.slice(0, 66);
        var s = '0x' + sig.slice(66, 130);
        var v = parseInt('0x' + sig.slice(130, 132), 16);
        if (sig.length<132) {
          //web3.eth.sign shouldn't return a signature of length<132, but if it does...
          sig = sig.slice(2);
          r = '0x' + sig.slice(0, 64);
          s = '0x00' + sig.slice(64, 126);
          v = parseInt('0x' + sig.slice(126, 128), 16);
        }
        if (v!=27 && v!=28) v+=27;
        callback(undefined, {r: r, s: s, v: v});
      } catch (err) {
        callback(err, undefined);
      }
    } else {
      callback(err, undefined);
    }
  });
}

contract('MelonToken', (accounts) => {
  //globals
  let contract;
  let contractAddress;
  var accounts;
  let testCases;
  const ETHER = new BigNumber(Math.pow(10,18));
  const mMLN = new BigNumber(Math.pow(10,15)); // 1 MLN == 1000 mMLN
  const founder = accounts[0];
  const signer = accounts[1];
  const FOUNDER_LOCKUP = 2252571;
  const TRANSFER_LOCKUP = 370285;

  before('Check accounts', (done) => {
    assert.equal(accounts.length, 10);
    done();
  });

  it('Deploy smart contract', (done) => {
    MelonToken_test.new(founder, signer, startBlock, endBlock).then((result) => {
      contract = result;
      contractAddress = contract.address;
      done();
    });
  });

});
