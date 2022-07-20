const { utils } = require("ethers");

const getPositionKey = async (address, lowerTicker, upperTick) => {
  return utils.keccak256(utils.solidityPack(["address", "int24", "int24"], [address, lowerTicker, upperTick]));
};

module.exports = {
  getPositionKey,
};
