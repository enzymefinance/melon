module.exports = function(deployer) {
  deployer.deploy(MelonToken);
  deployer.deploy(PolkaDotToken);
  // TODO deploy contribution w melon and polka param
};
