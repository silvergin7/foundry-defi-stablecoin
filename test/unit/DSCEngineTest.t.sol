// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    /////////////////
    // Constructor Tests //
    /////////////////

    function testRevertsIfTokenLengthDOesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanDepositCollateral() public depositedCollateral {
        uint256 collateral = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateral, AMOUNT_COLLATERAL);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        dsce.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        FalseTransferToken token = new FalseTransferToken();
        tokens[0] = address(token);
        feeds[0] = ethUsdPriceFeed;
        DSCEngine engine = new DSCEngine(tokens, feeds, address(dsc));

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.depositCollateral(address(token), AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralAndMintDsc() public depositedCollateralAndMintedDsc {
        uint256 collateral = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateral, AMOUNT_COLLATERAL);
        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expected = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expected);
    }

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        // $100 minted, $20,000 collateral, 50% threshold -> 10,000 / 100 = 100
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, 100 ether);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);
        assertEq(dsce.getHealthFactor(USER), 0.9 ether);
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testRevertsIfMintAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testRevertsIfMintBreaksHealthFactor() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert();
        dsce.mintDsc(10001 ether);
    }

    function testRevertsIfMintFails() public depositedCollateral {
        vm.mockCall(address(dsc), abi.encodeWithSelector(dsc.mint.selector, USER, AMOUNT_TO_MINT), abi.encode(false));

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dsce.mintDsc(AMOUNT_TO_MINT);
    }

    ////////////////////////
    // redeem / burn Tests //
    ////////////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testCanRedeemCollateral() public depositedCollateralAndMintedDsc {
        vm.prank(USER);
        dsce.redeemCollateral(weth, 1 ether);
        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL - 1 ether);
    }

    function testRevertsIfRedeemBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 10000 ether);
        vm.expectRevert();
        dsce.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    function testRevertsIfRedeemTransferFails() public {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        FalseTransferOutToken token = new FalseTransferOutToken();
        tokens[0] = address(token);
        feeds[0] = ethUsdPriceFeed;
        DSCEngine engine = new DSCEngine(tokens, feeds, address(dsc));

        vm.startPrank(USER);
        engine.depositCollateral(address(token), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.redeemCollateral(address(token), 1 ether);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);
    }

    function testRevertsIfBurnTransferFails() public depositedCollateralAndMintedDsc {
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(dsc.transferFrom.selector, USER, address(dsce), AMOUNT_TO_MINT / 2),
            abi.encode(false)
        );

        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.burnDsc(AMOUNT_TO_MINT / 2);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.redeemCollateralForDsc(weth, 1 ether, AMOUNT_TO_MINT / 2);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT / 2);
        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL - 1 ether);
    }

    //////////////////////
    // liquidate Tests //
    //////////////////////

    function testRevertsIfLiquidateAmountIsZero() public {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }

    function testRevertsIfHealthFactorIsOk() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, 1 ether);
        vm.stopPrank();
    }

    function testCanLiquidate() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 1000 ether);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(150e8);

        ERC20Mock(weth).mint(LIQUIDATOR, 20 ether);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), 20 ether);
        dsce.depositCollateralAndMintDsc(weth, 20 ether, 200 ether);
        dsc.approve(address(dsce), 200 ether);

        uint256 balanceBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        dsce.liquidate(weth, USER, 100 ether);
        vm.stopPrank();

        assertGt(ERC20Mock(weth).balanceOf(LIQUIDATOR), balanceBefore);
    }

    function testRevertsIfHealthFactorNotImproved() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 10000 ether);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(10e8);

        ERC20Mock(weth).mint(LIQUIDATOR, 20 ether);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), 20 ether);
        dsce.depositCollateralAndMintDsc(weth, 20 ether, 10 ether);
        dsc.approve(address(dsce), 10 ether);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(weth, USER, 1 ether);
        vm.stopPrank();
    }

    function testMockAggregatorViewHelpers() public {
        MockV3Aggregator feed = MockV3Aggregator(ethUsdPriceFeed);
        feed.updateRoundData(2, 1000e8, block.timestamp, block.timestamp);

        (uint80 roundId, int256 answer,,,) = feed.getRoundData(2);
        assertEq(roundId, 2);
        assertEq(answer, 1000e8);
        assertEq(feed.description(), "v0.6/tests/MockV3Aggregator.sol");
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(ethUsdPriceFeed)), 3 hours);
    }

    function testRevertsOnStalePrice() public {
        vm.warp(block.timestamp + 3 hours + 1 seconds);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        dsce.getUsdValue(weth, 1 ether);
    }

    function testCanRedeemAllCollateralWithoutDebt() public depositedCollateral {
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), 0);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        ERC20Mock(weth).mint(LIQUIDATOR, 20 ether);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), 20 ether);
        dsce.depositCollateralAndMintDsc(weth, 20 ether, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT)
            + (
                dsce.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) * dsce.getLiquidationBonus()
                    / dsce.getLiquidationPrecision()
            );
        assertEq(liquidatorWethBalance, expectedWeth);
        assertEq(liquidatorWethBalance, 6_111_111_111_111_111_110);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    function testGetCollateralTokenPriceFeed() public view {
        assertEq(dsce.getCollateralTokenPriceFeed(weth), ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        assertEq(dsce.getMinHealthFactor(), 1e18);
    }

    function testGetLiquidationThreshold() public view {
        assertEq(dsce.getLiquidationThreshold(), 50);
    }

    function testGetDsc() public view {
        assertEq(dsce.getDsc(), address(dsc));
    }

    function testLiquidationPrecision() public view {
        assertEq(dsce.getLiquidationPrecision(), 100);
    }

    function testGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValue) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValue, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
    }
}

contract FalseTransferToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract FalseTransferOutToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}
