const numeric = require("numeric");
const axios = require("axios");
const mathjs = require("mathjs");
var cov = require("compute-covariance");

let portfolio = {
  tokens: {
    GOLD: {
      name: "Gold Token",
      symbol: "WBTC",
      address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      decimals: 8,
      priceFeedAddress: "0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22",
    },
    FIAT: {
      name: "USD",
      symbol: "LINK",
      address: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
      decimals: 18,
      priceFeedAddress: "0x42585eD362B3f1BCa95c640FdFf35Ef899212734",
    },
  },
};

let returns, covMatrix;

async function fetchHistoricalData(assetName) {
  // Binance API endpoint for candlestick data
  const url = `https://api.binance.com/api/v3/klines?symbol=${assetName}USDT&interval=1d&limit=1000`;
  const response = await axios.get(url);
  return response.data;
}

async function getReturnsAndCovMatrix() {
  // const apiKey = "580f60ed-b8b7-4feb-9e4a-365bbb456439";
  const assets = Object.values(portfolio.tokens).map((token) => token.symbol);

  let prices = [];
  let minLen = Infinity;
  for (let asset of assets) {
    const historicalData = await fetchHistoricalData(asset);
    const assetPrices = historicalData.map((quote) => Number(quote[4]));
    minLen = Math.min(minLen, assetPrices.length);
    prices.push(assetPrices);
  }
  // Trim all price arrays to the same length
  prices = prices.map((assetPrices) => assetPrices.slice(0, minLen));
  const returns = prices.map((assetPrices) => {
    const assetReturns = [];
    for (let i = 1; i < assetPrices.length; i++) {
      const arithmeticReturn =
        (assetPrices[i] - assetPrices[i - 1]) / assetPrices[i - 1];
      assetReturns.push(arithmeticReturn);
    }
    return assetReturns;
  });

  const covMatrix = cov(returns);

  // Return both returns and covariance matrix
  return { returns, covMatrix };
}

async function calculatePortfolio() {
  ({ returns, covMatrix } = await getReturnsAndCovMatrix());

  const numPortfolios = 100000;

  let allWeights = new Array(numPortfolios);
  let retArr = new Array(numPortfolios);
  let volArr = new Array(numPortfolios);

  for (let i = 0; i < numPortfolios; i++) {
    // Create random weights
    let weights = returns.map(() => Math.random());
    let sumWeights = numeric.sum(weights);
    weights = weights.map((w) => w / sumWeights);

    // Save weights
    allWeights[i] = weights;

    // Expected return
    retArr[i] = numeric.sum(
      returns.map((assetReturns, idx) => {
        const weightedReturns = numeric.mul(assetReturns, weights[idx]);
        return numeric.sum(weightedReturns);
      })
    );
    // Expected volatility
    let intermediate = numeric.dot(covMatrix, weights);
    volArr[i] = Math.sqrt(
      mathjs.multiply(mathjs.multiply(weights, covMatrix), weights)
    );
    // console.log(volArr[i]);
  }

  // Find the portfolio with the highest Sharpe Ratio
  let sharpeArr = retArr.map((ret, idx) => ret / volArr[idx]);

  let maxSharpeIdx = sharpeArr.indexOf(Math.max(...sharpeArr));
  let maxSrReturns = retArr[maxSharpeIdx];
  let maxSrVolatility = volArr[maxSharpeIdx];

  return allWeights[maxSharpeIdx][0] * 100;
}

calculatePortfolio().then((firstWeight) => {
  console.log("First Token Weight:", firstWeight);
});
