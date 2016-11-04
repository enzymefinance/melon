var async = require('async');
var assert = require('assert');
var BigNumber = require('bignumber.js');
var sha256 = require('js-sha256').sha256;

//Config
const startTime = 1477958400; // 11/01/2016 @ 12:00am (UTC)
const SECONDS_PER_WEEK = 604800; // 3600*24*7
const endTime = startTime + 8*SECONDS_PER_WEEK;

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

contract('Contribution', (accounts) => {
  //globals
  let contract;
  let melon_contract;
  let polkaDot_contract;
  let contractAddress;
  var accounts;
  let testCases;
  const ETHER = new BigNumber(Math.pow(10,18));
  const UNIT = 1000;
  const melonport = accounts[0];
  const parity = accounts[1];
  const btcs = accounts[2];
  const signer = accounts[3];
  const FOUNDER_LOCKUP = 2252571;
  const TRANSFER_LOCKUP = 370285;

  before('Check accounts', (done) => {
    assert.equal(accounts.length, 10);
    done();
  });

  it('Deploy smart contract', (done) => {
    Contribution.new(melonport, parity, btcs, signer, startTime).then((result) => {
      contract = result;
      contractAddress = contract.address;
      return contract.melonToken();
    }).then((result) => {
      melon_contract = MelonToken.at(result);
      return melon_contract.creator()
    }).then((result) => {
      return contract.polkaDotToken();
    }).then((result) => {
      polkaDot_contract = PolkaDotToken.at(result);
      done();
    });
  });

  it('Set up test cases', (done) => {
    testCases = [];
    const numBlocks = 8;
    for (i = 0; i < numBlocks; i++) {
      const blockNumber = Math.round(startTime + (endTime-startTime)*i/(numBlocks-1));
      let expectedPrice;
      if (blockNumber>=startTime && blockNumber<startTime + 2*SECONDS_PER_WEEK) {
        expectedPrice = 1075;
      } else if (blockNumber>=startTime + 2*SECONDS_PER_WEEK && blockNumber < startTime + 4*SECONDS_PER_WEEK) {
        expectedPrice = 1050;
      } else if (blockNumber>=startTime + 4*SECONDS_PER_WEEK && blockNumber < startTime + 6*SECONDS_PER_WEEK) {
        expectedPrice = 1025;
      } else if (blockNumber>=startTime + 6*SECONDS_PER_WEEK && blockNumber < startTime + 8*SECONDS_PER_WEEK) {
        expectedPrice = 1000;
      } else {
        expectedPrice = 0;
      }
      const accountNum = Math.max(1,Math.min(i+1, accounts.length-1));
      const account = accounts[accountNum];
      expectedPrice = Math.round(expectedPrice);
      testCases.push(
        {
          accountNum: accountNum,
          blockNumber: blockNumber,
          expectedPrice: expectedPrice,
          account: account,
        }
      );
    }
    done();
  });
  
  it('Should sign test cases', (done) => {
    async.mapSeries(testCases,
      function(testCase, callbackMap) {
        const hash = '0x' + sha256(new Buffer(testCase.account.slice(2),'hex'));
        sign(web3, signer, hash, (err, sig) => {
          testCase.v = sig.v;
          testCase.r = sig.r;
          testCase.s = sig.s;
          callbackMap(null, testCase);
        });
      },
      function(err, newTestCases) {
        testCases = newTestCases;
        done();
      }
    );
  });
  //
  // it('Test price', (done) => {
  //   async.eachSeries(testCases,
  //     function(testCase, callbackEach) {
  //       contract.setBlockNumber(testCase.blockNumber).then((result) => {
  //         return contract.testPrice();
  //       }).then((result) => {
  //         // console.log('result ' + result.toNumber() + ' expected ' + testCase.expectedPrice)
  //         assert.equal(result.toNumber(), testCase.expectedPrice);
  //         callbackEach();
  //       });
  //     },
  //     function(err) {
  //       done();
  //     }
  //   );
  // });
  //
  // it('Test buyLiquid(..)', (done) => {
  //   var amountToBuy = web3.toWei(4, "ether");
  //   var amountBought = new BigNumber(0);
  //   let melonAmountBought = 0;
  //   let polkaDotAmountBought = 0;
  //   web3.eth.getBalance(melonport, (err, result) => {
  //     var initialBalance = result;
  //     async.eachSeries(testCases,
  //       (testCase, callbackEach) => {
  //         contract.setBlockNumber(testCase.blockNumber, {from: testCase.account, value: 0}).then((result) => {
  //           return contract.buyLiquid(testCase.v, testCase.r, testCase.s, {from: testCase.account, value: amountToBuy});
  //         }).then((result) => {
  //           amountBought = amountBought.plus(new BigNumber(amountToBuy));
  //           return melon_contract.balanceOf(testCase.account);
  //         }).then((result) => {
  //           melonAmountBought = result;
  //           return polkaDot_contract.balanceOf(testCase.account);
  //         }).then((result) => {
  //           polkaDotAmountBought = result;
  //           tokenAmountBought = melonAmountBought.toNumber() + polkaDotAmountBought.toNumber();
  //           expectedResult = (new BigNumber(amountToBuy)).dividedBy(new BigNumber(UNIT)).times(new BigNumber(testCase.expectedPrice));
  //           // console.log(
  //           //   '\nstartTime: ' + startTime +
  //           //   '\nendTime: ' + endTime +
  //           //   '\nv: ' + testCase.v +
  //           //   '\nr: ' + testCase.r +
  //           //   '\ns: ' + testCase.s +
  //           //   '\n---------------- ' +
  //           //   '\ninitalBalance: ' + initialBalance +
  //           //   '\namountToBuy: ' + amountToBuy +
  //           //   '\nmelon balance: ' + melonAmountBought +
  //           //   '\npolkaDot balance: ' + polkaDotAmountBought +
  //           //   '\ntotal amount: ' + tokenAmountBought +
  //           //   '\nexpectedPrice: ' + testCase.expectedPrice +
  //           //   '\n---------------- ' +
  //           //   '\nexpectedResult: ' + expectedResult
  //           // );
  //           assert.equal(tokenAmountBought, expectedResult);
  //           callbackEach();
  //         });
  //       },
  //       (err) => {
  //         web3.eth.getBalance(melonport, (err, result) => {
  //           var finalBalance = result;
  //           assert.equal(finalBalance.minus(initialBalance).toNumber(), amountBought.toNumber());
  //           done();
  //         });
  //       }
  //     );
  //   });
  // });
  //
  // it('Test buying on behalf of a recipient', (done) => {
  //   var amountToBuy = web3.toWei(1, "ether");
  //   var initialBalance;
  //   var price;
  //   contract.setBlockNumber(endTime - 10, {from: accounts[0], value: 0}).then((result) => {
  //     return melon_contract.balanceOf(accounts[2]);
  //   }).then((result) => {
  //     initialBalance = result;
  //     const hash = '0x' + sha256(new Buffer(accounts[2].slice(2),'hex'));
  //     sign(web3, signer, hash, (err, sig) => {
  //       contract.buyLiquidRecipient(accounts[2], sig.v, sig.r, sig.s, {from: accounts[2], value: amountToBuy}).then((result) => {
  //         return contract.testPrice();
  //       }).then((result) => {
  //         price = result / UNIT;
  //         return melon_contract.balanceOf(accounts[2]);
  //       }).then((result) => {
  //         var finalBalance = result;
  //         // console.log(
  //         //   '\nfinalBalance: ' + finalBalance +
  //         //   '\ninitalBalance: ' + initialBalance +
  //         //   '\namountToBuy: ' + amountToBuy +
  //         //   '\nprice: ' + price
  //         // );
  //         //TODO for both tokens
  //         assert.equal(finalBalance.sub(initialBalance).toNumber(), (new BigNumber(amountToBuy).times(price).dividedBy(3)).toNumber());
  //         done();
  //       });
  //     });
  //   });
  // });
  //
  // it('Test buying w poorly fromed msg value', (done) => {
  //   var amountToBuy = 1001;
  //   var initialBalance;
  //   melon_contract.balanceOf(accounts[2]).then((result) => {
  //     initialBalance = result;
  //     const hash = '0x' + sha256(new Buffer(accounts[2].slice(2),'hex'));
  //     sign(web3, signer, hash, (err, sig) => {
  //       if (!err) {
  //         contract.buyLiquid(sig.v, sig.r, sig.s, {from: accounts[2], value: amountToBuy
  //         }).then((result) => {
  //           assert.fail();
  //         }).catch((err) => {
  //           assert.notEqual(err.name, 'AssertionError');
  //           melon_contract.balanceOf(accounts[2]).then((result) => {
  //             var finalBalance = result;
  //             assert.equal(finalBalance.sub(initialBalance).toNumber(), 0);
  //             done();
  //           });
  //         });
  //       } else {
  //         callback(err, undefined);
  //       }
  //     });
  //   });
  // });
  //
  // it('Test halting, buying, and failing', (done) => {
  //   var amountToBuy = web3.toWei(1, "ether");
  //   var initialBalance;
  //   melon_contract.balanceOf(accounts[2]).then((result) => {
  //     initialBalance = result;
  //     return contract.halt({from: melonport, value: 0});
  //   }).then((result) => {
  //     const hash = '0x' + sha256(new Buffer(accounts[2].slice(2),'hex'));
  //     sign(web3, signer, hash, (err, sig) => {
  //       if (!err) {
  //         contract.buyLiquid(sig.v, sig.r, sig.s, {from: accounts[2], value: amountToBuy
  //         }).then((result) => {
  //           assert.fail();
  //         }).catch((err) => {
  //           assert.notEqual(err.name, 'AssertionError');
  //           melon_contract.balanceOf(accounts[2]).then((result) => {
  //             var finalBalance = result;
  //             assert.equal(finalBalance.sub(initialBalance).toNumber(), 0);
  //             done();
  //           });
  //         });
  //       } else {
  //         callback(err, undefined);
  //       }
  //     });
  //   });
  // });
  //
  // it('Test unhalting, buying, and succeeding', (done) => {
  //   var amountToBuy = web3.toWei(1, "ether");
  //   var initialBalance;
  //   melon_contract.balanceOf(accounts[2]).then((result) => {
  //     initialBalance = result;
  //     return contract.unhalt({from: melonport, value: 0});
  //   }).then((result) => {
  //     const hash = '0x' + sha256(new Buffer(accounts[2].slice(2),'hex'));
  //     sign(web3, signer, hash, (err, sig) => {
  //       if (!err) {
  //         contract.buyLiquid(sig.v, sig.r, sig.s, {from: accounts[2], value: amountToBuy
  //         }).then((result) => {
  //           return melon_contract.balanceOf(accounts[2]);
  //         }).then((result) => {
  //           var finalBalance = result;
  //           //TODO for both tokens
  //           assert.equal(finalBalance.sub(initialBalance).toNumber(), amountToBuy / 3);
  //           done();
  //         });
  //       } else {
  //         callback(err, undefined);
  //       }
  //     });
  //   });
  // });
  //
  // it('Test buying after the sale ends', (done) => {
  //   contract.setBlockNumber(endTime + 1, {from: accounts[0], value: 0}).then((result) => {
  //     const hash = '0x' + sha256(new Buffer(accounts[2].slice(2),'hex'));
  //     sign(web3, signer, hash, (err, sig) => {
  //       if (!err) {
  //         contract.buyLiquid(sig.v, sig.r, sig.s, {from: accounts[2], value: web3.toWei(1, "ether")
  //         }).then((result) => {
  //           assert.fail();
  //         }).catch((err) => {
  //           assert.notEqual(err.name, 'AssertionError');
  //           done();
  //         });
  //       } else {
  //         callback(err, undefined);
  //       }
  //     });
  //   });
  // });
  //
  // it('Test contract balance is zero', (done) => {
  //   web3.eth.getBalance(contractAddress, (err, result) => {
  //     assert.equal(result.equals(new BigNumber(0)), true);
  //     done();
  //   });
  // });
  //
  // it('Test companies allocation', (done) => {
  //   var expectedChange;
  //   var blockNumber;
  //   var initialMelonportBalance;
  //   var finalMelonportBalance;
  //   contract.ETHER_CAP().then((result) => {
  //     expectedChange = new BigNumber(result).div(300).mul(12);
  //     blockNumber = startTime + 1;
  //     return melon_contract.lockedBalanceOf(melonport);
  //   }).then((result) => {
  //     initialMelonportBalance = result;
  //     return contract.setBlockNumber(blockNumber, {from: melonport, value: 0});
  //   }).then((result) => {
  //     return contract.allocateCompanyTokens({from: melonport, value: 0});
  //   }).then((result) => {
  //     return melon_contract.lockedBalanceOf(melonport);
  //   }).then((result) => {
  //     finalMelonportBalance = result;
  //     // console.log(
  //     //   '\nfinalMelonportBalance: ' + finalMelonportBalance +
  //     //   '\ninitalMelonportBalance: ' + initialMelonportBalance +
  //     //   '\nexpectedChange: ' + expectedChange
  //     // );
  //     assert.equal(finalMelonportBalance.minus(initialMelonportBalance).toNumber(), new BigNumber(expectedChange));
  //     done();
  //   });
  // });
  //
  // it('Test companies allocation twice', (done) => {
  //   contract.allocateCompanyTokens({from: melonport, value: 0
  //   }).then((result) => {
  //     assert.fail();
  //   }).catch((err) => {
  //     assert.notEqual(err.name, 'AssertionError');
  //     done();
  //   });
  // });
  //
  // it('Test founder change by hacker', (done) => {
  //   var newFounder = accounts[4];
  //   var hacker = accounts[2];
  //   contract.changeFounder(newFounder, {from: hacker, value: 0
  //   }).then((result) => {
  //     assert.fail();
  //   }).catch((err) => {
  //     assert.notEqual(err.name, 'AssertionError');
  //     done();
  //   });
  // });
  //
  // it('Test founder change', (done) => {
  //   var newFounder = accounts[4];
  //   contract.changeFounder(newFounder, {from: melonport, value: 0
  //   }).then((result) => {
  //     return contract.melonport();
  //   }).then((result) => {
  //     assert.equal(result, newFounder);
  //     done();
  //   });
  // });
  //
  // it('Test restricted early transfer', (done) => {
  //   var account3 = accounts[3];
  //   var account4 = accounts[4];
  //   var amount = web3.toWei(1, "ether");
  //   var blockNumber = endTime;
  //   contract.setBlockNumber(blockNumber, {from: melonport, value: 0
  //   }).then((result) => {
  //     return melon_contract.transfer(account3, amount, {from: account4, value: 0});
  //   }).then((result) => {
  //     assert.fail();
  //   }).catch((err) => {
  //     assert.notEqual(err.name, 'AssertionError');
  //     done();
  //   });
  // });
  //
  // it('Test melon transfer after restricted period', (done) => {
  //   var account3 = accounts[3];
  //   var account4 = accounts[4];
  //   var blockNumber = Math.round(endTime + TRANSFER_LOCKUP + 1);
  //   var initalBalance3;
  //   var initalBalance4;
  //   var transferAmount = web3.toWei(1, "ether");
  //   contract.setBlockNumber(blockNumber, {from: melonport, value: 0
  //   }).then((result) => {
  //     return melon_contract.balanceOf(account3);
  //   }).then((result) => {
  //     initalBalance3 = result;
  //     return melon_contract.balanceOf(account4);
  //   }).then((result) => {
  //     initalBalance4 = result;
  //     return melon_contract.transfer(account3, transferAmount, {from: account4, value: 0});
  //   }).then((result) => {
  //     return melon_contract.balanceOf(account3);
  //   }).then((result) => {
  //     assert.equal(result.toNumber(), initalBalance3.plus(transferAmount).toNumber());
  //     return melon_contract.balanceOf(account4);
  //   }).then((result) => {
  //     assert.equal(result.toNumber(), initalBalance4.minus(transferAmount).toNumber());
  //     done();
  //   });
  // });
  //
  // it('Test polkaDot transfer after restricted period', (done) => {
  //   var account3 = accounts[3];
  //   var account4 = accounts[4];
  //   var blockNumber = Math.round(endTime + TRANSFER_LOCKUP + 1);
  //   var initalBalance3;
  //   var initalBalance4;
  //   var transferAmount = web3.toWei(1, "ether");
  //   contract.setBlockNumber(blockNumber, {from: melonport, value: 0
  //   }).then((result) => {
  //     return polkaDot_contract.balanceOf(account3);
  //   }).then((result) => {
  //     initalBalance3 = result;
  //     return polkaDot_contract.balanceOf(account4);
  //   }).then((result) => {
  //     initalBalance4 = result;
  //     return polkaDot_contract.transfer(account3, transferAmount, {from: account4, value: 0});
  //   }).then((result) => {
  //     return polkaDot_contract.balanceOf(account3);
  //   }).then((result) => {
  //     assert.equal(result.toNumber(), initalBalance3.plus(transferAmount).toNumber());
  //     return polkaDot_contract.balanceOf(account4);
  //   }).then((result) => {
  //     assert.equal(result.toNumber(), initalBalance4.minus(transferAmount).toNumber());
  //     done();
  //   });
  // });

});
