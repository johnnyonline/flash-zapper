// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../script/Deploy.s.sol";

import "forge-std/Test.sol";

abstract contract Base is Deploy, Test {

    address public user = address(420);

    uint256 public LTV;
    uint256 public BRANCH_INDEX;
    address public PRICE_ORACLE;
    address public TROVE_MANAGER;
    address public BORROWER_OPERATIONS;
    address public SORTED_TROVES;
    string public EXCHANGE_NAME;

    IERC20 public COLLATERAL_TOKEN;
    IERC20 public WRAPPED_COLLATERAL_TOKEN;
    IExchange public EXCHANGE;
    IFlashZapper public FLASH_ZAPPER;

    IERC20 public constant USDAF = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA);
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // default BTC values
    uint256 public MIN_FUZZ = 0.03 ether;
    uint256 public MAX_FUZZ = 0.1 ether;
    uint256 public MIN_LEVERAGE = 3 ether; // 3x leverage
    uint256 public MAX_LEVERAGE = 4 ether; // 4x leverage

    function setUp() public virtual {
        // notify deplyment script that this is a test
        isTest = true;

        // create fork
        uint256 _blockNumber = 22_705_584; // cache state for faster tests
        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL"), _blockNumber));

        // deploy and initialize contracts
        run();
    }

    function airdrop(address _token, address _to, uint256 _amount) public {
        _token == address(0) ? vm.deal(_to, _amount) : deal({token: _token, to: _to, give: _amount});
    }

    function _setParams(
        uint256 _index
    ) internal {
        Params memory p = params[_index];
        COLLATERAL_TOKEN = IERC20(p.collateralToken);
        WRAPPED_COLLATERAL_TOKEN = COLLATERAL_TOKEN;
        EXCHANGE = IExchange(p.exchange);
        FLASH_ZAPPER = IFlashZapper(p.flashZapper);
        LTV = p.ltv;
        PRICE_ORACLE = p.priceOracle;
        TROVE_MANAGER = p.troveManager;
        BORROWER_OPERATIONS = p.borrowerOperations;
        SORTED_TROVES = p.sortedTroves;
        BRANCH_INDEX = p.branchIndex;
        EXCHANGE_NAME = p.exchangeName;

        if (LTV == USD_LTV) {
            MIN_FUZZ = 3000 ether;
            MAX_FUZZ = 10_000 ether;
            MIN_LEVERAGE = 3 ether; // 3x leverage
            MAX_LEVERAGE = 7 ether; // 7x leverage
        }

        // Override for WBTC
        if (BRANCH_INDEX == wbtc18_branchIndex) {
            COLLATERAL_TOKEN = IERC20(WBTC);
            WRAPPED_COLLATERAL_TOKEN = IERC20(p.collateralToken);
        }
    }

}
