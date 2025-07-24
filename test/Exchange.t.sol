// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./Base.sol";

contract ExchangeTests is Base {

    function setUp() public override {
        Base.setUp();
    }

    function test_swapTo(
        uint256 _amount
    ) public {
        for (uint256 i = 0; i < params.length; i++) {
            _setParams(i);
            check_swapTo(_amount);
        }
    }

    function test_swapFrom(
        uint256 _amount
    ) public {
        for (uint256 i = 0; i < params.length; i++) {
            _setParams(i);
            check_swapFrom(_amount);
        }
    }

    function test_swapTo_usdaf(
        uint256 _amount
    ) public {
        setup_usdafParams();
        check_swapTo(_amount);
    }

    function test_swapFrom_usdaf(
        uint256 _amount
    ) public {
        setup_usdafParams();
        check_swapFrom(_amount);
    }

    // ============================================================================================
    // Tests
    // ============================================================================================

    function check_swapTo(
        uint256 _amount
    ) public {
        _amount = bound(_amount, MIN_FUZZ, MAX_FUZZ);

        uint256 _balanceBefore = CRVUSD.balanceOf(user);

        airdrop(address(WRAPPED_COLLATERAL_TOKEN), user, _amount);

        vm.startPrank(user);
        WRAPPED_COLLATERAL_TOKEN.approve(address(EXCHANGE), _amount);
        uint256 _amountOut = EXCHANGE.swap(_amount, 0, false);
        vm.stopPrank();

        // Check user balances
        assertGt(CRVUSD.balanceOf(user), 0, "check_swapTo: E0");
        assertEq(WRAPPED_COLLATERAL_TOKEN.balanceOf(user), 0, "check_swapTo: E1");

        // Check exchange balances
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_swapTo: E2");
        assertEq(WRAPPED_COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_swapTo: E3");

        // Check amount out
        assertGt(_amountOut, 0, "check_swapTo: E4");
        assertEq(CRVUSD.balanceOf(user), _balanceBefore + _amountOut, "check_swapTo: E6");
    }

    function check_swapFrom(
        uint256 _amount
    ) public {
        _amount = bound(_amount, MIN_FUZZ, MAX_FUZZ);

        uint256 _balanceBefore = WRAPPED_COLLATERAL_TOKEN.balanceOf(user);

        airdrop(address(CRVUSD), user, _amount);

        vm.startPrank(user);
        CRVUSD.approve(address(EXCHANGE), _amount);
        uint256 _amountOut = EXCHANGE.swap(_amount, 0, true);
        vm.stopPrank();

        // Check user balances
        assertGt(WRAPPED_COLLATERAL_TOKEN.balanceOf(user), 0, "check_swapFrom: E0");
        assertEq(CRVUSD.balanceOf(user), 0, "check_swapFrom: E1");

        // Check exchange balances
        assertEq(WRAPPED_COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_swapFrom: E2");
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_swapFrom: E3");

        // Check amount out
        assertGt(_amountOut, 0, "check_swapFrom: E4");
        assertEq(WRAPPED_COLLATERAL_TOKEN.balanceOf(user), _balanceBefore + _amountOut, "check_swapFrom: E6");
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    function setup_usdafParams() public {
        WRAPPED_COLLATERAL_TOKEN = USDAF;
        EXCHANGE = USDAF_EXCHANGE;
        MIN_FUZZ = MIN_FUZZ_USD;
        MAX_FUZZ = MAX_FUZZ_USD;
    }

}
