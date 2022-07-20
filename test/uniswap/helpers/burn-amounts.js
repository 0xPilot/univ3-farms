const { FeeAmount } = require("@uniswap/v3-sdk");
const { Percent } = require("@uniswap/sdk-core");
const { BigNumber } = require("ethers");
const { getTicks } = require("./get-ticks");
const { liquidityForAmounts } = require("./liquidity-for-amounts");
const { liquidityLast } = require("./liquidity-last");
const { createPosition } = require("./create-position");

const burnAmounts = async (uniswapPool, contract, share, to) => {
  const [tickLower, tickUpper] = await getTicks(contract);

  const protocolFees0 = await contract.protocolFees0();
  const protocolFees1 = await contract.protocolFees1();

  const protocolLiquidity = await liquidityForAmounts(
    uniswapPool,
    protocolFees0.toNumber(),
    protocolFees1.toNumber(),
    tickLower,
    tickUpper,
  );

  const liqudityInPool = await liquidityLast(uniswapPool, contract);

  const totalSupply = await contract.totalSupply();

  const liquidity = liqudityInPool.sub(protocolLiquidity).mul(BigNumber.from(share)).div(totalSupply);

  const position = await createPosition(uniswapPool, FeeAmount.MEDIUM, liquidity.toString(), tickLower, tickUpper);

  const { amount0, amount1 } = position.burnAmountsWithSlippage(new Percent(0));
  return [amount0.toString(), amount1.toString()];
};

module.exports = {
  burnAmounts,
};
