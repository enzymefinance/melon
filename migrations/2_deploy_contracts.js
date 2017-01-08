module.exports = function(deployer) {
  const multiSigOwners = [
    '0xeaa1f63e60982c33868c8910EA4cd1cfB8eB9dcc',
    '0x0922B77bE99666eD4aaC41370E7487781CAc7A4A',
    '0xDC7FF26c040F5F215f649d62bdf54E5d01291C74',
  ];
  const requiredSignatures = 2;
  const signer = '0x32cd3282d33ff58b4ae8402a226a0b27441b7f1a';
  const btcs = '0x32cd3282d33ff58b4ae8402a226a0b27441b7f1b';
  const startTime = 1483839675;
  deployer.deploy(MultiSigWallet, multiSigOwners, requiredSignatures).then(() =>
    deployer.deploy(Contribution, MultiSigWallet.address, btcs, signer, startTime)
  );
};
