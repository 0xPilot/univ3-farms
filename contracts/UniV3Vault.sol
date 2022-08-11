// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./libraries/PoolActions.sol";
import "./interfaces/IUniV3Vault.sol";

import "hardhat/console.sol";

/**
 * @title UniV3Vault
 * @notice Uniswap V3 Vault implementation
 */
contract UniV3Vault is IUniV3Vault, Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
  using LowGasSafeMath for uint256;
  using LowGasSafeMath for uint160;
  using LowGasSafeMath for uint128;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using PoolActions for IUniswapV3Pool;
  using PoolVariables for IUniswapV3Pool;

  /// @notice Emitted when user adds liquidity
  /// @param by The address that minted the liquidity
  /// @param recipient The address that get shares
  /// @param shares The amount of share of liquidity added by the user to position
  /// @param amount0 How much token0 was required for the added liquidity
  /// @param amount1 How much token1 was required for the added liquidity
  event Deposit(address indexed by, address indexed recipient, uint256 shares, uint256 amount0, uint256 amount1);

  /// @notice Emitted when user withdraws liquidity
  /// @param by The address that burn the liquidity
  /// @param recipient The address that get amounts
  /// @param shares of liquidity withdrawn by the user from the position
  /// @param amount0 How much token0 was required for the added liquidity
  /// @param amount1 How much token1 was required for the added liquidity
  event Withdraw(address indexed by, address indexed recipient, uint256 shares, uint256 amount0, uint256 amount1);

  /// @notice Emitted when fees was collected from the pool
  /// @param feesFromPool0 Total amount of fees collected from the pool in terms of token 0
  /// @param feesFromPool1 Total amount of fees collected from the pool in terms of token 1
  /// @param totalFees0 Total amount of fees collected in terms of token 0
  /// @param totalFees1 Total amount of fees collected in terms of token 1
  event CollectFees(
    address indexed by,
    uint256 feesFromPool0,
    uint256 feesFromPool1,
    uint256 totalFees0,
    uint256 totalFees1
  );

  /// @notice Emitted when Vault changes the position in the pool
  /// @param tickLower Lower price tick of the positon
  /// @param tickUpper Upper price tick of the position
  /// @param amount0 Amount of token 0 deposited to the position
  /// @param amount1 Amount of token 1 deposited to the position
  event Rerange(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1);

  /// @notice Emitted when the tick range multiplier is chagned
  /// @param by The address that chagned the tick range multiplier
  /// @param tickRangeMultiplier The tick range multiplier set
  event TickRangeMultiplerChanged(address indexed by, int24 tickRangeMultiplier);

  /// @notice Emitted when the Vault admin is updated
  /// @param by The old admin address
  /// @param admin The new admin address
  event AdminChanged(address indexed by, address admin);

  /// @notice Emitted when the Vault manager is added by the Vault admin
  /// @param by The admin address added the manager
  /// @param manager The manager address added
  event ManagerAdded(address indexed by, address indexed manager);

  /// @notice Emitted when the Vault manager is removed by the Vault admin
  /// @param by The admin address removed the manager
  /// @param manager The manager address removed
  event ManagerRemoved(address indexed by, address indexed manager);

  /// @dev Any data passed through by the caller via the IUniswapV3PoolActions#mint call
  struct MintCallbackData {
    address payer;
  }

  /// @inheritdoc IUniV3Vault
  address public override admin;
  /// @inheritdoc IUniV3Vault
  address public override token0;
  /// @inheritdoc IUniV3Vault
  address public override token1;
  /// @inheritdoc IUniV3Vault
  int24 public override tickSpacing;
  /// @inheritdoc IUniV3Vault
  int24 public override tickRangeMultiplier;
  uint24 private constant MULTIPLIER = 1e6;
  uint24 private constant GLOBAL_DIVISIONER = 1e6; // for basis point (0.0001%)
  uint24 private constant protocolFee = 2 * 1e5; // 20%

  mapping(address => bool) public managers;

  /// @inheritdoc IUniV3Vault
  IUniswapV3Pool public override pool;
  // Accrued protocol fees in terms of token0
  uint256 public protocolFees0;
  // Accrued protocol fees in terms of token1
  uint256 public protocolFees1;
  // Total accrued fees in tersm of token0
  uint256 public totalFees0;
  // Total accrued fees in tersm of token1
  uint256 public totalFees1;
  // Current tick lower of Vault pool position
  int24 public override tickLower;
  // Current tick higher of Vault pool position
  int24 public override tickUpper;

  modifier onlyAdmin() {
    require(msg.sender == admin, "OA");
    _;
  }

  modifier onlyAdminOrManager() {
    require(msg.sender == admin || managers[msg.sender], "OAM");
    _;
  }

  function initialize(
    address _admin,
    address _pool,
    int24 _tickRangeMultiplier,
    string memory _name,
    string memory _symbol
  ) public initializer {
    __ERC20_init(_name, _symbol);
    __ReentrancyGuard_init();
    __Pausable_init();

    // initialize the params
    admin = _admin;
    pool = IUniswapV3Pool(_pool);
    token0 = pool.token0();
    token1 = pool.token1();
    tickSpacing = pool.tickSpacing();
    tickRangeMultiplier = _tickRangeMultiplier;

    int24 baseThreshold = tickSpacing * _tickRangeMultiplier;
    (, int24 currentTick, , , , , ) = pool.slot0();
    (tickLower, tickUpper) = PoolVariables.baseTicks(currentTick, baseThreshold, tickSpacing);
    PoolVariables.checkRange(tickLower, tickUpper);
  }

  /// @inheritdoc IUniV3Vault
  function deposit(
    uint256 _amount0Desired,
    uint256 _amount1Desired,
    address _to
  )
    external
    override
    nonReentrant
    whenNotPaused
    returns (
      uint256 shares,
      uint256 amount0,
      uint256 amount1
    )
  {
    _earnFees();
    uint128 liquidityLast = pool.positionLiquidity(tickLower, tickUpper);

    // Calculate the liquidity amount
    uint128 liquidity = pool.liquidityForAmounts(_amount0Desired, _amount1Desired, tickLower, tickUpper);

    // Add liquidity for the given recipient and tick range
    (amount0, amount1) = pool.mint(
      address(this),
      tickLower,
      tickUpper,
      liquidity,
      abi.encode(MintCallbackData({payer: msg.sender}))
    );
    require(amount0 > 0 && amount1 > 0, "ANV");

    // Mint shares
    shares = totalSupply() == 0 ? liquidity * MULTIPLIER : FullMath.mulDiv(liquidity, totalSupply(), liquidityLast);
    _mint(_to, shares);

    emit Deposit(msg.sender, _to, shares, amount0, amount1);
  }

  /// @inheritdoc IUniV3Vault
  function withdraw(uint256 _shares, address _to)
    external
    override
    nonReentrant
    whenNotPaused
    returns (uint256 amount0, uint256 amount1)
  {
    require(_shares > 0, "S");
    require(_to != address(0), "WZA");

    _earnFees();

    // Burn shares
    (amount0, amount1) = pool.burnLiquidityShare(tickLower, tickUpper, totalSupply(), _shares, _to);
    require(amount0 > 0 || amount1 > 0, "EA");
    _burn(msg.sender, _shares);

    emit Withdraw(msg.sender, _to, _shares, amount0, amount1);
  }

  /// @inheritdoc IUniV3Vault
  function rerange() external override nonReentrant onlyAdminOrManager {
    _earnFees();

    // Burn all liquidity from pool to rerange for Vault balances
    pool.burnAllLiquidity(tickLower, tickUpper);

    // Get token balances
    uint256 balance0 = _balance0();
    uint256 balance1 = _balance1();

    // Get exact ticks depending on Vault balances
    int24 baseThreshold = tickSpacing * tickRangeMultiplier;
    (tickLower, tickUpper) = pool.getPositionTicks(balance0, balance1, baseThreshold, tickSpacing);

    // Get liquidity for Vault balances
    uint128 liquidity = pool.liquidityForAmounts(balance0, balance1, tickLower, tickUpper);

    // Add liquidity to the pool
    (uint256 amount0, uint256 amount1) = pool.mint(
      address(this),
      tickLower,
      tickUpper,
      liquidity,
      abi.encode(MintCallbackData({payer: address(this)}))
    );

    emit Rerange(tickLower, tickUpper, amount0, amount1);
  }

  /// @inheritdoc IUniV3Vault
  function setTickRangeMultiplier(int24 newTickRangeMultiplier) external override onlyAdminOrManager {
    tickRangeMultiplier = newTickRangeMultiplier;

    emit TickRangeMultiplerChanged(msg.sender, newTickRangeMultiplier);
  }

  /// @notice Pull in tokens from sender. Called to `msg.sender` after minting liquidity to a position from IUniswapV3Pool#mint.
  /// @dev In the implementation you must pay to the pool for the minted liquidity.
  /// @param amount0 The amount of token0 due to the pool for the minted liquidity
  /// @param amount1 The amount of token1 due to the pool for the minted liquidity
  /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#mint call
  function uniswapV3MintCallback(
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external {
    require(msg.sender == address(pool), "FP");

    MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

    if (amount0 > 0) _pay(token0, decoded.payer, msg.sender, amount0);
    if (amount1 > 0) _pay(token1, decoded.payer, msg.sender, amount1);
  }

  /// @dev Amount of token0 held as unused balance.
  function _balance0() internal view returns (uint256) {
    return IERC20Upgradeable(token0).balanceOf(address(this)).sub(protocolFees0);
  }

  /// @dev Amount of token1 held as unused balance.
  function _balance1() internal view returns (uint256) {
    return IERC20Upgradeable(token1).balanceOf(address(this)).sub(protocolFees1);
  }

  /// @dev collects fees from the pool
  function _earnFees() internal {
    uint256 liquidity = pool.positionLiquidity(tickLower, tickUpper);
    if (liquidity == 0) return;

    // Burn with zero amount to update the earned fees
    pool.burn(tickLower, tickUpper, 0);

    // Collect fees to the contract
    (uint256 collect0, uint256 collect1) = pool.collect(
      address(this),
      tickLower,
      tickUpper,
      type(uint128).max,
      type(uint128).max
    );

    // Calculate protocol fees
    uint256 earnedProtocolFees0 = SafeMathUpgradeable.div(collect0.mul(protocolFee), GLOBAL_DIVISIONER);
    uint256 earnedProtocolFees1 = SafeMathUpgradeable.div(collect1.mul(protocolFee), GLOBAL_DIVISIONER);
    protocolFees0 = protocolFees0.add(earnedProtocolFees0);
    protocolFees1 = protocolFees1.add(earnedProtocolFees1);
    totalFees0 = totalFees0.add(collect0);
    totalFees1 = totalFees0.add(collect1);

    emit CollectFees(msg.sender, collect0, collect1, totalFees0, totalFees1);
  }

  /// @param _token The token to pay
  /// @param _payer The entity that must pay
  /// @param _recipient The entity that will receive payment
  /// @param _value The amount to pay
  function _pay(
    address _token,
    address _payer,
    address _recipient,
    uint256 _value
  ) internal {
    if (_payer == address(this)) {
      // pay with tokens already in the contract
      IERC20Upgradeable(_token).safeTransfer(_recipient, _value);
    } else {
      // pull payment
      IERC20Upgradeable(_token).safeTransferFrom(_payer, _recipient, _value);
    }
  }

  /// @notice Change Vault admin address
  /// @param _admin The admin address
  function changeAdmin(address _admin) external onlyAdmin {
    require(_admin != address(0), "ZAA");
    admin = _admin;

    emit AdminChanged(msg.sender, _admin);
  }

  /// @notice Add Vault manager address
  /// @param _manager The manager address to add
  function addManager(address _manager) external onlyAdmin {
    if (!managers[_manager]) {
      managers[_manager] = true;

      emit ManagerAdded(msg.sender, _manager);
    }
  }

  /// @notice Remove Vault manager address
  /// @param _manager The manager address to remove
  function removeManager(address _manager) external onlyAdmin {
    if (managers[_manager]) {
      managers[_manager] = false;

      emit ManagerAdded(msg.sender, _manager);
    }
  }
}
