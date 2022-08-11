// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniV3Vault {
  /// @notice The Vault admin address
  /// @dev The Vault admin can add or remove the Vault managers
  /// @return The Vault admin address
  function admin() external view returns (address);

  /// @notice The first of the two tokens of the pool, sorted by address
  /// @return The token contract address
  function token0() external view returns (address);

  /// @notice The second of the two tokens of the pool, sorted by address
  /// @return The token contract address
  function token1() external view returns (address);

  /// @notice The pool tick spacing
  /// @dev Ticks can only be used at multiples of this value, minimum of 1 and always positive
  /// e.g.: a tickSpacing of 3 means ticks can be initialized every 3rd tick, i.e., ..., -6, -3, 0, 3, 6, ...
  /// This value is an int24 to avoid casting even though it is always positive.
  /// @return The tick spacing
  function tickSpacing() external view returns (int24);

  /// @notice The tick multiplier for base range calculation
  function tickRangeMultiplier() external view returns (int24);

  /// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
  /// to the ERC20 specification
  /// @return The address of the Uniswap V3 Pool
  function pool() external view returns (IUniswapV3Pool);

  /// @notice The lower tick of the range
  function tickLower() external view returns (int24);

  /// @notice The upper tick of the range
  function tickUpper() external view returns (int24);

  /// @notice Deposits tokens in proportion to the Vault's current ticks.
  /// @param amount0Desired Max amount of token0 to deposit
  /// @param amount1Desired Max amount of token1 to deposit
  /// @param to address that plp should be transfered
  /// @return shares minted
  /// @return amount0 Amount of token0 deposited
  /// @return amount1 Amount of token1 deposited
  function deposit(
    uint256 amount0Desired,
    uint256 amount1Desired,
    address to
  )
    external
    returns (
      uint256 shares,
      uint256 amount0,
      uint256 amount1
    );

  /// @notice Withdraws tokens in proportion to the Vault's holdings.
  /// @dev Removes proportional amount of liquidity from Uniswap.
  /// @param shares burned by sender
  /// @return amount0 Amount of token0 sent to recipient
  /// @return amount1 Amount of token1 sent to recipient
  function withdraw(uint256 shares, address to) external returns (uint256 amount0, uint256 amount1);

  /// @notice Updates Vault's positions.
  /// @dev Finds base position for imbalanced token
  /// mints all amounts to this position(including earned fees)
  function rerange() external;

  /// @notice Set the tick range multiplier
  /// @dev Change the tick range where the liquidity is added
  /// @param newTickRangeMultiplier new tick range multiplier
  function setTickRangeMultiplier(int24 newTickRangeMultiplier) external;
}
