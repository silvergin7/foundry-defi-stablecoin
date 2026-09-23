// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view returns (bool) {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Weth Value: ", wethValue);
        console.log("Wbtc Value: ", wbtcValue);
        console.log("Total Supply: ", totalSupply);
        console.log("Times Mint called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
        return true;
    }

    function invariant_gettersShouldNotRevert() public view {
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getPrecision();
        dsce.getAdditionalFeedPrecision();
        dsce.getLiquidationThreshold();
        dsce.getLiquidationPrecision();
        dsce.getMinHealthFactor();
        dsce.getDsc();
        dsce.getAccountCollateralValue(msg.sender);
        dsce.getCollateralBalanceOfUser(msg.sender, weth);
        dsce.getAccountInformation(msg.sender);
        dsce.getHealthFactor(msg.sender);
        dsce.getUsdValue(weth, 1 ether);
        dsce.getTokenAmountFromUsd(weth, 1 ether);
        dsce.getCollateralTokenPriceFeed(weth);
        dsce.calculateHealthFactor(1 ether, 1 ether);
    }
}
