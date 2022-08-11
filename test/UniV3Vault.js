const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { BigNumber, constants } = require("ethers");
const { FeeAmount } = require("@uniswap/v3-sdk");
const {
  deploy,
  mintAmounts,
  getTicks,
  liquidity,
  liquidityLast,
  calcShare,
  burnAmounts,
} = require("./uniswap/helpers");

const TOKEN_MAX_AMOUNT = 10000;

const snapshot = async () => {
  const snapshotId = await network.provider.request({
    method: "evm_snapshot",
  });

  return snapshotId;
};

const revertSnapshot = async (id) => {
  await network.provider.request({
    method: "evm_revert",
    params: [id],
  });
};

const randomTokenNumber = () => {
  const rand = Math.random() * TOKEN_MAX_AMOUNT;
  return ethers.utils.parseEther(rand.toString());
};

describe("UniV3 Vault", function () {
  let vault, pool, router, token0, token1;
  let testSnapshotId;

  const TOKENS = [
    { name: "Token0", symbol: "T0" },
    { name: "Token1", symbol: "T1" },
  ];

  const ONE_ETHER = ethers.utils.parseEther("1");

  before(async () => {
    [deployer, admin, alice, other] = await ethers.getSigners();

    // Deploy Uniswap V3 contracts and create the pool
    const deployedContracts = await deploy(deployer, {
      feeAmount: FeeAmount.MEDIUM,
      tokens: TOKENS,
      priceSqrtRange: [1, 2],
    });
    pool = deployedContracts.pool.pool;
    router = deployedContracts.router;
    token0 = deployedContracts.pool.token0;
    token1 = deployedContracts.pool.token1;

    // Deploy UniV3 Vault contract
    const VaultFactory = await ethers.getContractFactory("UniV3Vault");
    vault = await VaultFactory.deploy(admin.address, pool.address, 1, "TCR<>WETH", "TCR<>WETH");

    // Mint and approve tokens
    for (let token of [token0, token1]) {
      await token.mint(deployer.address, ONE_ETHER.mul(TOKEN_MAX_AMOUNT));
      await token.approve(vault.address, constants.MaxUint256);
      await token.approve(router.address, constants.MaxUint256);

      await token.mint(other.address, ONE_ETHER.mul(TOKEN_MAX_AMOUNT));
      await token.connect(other).approve(vault.address, constants.MaxUint256);
      await token.connect(other).approve(router.address, constants.MaxUint256);
    }
  });

  beforeEach(async () => {
    testSnapshotId = await snapshot();
  });

  afterEach(async () => {
    await revertSnapshot(testSnapshotId);
  });

  describe("deposit", () => {
    let aliceAddress, share, amount0Desired, amount1Desired, amount0, amount1;

    beforeEach(async () => {
      aliceAddress = alice.address;
      amount0Desired = randomTokenNumber();
      amount1Desired = randomTokenNumber();

      const [tickLower, tickUpper] = await getTicks(vault);
      const _liquidity = await liquidity(pool, vault, amount0Desired, amount1Desired);
      share = await calcShare(pool, vault, amount0Desired, amount1Desired);
      [amount0, amount1] = await mintAmounts(pool, tickLower, tickUpper, _liquidity);
    });

    it("Should emit Deposit event", async () => {
      // deposit
      const tx = vault.deposit(amount0Desired, amount1Desired, aliceAddress);
      const shareMultiplier = BigNumber.from(share).mul(1e6);

      await expect(tx)
        .to.emit(vault, "Deposit")
        .withArgs(deployer.address, aliceAddress, shareMultiplier, amount0, amount1);
    });

    it("Should deposit tokens to the pool", async () => {
      // check the old values
      const token0BalanceBefore = await token0.balanceOf(deployer.address);
      const token1BalanceBefore = await token1.balanceOf(deployer.address);
      const poolLiquidityBefore = await liquidityLast(pool, vault);
      const shareBefore = await vault.balanceOf(aliceAddress);

      // deposit
      const tx = await vault.deposit(amount0Desired, amount1Desired, aliceAddress);
      const receipt = await tx.wait();

      // check the new values
      const token0BalanceAfter = await token0.balanceOf(deployer.address);
      const token1BalanceAfter = await token1.balanceOf(deployer.address);
      const poolLiquidityAfter = await liquidityLast(pool, vault);
      const shareAfter = await vault.balanceOf(aliceAddress);

      const depositEvent = receipt.events.filter((log) => log.event == "Deposit")[0];
      const token0Deposited = depositEvent.args.amount0;
      const token1Deposited = depositEvent.args.amount1;
      const shareMinted = depositEvent.args.shares;

      expect(token0BalanceAfter).to.equal(token0BalanceBefore.sub(token0Deposited));
      expect(token1BalanceAfter).to.equal(token1BalanceBefore.sub(token1Deposited));
      expect(poolLiquidityAfter).to.gt(poolLiquidityBefore);
      expect(shareAfter).to.equal(shareBefore.add(shareMinted));
    });
  });

  describe("withdraw", () => {
    let aliceAddress, share, amount0Desired, amount1Desired, amount0, amount1;

    beforeEach(async () => {
      aliceAddress = alice.address;
      amount0Desired = randomTokenNumber();
      amount1Desired = randomTokenNumber();

      // deposit
      await vault.deposit(amount0Desired, amount1Desired, aliceAddress);

      share = await calcShare(pool, vault, amount0Desired, amount1Desired);
      [amount0, amount1] = await burnAmounts(pool, vault, share, aliceAddress);
    });

    it("Should emit Withdraw event", async () => {
      // withdraw
      await vault.connect(alice).approve(vault.address, share);
      const tx = vault.connect(alice).withdraw(share, other.address);

      await expect(tx).to.emit(vault, "Withdraw").withArgs(aliceAddress, other.address, share, amount0, amount1);
    });

    it("Should burn shares", async () => {
      // check the old values
      const shareBalanceBefore = await vault.balanceOf(aliceAddress);
      const token0BalanceBefore = await token0.balanceOf(other.address);
      const token1BalanceBefore = await token1.balanceOf(other.address);
      const poolLiquidityBefore = await liquidityLast(pool, vault);

      expect(shareBalanceBefore).to.equal(share);

      // withdraw
      await vault.connect(alice).approve(vault.address, share);
      const tx = await vault.connect(alice).withdraw(share, other.address);
      const receipt = await tx.wait();

      // check the new values
      const shareBalanceAfter = await vault.balanceOf(aliceAddress);
      const token0BalanceAfter = await token0.balanceOf(other.address);
      const token1BalanceAfter = await token1.balanceOf(other.address);
      const poolLiquidityAfter = await liquidityLast(pool, vault);

      const withdrawEvent = receipt.events.filter((log) => log.event == "Withdraw")[0];
      const token0Withdraw = withdrawEvent.args.amount0;
      const token1Withdraw = withdrawEvent.args.amount1;
      const shareWithdraw = withdrawEvent.args.shares;

      expect(token0BalanceAfter).to.equal(token0BalanceBefore.add(token0Withdraw));
      expect(token1BalanceAfter).to.equal(token1BalanceBefore.add(token1Withdraw));
      expect(poolLiquidityAfter).to.lt(poolLiquidityBefore);
      expect(shareBalanceAfter).to.equal(shareBalanceBefore.sub(shareWithdraw));
    });

    it("Should revert if the shares is zero", async () => {
      // withdraw
      await vault.connect(alice).approve(vault.address, share);
      const tx = vault.connect(alice).withdraw(0, other.address);

      await expect(tx).to.revertedWith("S");
    });

    it("Should revert if beneficiary address is address(0)", async () => {
      // withdraw
      await vault.connect(alice).approve(vault.address, share);
      const tx = vault.connect(alice).withdraw(share, constants.AddressZero);

      await expect(tx).to.revertedWith("WZA");
    });
  });

  describe("rebalance", () => {
    beforeEach(async () => {
      aliceAddress = alice.address;
      const amount = 100000;

      // deposit
      await vault.deposit(amount, amount, aliceAddress);
    });

    it("Should emit Reragne event", async () => {
      const [tickLower, tickUpper] = await getTicks(vault);
      const token0Reserved = await token0.balanceOf(pool.address);
      const token1Reserved = await token1.balanceOf(pool.address);

      // rerange
      const tx = await vault.connect(admin).rerange();
      const receipt = await tx.wait();

      const rerangeEvent = receipt.events.filter((log) => log.event == "Rerange")[0];
      const rerangedTickLower = rerangeEvent.args.tickLower;
      const rerangedTickUpper = rerangeEvent.args.tickUpper;
      const token0Deposited = rerangeEvent.args.amount0;
      const token1Deposited = rerangeEvent.args.amount1;

      expect(rerangedTickLower).to.equal(tickLower);
      expect(rerangedTickUpper).to.equal(tickUpper);
      expect(token0Deposited).to.be.closeTo(token0Reserved, token0Reserved.mul(9999).div(10000)); // 0.01% delta
      expect(token1Deposited).to.be.closeTo(token1Reserved, token1Reserved.mul(9999).div(10000)); // 0.01% delta
    });

    it("Should be called only owner or admin", async () => {
      const tx = vault.connect(other).rerange();
      await expect(tx).to.revertedWith("OAM");
    });
  });
});
