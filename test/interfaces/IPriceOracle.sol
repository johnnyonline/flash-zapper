// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

interface IPriceOracle {

    function fetchPrice() external returns (uint256 price, bool isOracleDown);

}
