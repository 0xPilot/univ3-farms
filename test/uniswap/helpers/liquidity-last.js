const { getTicks } = require("./get-ticks");
const { getPositionKey } = require("./get-position-key");

const liquidityLast = async (pool, contract) => {
  const [tickLower, tickUpper] = await getTicks(contract);
  const positionKey = getPositionKey(contract.address, tickLower, tickUpper);
  const [liquidityLast] = await pool.positions(positionKey);

  return liquidityLast;
};

module.exports = {
  liquidityLast,
};
