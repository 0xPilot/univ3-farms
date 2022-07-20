const { getTicks } = require("./get-ticks");
const { liquidityForAmounts } = require("./liquidity-for-amounts");

const liquidity = async (pool, contract, amount0Desird, amount1Desird) => {
  const [tickLower, tickUpper] = await getTicks(contract);
  return await liquidityForAmounts(pool, amount0Desird, amount1Desird, tickLower, tickUpper);
};

module.exports = {
  liquidity,
};
