// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";

contract HelperConfigTest is Test {
    function testSepoliaConfig() public {
        vm.chainId(11155111);
        vm.setEnv("PRIVATE_KEY", "1");

        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        assertEq(wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        assertEq(weth, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
        assertEq(wbtc, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        assertEq(deployerKey, 1);
    }

    function testAnvilConfigReusesExistingFeeds() public {
        HelperConfig config = new HelperConfig();
        (address firstFeed,,,,) = config.activeNetworkConfig();

        HelperConfig.NetworkConfig memory again = config.getOrCreateAnvilEthConfig();
        assertEq(firstFeed, again.wethUsdPriceFeed);
        assertTrue(firstFeed != address(0));
    }
}
