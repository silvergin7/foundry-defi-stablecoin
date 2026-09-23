// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {
    DecentralizedStableCoin,
    DecentralizedStableCoin__MustBeMoreThanZero,
    DecentralizedStableCoin__BurnAmountExceedsBalance,
    DecentralizedStableCoin__NotZeroAddress
} from "../../src/DecentralizedStableCoin.sol";
import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin coin;
    address public USER = makeAddr("user");

    function setUp() public {
        coin = new DecentralizedStableCoin(address(this));
    }

    function testMint() public {
        bool minted = coin.mint(USER, 100 ether);
        assertTrue(minted);
        assertEq(coin.balanceOf(USER), 100 ether);
    }

    function testRevertsIfMintToZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin__NotZeroAddress.selector);
        coin.mint(address(0), 1 ether);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin__MustBeMoreThanZero.selector);
        coin.mint(USER, 0);
    }

    function testRevertsIfNonOwnerMints() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        coin.mint(USER, 1 ether);
    }

    function testBurn() public {
        coin.mint(address(this), 100 ether);
        coin.burn(40 ether);
        assertEq(coin.balanceOf(address(this)), 60 ether);
    }

    function testRevertsIfBurnAmountIsZero() public {
        coin.mint(address(this), 100 ether);
        vm.expectRevert(DecentralizedStableCoin__MustBeMoreThanZero.selector);
        coin.burn(0);
    }

    function testRevertsIfBurnAmountExceedsBalance() public {
        coin.mint(address(this), 100 ether);
        vm.expectRevert(DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        coin.burn(101 ether);
    }

    function testRevertsIfNonOwnerBurns() public {
        coin.mint(address(this), 100 ether);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        coin.burn(1 ether);
    }
}
