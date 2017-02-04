module.exports = (deployer) => {
  const melonport = '0x32cd3282d33ff58b4ae8402a226a0b27441b7f1a';
  const signer = '0x32cd3282d33ff58b4ae8402a226a0b27441b7f1a';
  const btcs = '0x32cd3282d33ff58b4ae8402a226a0b27441b7f1b';
  const startTime = 1483839675;
  deployer.deploy(Contribution, melonport, btcs, signer, startTime);
};
