const { Token } = require("@uniswap/sdk-core");
const { Pool, Position } = require("@uniswap/v3-sdk");

const createPosition = async (uniswapPool, fee, liquidity, tickLower, tickUpper) => {
  const token0 = new Token(0, await uniswapPool.token0(), 18);
  const token1 = new Token(0, await uniswapPool.token1(), 18);

  const { sqrtPriceX96, tick } = await uniswapPool.slot0();
  const poolLiquidity = await uniswapPool.liquidity();

  const pool = new Pool(token0, token1, fee, sqrtPriceX96.toString(), poolLiquidity.toString(), tick);

  return new Position({ pool, liquidity: liquidity.toString(), tickLower, tickUpper });
};

module.exports = {
  createPosition,
};
