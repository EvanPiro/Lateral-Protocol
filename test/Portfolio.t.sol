// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Portfolio.sol";
import "./MockERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IDAI {
    function mint(address user, uint256 amount) external returns (bool);

    function approve(address user, uint256 amount) external returns (bool);
}

contract PortfolioTest is Test {
    Portfolio portfolio;
    uint256 amountIn;
    address tokenIn;
    address tokenOut;
    MockERC20 private mockToken1;
    MockERC20 private mockToken2;
    uint256 public amountToMint1;
    uint256 public amountToMint2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        mockToken1 = new MockERC20();
        mockToken2 = new MockERC20();
        amountToMint1 = 1 * 10 ** 18;
        amountToMint2 = 100 * 10 ** 18;
        // IDAI(DAI).mint(address(1), amountToMint1);
        mockToken2.mint(address(1), amountToMint2);
        vm.startPrank(address(1));
        portfolio = new Portfolio();
        IDAI(WETH9).approve(address(portfolio), amountToMint1);
    }

    function testSwap() public {
        portfolio.uniswapV3(amountToMint1, WETH9, DAI);
    }
}
