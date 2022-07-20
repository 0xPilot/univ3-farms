const { ethers } = require("hardhat");
const UniswapV3Factory = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json");
const WETH9 = require("../constants/WETH9.json");
const UniswapV3Router = require("@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json");
const UniswapV3Pool = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json");
const { encodePriceSqrt } = require("./encode-price-sqrt");

const deployUniswapFactory = async (deployer) => {
  const factory = new ethers.ContractFactory(UniswapV3Factory.abi, UniswapV3Factory.bytecode, deployer);
  return await factory.deploy();
};

const deployWeth9 = async (deployer) => {
  const factory = new ethers.ContractFactory(WETH9.abi, WETH9.bytecode, deployer);
  return await factory.deploy();
};

const deployUniswapRouter = async (deployer, factoryAddress, weth9Address) => {
  const factory = new ethers.ContractFactory(UniswapV3Router.abi, UniswapV3Router.bytecode, deployer);
  return await factory.deploy(factoryAddress, weth9Address);
};

const deployERC20 = async (poolOption) => {
  const factory = await ethers.getContractFactory("ERC20Mock");
  return await factory.deploy(poolOption.name, poolOption.symbol);
};

const deployUniswapPool = async (factory, tokens, feeAmount, priceSqrtRange) => {
  await factory.createPool(tokens[0].address, tokens[1].address, feeAmount);
  const poolAddress = await factory.getPool(tokens[0].address, tokens[1].address, feeAmount);
  const pool = await ethers.getContractAt(UniswapV3Pool.abi, poolAddress);

  await pool.initialize(encodePriceSqrt(priceSqrtRange[0], priceSqrtRange[1]));

  const token0Address = await pool.token0();
  const token1Address = await pool.token1();

  const token0 = await ethers.getContractAt("ERC20Mock", token0Address);
  const token1 = await ethers.getContractAt("ERC20Mock", token1Address);

  return { pool, token0, token1 };
};

const deploy = async (deployer, poolOptions) => {
  const factory = await deployUniswapFactory(deployer);
  const weth9 = await deployWeth9(deployer);
  const router = await deployUniswapRouter(deployer, factory.address, weth9.address);
  const tokens = await Promise.all(poolOptions.tokens.map(async (poolOption) => deployERC20(poolOption)));
  const pool = await deployUniswapPool(factory, tokens, poolOptions.feeAmount, poolOptions.priceSqrtRange);

  return { factory, weth9, router, pool };
};

module.exports = {
  deploy,
};
