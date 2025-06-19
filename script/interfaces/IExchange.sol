// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IExchange {

    function swap(uint256 amount, uint256 minAmount, bool fromToken) external returns (uint256);

}
