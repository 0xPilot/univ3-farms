// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./PoolVariables.sol";

library PoolActions {
  using PoolVariables for IUniswapV3Pool;
  using LowGasSafeMath for uint256;
  using SafeCast for uint256;

  /// @notice Withdraws liquidity in share proportion to the Vault's totalSupply.
  /// @param pool Uniswap V3 pool
  /// @param tickLower The lower tick of the range
  /// @param tickUpper The upper tick of the range
  /// @param totalSupply The amount of total shares in existence
  /// @param share to burn
  /// @param to Recipient of amounts
  /// @return amount0 Amount of token0 withdrawed
  /// @return amount1 Amount of token1 withdrawed
  function burnLiquidityShare(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper,
    uint256 totalSupply,
    uint256 share,
    address to
  ) internal returns (uint256 amount0, uint256 amount1) {
    require(totalSupply > 0, "TS");
    uint128 liquidityInPool = pool.positionLiquidity(tickLower, tickUpper);
    uint256 liquidity = uint256(liquidityInPool).mul(share) / totalSupply;

    if (liquidity > 0) {
      (amount0, amount1) = pool.burn(tickLower, tickUpper, toUint128(liquidity));

      if (amount0 > 0 || amount1 > 0) {
        // Collect liqudity share
        (amount0, amount1) = pool.collect(to, tickLower, tickUpper, toUint128(amount0), toUint128(amount1));
      }
    }
  }

  /// @notice Withdraws all liquidity in a range from Uniswap pool
  /// @param pool Uniswap V3 pool
  /// @param tickLower The lower tick of the range
  /// @param tickUpper The upper tick of the range
  function burnAllLiquidity(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickUpper
  ) internal {
    // Burn all liquidity in this range
    uint128 liquidity = pool.positionLiquidity(tickLower, tickUpper);
    if (liquidity > 0) {
      pool.burn(tickLower, tickUpper, liquidity);
    }

    // Collect all owed tokens
    pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
  }

  /// @notice Cast a uint256 to a uint128, revert on overflow
  /// @param y The uint256 to be downcasted
  /// @return z The downcasted integer, now type uint128
  function toUint128(uint256 y) internal pure returns (uint128 z) {
    require((z = uint128(y)) == y);
  }
}
