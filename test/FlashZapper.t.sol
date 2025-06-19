// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// import {ICurvePool} from "./interfaces/ICurvePool.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ITroveManager} from "./interfaces/ITroveManager.sol";
import {ISortedTroves} from "./interfaces/ISortedTroves.sol";
import {IHintHelpers} from "./interfaces/IHintHelpers.sol";
import {IBorrowerOperations} from "./interfaces/IBorrowerOperations.sol";

import "./Base.sol";

contract FlashZapperTests is Base {

    address public whale = address(69);

    uint256 public constant ETH_GAS_COMPENSATION = 0.0375 ether;
    uint256 public constant MIN_DEBT = 2000 * 1e18;
    uint256 public constant MIN_ANNUAL_INTEREST_RATE = 1e18 / 100 / 2;

    IHintHelpers public constant HINT_HELPERS = IHintHelpers(0x9E690678B7d2c2F5C094AD89d5c742CFcB02Ed8F);

    function setUp() public override {
        Base.setUp();
        _setParams(scrvusd_branchIndex);
    }

    function test_leverUp(
        uint256 _amount
    ) public returns (uint256 _troveId) {
        vm.assume(_amount > MIN_FUZZ_ && _amount < MAX_FUZZ_);
        _amount = MIN_FUZZ_; // 3,000
        uint256 _leverageRatio = 8 * 1e18;

        _troveId = _openTrove(_amount);

        (uint256 _flashLoanAmount, uint256 _debt) = _leverup_amounts(_troveId, _leverageRatio);

        vm.prank(user);
        FLASH_ZAPPER.lever_up_trove(
            _troveId,
            _flashLoanAmount, // flash_loan_amount
            _debt, // usdaf_amount
            type(uint256).max // max_upfront_fee
        );

        (uint256 _price,) = IPriceOracle(PRICE_ORACLE).fetchPrice();
        uint256 _capital = _amount - (MIN_DEBT * 1e18 / _price);
        uint256 _expectedCollateral = _capital * _leverageRatio / 1e18;
        uint256 _expectedDebt = _debt + MIN_DEBT;
        (uint256 _debtAfter, uint256 _collateralAfter) = _getTroveData(_troveId);

        // Check expected trove data
        assertApproxEqRel(_collateralAfter, _expectedCollateral, 1e15, "check_leverUp: E0"); // 0.1% diff allowed
        assertApproxEqRel(_debtAfter, _expectedDebt, 1e15, "check_leverUp: E1"); // 0.1% diff allowed

        uint256 expectedCR = 1e18 * 1e18 / LTV;
        uint256 _currentCR = ITroveManager(TROVE_MANAGER).getCurrentICR(_troveId, _price);

        // Check leverage ratio
        assertApproxEqRel(_currentCR, expectedCR, 1e16, "check_leverUp: E2"); // 1% diff allowed

        // Check user balances
        assertGe(USDAF.balanceOf(user), MIN_DEBT, "check_leverUp: E3");
        assertEq(COLLATERAL_TOKEN.balanceOf(user), 0, "check_leverUp: E4");
        assertEq(CRVUSD.balanceOf(user), 0, "check_leverUp: E5");

        // Check zapper balances
        assertEq(USDAF.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E6");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E7");
        assertEq(CRVUSD.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E8");

        // Check exchange
        assertEq(USDAF.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E9");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E10");
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E11");
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    function _openTrove(
        uint256 _collAmount
    ) internal returns (uint256) {
        // open a massive trove to make sure TCRBelowCCR is never hit
        _openTrove(10_000_000 ether, whale);

        // open a trove for the user
        return _openTrove(_collAmount, user);
    }

    function _openTrove(uint256 _collAmount, address _user) internal returns (uint256 _troveId) {
        airdrop(address(WETH), _user, ETH_GAS_COMPENSATION);
        airdrop(address(COLLATERAL_TOKEN), _user, _collAmount);
        (uint256 _upperHint, uint256 _lowerHint) = _findHints();
        vm.startPrank(_user);
        COLLATERAL_TOKEN.approve(BORROWER_OPERATIONS, _collAmount);
        WETH.approve(BORROWER_OPERATIONS, ETH_GAS_COMPENSATION);
        _troveId = IBorrowerOperations(BORROWER_OPERATIONS).openTrove(
            _user, // owner
            block.timestamp, // ownerIndex
            _collAmount,
            MIN_DEBT, // boldAmount
            _upperHint,
            _lowerHint,
            MIN_ANNUAL_INTEREST_RATE, // annualInterestRate
            type(uint256).max, // maxUpfrontFee
            address(0), // addManager
            address(FLASH_ZAPPER), // removeManager
            address(FLASH_ZAPPER) // receiver
        );
        vm.stopPrank();
    }

    function _findHints() internal view returns (uint256 _upperHint, uint256 _lowerHint) {
        // Find approx hint (off-chain)
        (uint256 _approxHint,,) = HINT_HELPERS.getApproxHint({
            _collIndex: BRANCH_INDEX,
            _interestRate: MIN_ANNUAL_INTEREST_RATE,
            _numTrials: _sqrt(100 * ITroveManager(TROVE_MANAGER).getTroveIdsCount()),
            _inputRandomSeed: block.timestamp
        });

        // Find concrete insert position (off-chain)
        (_upperHint, _lowerHint) =
            ISortedTroves(SORTED_TROVES).findInsertPosition(MIN_ANNUAL_INTEREST_RATE, _approxHint, _approxHint);
    }

    function _sqrt(
        uint256 y
    ) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _getTroveData(
        uint256 _troveId
    ) internal view returns (uint256, uint256) {
        ITroveManager.LatestTroveData memory _troveData = ITroveManager(TROVE_MANAGER).getLatestTroveData(_troveId);
        return (_troveData.entireDebt, _troveData.entireColl);
    }

    function _leverup_amounts(uint256 _troveId, uint256 _leverageRatio) internal returns (uint256, uint256) {
        (uint256 _price,) = IPriceOracle(PRICE_ORACLE).fetchPrice();
        uint256 _currentCR = ITroveManager(TROVE_MANAGER).getCurrentICR(_troveId, _price);
        uint256 _currentLR = _currentCR * 1e18 / (_currentCR - 1e18);
        assertGt(_leverageRatio, _currentLR, "_leverup_amounts: E0");

        (, uint256 _currentCollateral) = _getTroveData(_troveId);
        uint256 _flashLoanAmountInCollateral = _currentCollateral * _leverageRatio / _currentLR - _currentCollateral;
        uint256 _flashLoanAmountInUSD = (_flashLoanAmountInCollateral * _price) / 1e18;
        uint256 _debtNeeded = _flashLoanAmountInUSD * 105 / 100; // 5% slippage

        return (_flashLoanAmountInUSD, _debtNeeded);
    }

}
