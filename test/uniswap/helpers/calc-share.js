const { BigNumber } = require("ethers");
const { liquidity } = require("./liquidity");
const { liquidityLast } = require("./liquidity-last");

const calcShare = async (pool, contract, amount0Desired, amount1Desired) => {
  const _liquidity = await liquidity(pool, contract, amount0Desired, amount1Desired);
  const _liquidityLast = await liquidityLast(pool, contract);

  const totalSupply = await contract.totalSupply();

  return totalSupply.isZero()
    ? _liquidity
    : BigNumber.from(_liquidity).mul(totalSupply).div(BigNumber.from(_liquidityLast)).toString();
};

module.exports = {
  calcShare,
};
