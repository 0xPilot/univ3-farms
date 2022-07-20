const { TickMath, maxLiquidityForAmounts } = require("@uniswap/v3-sdk");
const JSBI = require("jsbi");

const liquidityForAmounts = async (pool, amount0, amount1, tickLower, tickUpper) => {
  const [sqrtRatioX96] = await pool.slot0();
  const _tickLower = TickMath.getSqrtRatioAtTick(tickLower);
  const _tickUpper = TickMath.getSqrtRatioAtTick(tickUpper);

  return maxLiquidityForAmounts(JSBI.BigInt(sqrtRatioX96), _tickLower, _tickUpper, amount0, amount1, true).toString();
};

module.exports = {
  liquidityForAmounts,
};
