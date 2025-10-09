
import {expect} from "chai";
import {network} from "hardhat";
import {createToken} from "./utils/contractUtils.js";
const {ethers, networkHelpers} = await network.connect();

describe("LPOracleFairValue", function () {
  const Q112 = 2n ** 112n;
  const WAD = 10n ** 18n;

  async function deployContracts() {
    const [owner, addr1] = await ethers.getSigners();

    const MockOracle = await ethers.getContractFactory("MockMasterOracle");
    const oracle = await MockOracle.deploy();

    const LPOracle = await ethers.getContractFactory("LPOracleFairValue");
    const lpOracle = await LPOracle.deploy(oracle, owner);

    const token0 = await createToken(owner, "Favor", "Favor");
    const token1 = await createToken(owner, "PLSX", "PLSX");

    // Deploy mock pair
    const MockPair = await ethers.getContractFactory("MockPair");
    const pair = await MockPair.deploy(
      await token0.getAddress(),
      await token1.getAddress()
    );

    return { lpOracle, oracle, token0, token1, pair, owner, addr1 };
  }

  describe("Deployment", function () {
        it("shall be able to deploy", async () => {
            const [owner] = await ethers.getSigners();
            let {lpOracle} = await networkHelpers.loadFixture(deployContracts);
            expect(lpOracle).to.not.equal(null);
        })
  });

  describe("getUSDPx_Q112", function () {
    it("Should correctly convert WAD price to Q112", async function () {
      const { lpOracle, oracle, token0 } = await networkHelpers.loadFixture(deployContracts);
      
      // Set price to $1000 (in WAD)
      const priceWad = ethers.parseEther("1000");
      await oracle.setLastPrice(await token0.getAddress(), priceWad);

      const priceQ112 = await lpOracle.getUSDPx_Q112(await token0.getAddress());
      
      // Expected: 1000 * 2^112 / 1e18
      const expected = (priceWad * Q112) / WAD;
      expect(priceQ112).to.equal(expected);
    });

    it("Should handle small prices correctly", async function () {
      const { lpOracle, oracle, token0 } = await networkHelpers.loadFixture(deployContracts);
      
      // Set price to $0.001 (in WAD)
      const priceWad = ethers.parseEther("0.001");
      await oracle.setLastPrice(await token0.getAddress(), priceWad);

      const priceQ112 = await lpOracle.getUSDPx_Q112(await token0.getAddress());
      
      const expected = (priceWad * Q112) / WAD;
      expect(priceQ112).to.equal(expected);
    });

    it("Should return 0 for zero price", async function () {
      const { lpOracle, token0 } = await networkHelpers.loadFixture(deployContracts);
      const priceQ112 = await lpOracle.getUSDPx_Q112(await token0.getAddress());
      expect(priceQ112).to.equal(0);
    });
  });

  describe("lpPriceUSD_Q112", function () {
    it("Should calculate correct LP price for balanced pool", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      // Set reserves: 100 token0, 100 token1
      const reserves = ethers.parseEther("100");
      await pair.setReserves(reserves, reserves);
      await pair.setTotalSupply(ethers.parseEther("100")); // 100 LP tokens

      // Set prices: $10 each
      const price = ethers.parseEther("10");
      await oracle.setLastPrice(await token0.getAddress(), price);
      await oracle.setLastPrice(await token1.getAddress(), price);

      const lpPrice = await lpOracle.lpPriceUSD_Q112(await pair.getAddress());

      // Expected: 2 * sqrt(10 * 10) = $20 per LP token
      // In Q112: 20 * 2^112
      const expectedWad = ethers.parseEther("20");
      const expectedQ112 = (expectedWad * Q112) / WAD;
      
      // Allow small rounding error
      expect(lpPrice).to.be.closeTo(expectedQ112, expectedQ112 / 1000n);
    });

    it("Should calculate correct LP price for imbalanced pool", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      // Set reserves: 400 token0, 100 token1 (ratio 4:1)
      await pair.setReserves(ethers.parseEther("400"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("200"));

      // Set prices: $5 for token0, $20 for token1
      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("5"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("20"));

      const lpPrice = await lpOracle.lpPriceUSD_Q112(await pair.getAddress());

      // Expected: 2 * sqrt(5 * 20) = 2 * sqrt(100) = 2 * 10 = $20 per LP
      const expectedWad = ethers.parseEther("20");
      const expectedQ112 = (expectedWad * Q112) / WAD;
      
      expect(lpPrice).to.be.closeTo(expectedQ112, expectedQ112 / 1000n);
    });

    it("Should return 0 when reserves are 0", async function () {
      const { lpOracle, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(0, 0);
      await pair.setTotalSupply(ethers.parseEther("100"));

      const lpPrice = await lpOracle.lpPriceUSD_Q112(await pair.getAddress());
      expect(lpPrice).to.equal(0);
    });

    it("Should return 0 when one reserve is 0", async function () {
      const { lpOracle, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), 0);
      await pair.setTotalSupply(ethers.parseEther("100"));

      const lpPrice = await lpOracle.lpPriceUSD_Q112(await pair.getAddress());
      expect(lpPrice).to.equal(0);
    });

    it("Should revert when totalSupply is 0", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(0);

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      await expect(
        lpOracle.lpPriceUSD_Q112(await pair.getAddress())
      ).to.be.revertedWith("LP: ZERO_SUPPLY");
    });

    it("Should revert when token0 price is 0", async function () {
      const { lpOracle, oracle, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      await expect(
        lpOracle.lpPriceUSD_Q112(await pair.getAddress())
      ).to.be.revertedWith("Invalid price");
    });

    it("Should revert when token1 price is 0", async function () {
      const { lpOracle, oracle, token0, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));

      await expect(
        lpOracle.lpPriceUSD_Q112(await pair.getAddress())
      ).to.be.revertedWith("Invalid price");
    });

    it("Should handle large reserve values", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      const largeReserve = ethers.parseEther("1000000"); // 1M tokens
      await pair.setReserves(largeReserve, largeReserve);
      await pair.setTotalSupply(ethers.parseEther("1000000"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("100"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("100"));

      const lpPrice = await lpOracle.lpPriceUSD_Q112(await pair.getAddress());

      // Expected: 2 * sqrt(100 * 100) = $200 per LP
      const expectedWad = ethers.parseEther("200");
      const expectedQ112 = (expectedWad * Q112) / WAD;
      
      expect(lpPrice).to.equal(expectedQ112);
    });
  });

  describe("lpPriceUSD_WAD", function () {
    it("Should correctly convert Q112 to WAD", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      const lpPriceWad = await lpOracle.lpPriceUSD_WAD(await pair.getAddress());

      // Expected: ~$20 in WAD
      const expected = ethers.parseEther("20");
      expect(lpPriceWad).to.be.closeTo(expected, ethers.parseEther("0.01"));
    });
  });

    describe("redeemableUsdPerLpQ112", function () {
    it("Should calculate redeemable value correctly in Q112", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);
      // 100 of each token, $10 each = $2000 total
      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100")); // 100 LP tokens

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      const redeemable = await lpOracle.redeemableUsdPerLpQ112(await pair.getAddress());

      // Expected: $2000 / 100 = $20 per LP in Q112
      const expectedWad = ethers.parseEther("20");
      const expectedQ112 = (expectedWad * Q112) / WAD;

      expect(redeemable).to.equal(expectedQ112);
    });

    it("Should handle imbalanced reserves in redeemable calculation", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      // 200 token0 at $5 = $1000, 50 token1 at $20 = $1000, total $2000
      await pair.setReserves(ethers.parseEther("200"), ethers.parseEther("50"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("5"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("20"));

      const redeemable = await lpOracle.redeemableUsdPerLpQ112(await pair.getAddress());

      // Expected: $2000 / 100 = $20 per LP in Q112
      const expectedWad = ethers.parseEther("20");
      const expectedQ112 = (expectedWad * Q112) / WAD;

      expect(redeemable).to.equal(expectedQ112);
    });

    it("Should return 0 when reserves are 0", async function () {
      const { lpOracle, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(0, 0);
      await pair.setTotalSupply(ethers.parseEther("100"));

      const redeemable = await lpOracle.redeemableUsdPerLpQ112(await pair.getAddress());
      expect(redeemable).to.equal(0);
    });

    it("Should revert when token prices are 0", async function () {
      const { lpOracle, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await expect(
        lpOracle.redeemableUsdPerLpQ112(await pair.getAddress())
      ).to.be.revertedWith("LPOracle: ZERO_TOKEN_PRICE");
    });
  });

  describe("redeemableUsdPerLpScaled", function () {
    it("Should correctly convert redeemable value to WAD", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      const redeemable = await lpOracle.redeemableUsdPerLpScaled(await pair.getAddress());

      // Expected: ~$20 in WAD
      expect(redeemable).to.be.closeTo(ethers.parseEther("20"), ethers.parseEther("0.01"));
    });

    it("Should fit in uint144", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      const redeemable = await lpOracle.redeemableUsdPerLpScaled(await pair.getAddress());

      // Verify it's within uint144 range
      const maxUint144 = 2n ** 144n - 1n;
      expect(redeemable).to.be.lte(maxUint144);
    });
  });

  describe("Fair price vs Redeemable value comparison", function () {
    it("Fair price should equal redeemable value for balanced pool with equal prices", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      await pair.setReserves(ethers.parseEther("100"), ethers.parseEther("100"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("10"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("10"));

      const fairPrice = await lpOracle.lpPriceUSD_WAD(await pair.getAddress());
      const redeemable = await lpOracle.redeemableUsdPerLpScaled(await pair.getAddress());

      // They should be very close (geometric mean = arithmetic mean when values are equal)
      expect(fairPrice).to.be.closeTo(redeemable, ethers.parseEther("0.01"));
    });

    it("Fair price should be lower than redeemable for imbalanced reserves (sanity check)", async function () {
      const { lpOracle, oracle, token0, token1, pair } = await networkHelpers.loadFixture(deployContracts);

      // Heavily imbalanced: 1000 token0, 10 token1
      await pair.setReserves(ethers.parseEther("1000"), ethers.parseEther("10"));
      await pair.setTotalSupply(ethers.parseEther("100"));

      await oracle.setLastPrice(await token0.getAddress(), ethers.parseEther("1"));
      await oracle.setLastPrice(await token1.getAddress(), ethers.parseEther("100"));

      const fairPrice = await lpOracle.lpPriceUSD_WAD(await pair.getAddress());
      const redeemable = await lpOracle.redeemableUsdPerLpScaled(await pair.getAddress());

      // Geometric mean <= arithmetic mean (with equality only when values are equal)
      expect(fairPrice).to.be.lte(redeemable);
    });
  });
});