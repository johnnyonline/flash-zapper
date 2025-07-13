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
    }

    // ============================================================================================
    // scrvUSD
    // ============================================================================================

    // function test_openLeveragedTrove_scrvusd(uint256 _amount, uint256 _leverageRatio) public {
    function test_openLeveragedTrove_scrvusd() public {
        _setParams(scrvusd_branchIndex);
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        check_openLeveragedTrove(_amount, _leverageRatio);
    }

    // function test_leverUp_scrvusd(uint256 _amount, uint256 _leverageRatio) public {
    function test_leverUp_scrvusd() public {
        _setParams(scrvusd_branchIndex);
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        check_leverUp(_amount, _leverageRatio);
    }

    // function test_leverDown_scrvusd(uint256 _amount, uint256 _leverageRatio) public {
    function test_leverDown_scrvusd() public {
        _setParams(scrvusd_branchIndex);
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        check_leverDown(_amount, _leverageRatio);
    }

    // ============================================================================================
    // tBTC
    // ============================================================================================

    // function test_openLeveragedTrove_tbtc(uint256 _amount, uint256 _leverageRatio) public {
    function test_openLeveragedTrove_tbtc() public {
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        _setParams(1);
        check_openLeveragedTrove(_amount, _leverageRatio);
    }

    // function test_setUp_tbtc(uint256 _amount, uint256 _leverageRatio) public {
    function test_setUp_tbtc() public {
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        _setParams(1);
        check_leverUp(_amount, _leverageRatio);
    }

    // function test_leverDown_tbtc(uint256 _amount, uint256 _leverageRatio) public {
    function test_leverDown_tbtc() public {
        uint256 _amount = MIN_FUZZ;
        uint256 _leverageRatio = MAX_LEVERAGE;
        _setParams(1);
        check_leverDown(_amount, _leverageRatio);
    }

    // ============================================================================================
    // Tests
    // ============================================================================================

    function check_openLeveragedTrove(uint256 _amount, uint256 _leverageRatio) public {
        // vm.assume(_amount > MIN_FUZZ && _amount < MAX_FUZZ);
        // vm.assume(_leverageRatio >= MIN_LEVERAGE && _leverageRatio <= MAX_LEVERAGE);

        (uint256 _price,) = IPriceOracle(PRICE_ORACLE).fetchPrice();

        // Estimate flash loan & debt from capital + leverage ratio
        uint256 _capitalInUSD = (_amount * _price) / 1e18;
        uint256 _flashLoanAmountUSD = (_capitalInUSD * _leverageRatio / 1e18) - _capitalInUSD;
        uint256 _debtToMint = _flashLoanAmountUSD * 102 / 100; // 5% slippage

        // Get trove hints
        (uint256 _upperHint, uint256 _lowerHint) = _findHints();

        // Airdrop user collateral & gas compensation
        airdrop(address(WETH), user, ETH_GAS_COMPENSATION);
        airdrop(address(COLLATERAL_TOKEN), user, _amount);
        vm.startPrank(user);
        COLLATERAL_TOKEN.approve(address(FLASH_ZAPPER), _amount);
        WETH.approve(address(FLASH_ZAPPER), ETH_GAS_COMPENSATION);

        // Call open_leveraged_trove
        FLASH_ZAPPER.open_leveraged_trove(
            user,
            block.timestamp, // owner_index
            _amount, // initial_collateral_amount
            _flashLoanAmountUSD, // flash_loan_amount
            _debtToMint, // usdaf_amount
            _upperHint,
            _lowerHint,
            MIN_ANNUAL_INTEREST_RATE,
            type(uint256).max // max_upfront_fee
        );
        vm.stopPrank();

        // Trove ID should be predictable
        uint256 _troveId = uint256(keccak256(abi.encode(address(FLASH_ZAPPER), user, block.timestamp)));

        // Fetch resulting trove data
        (uint256 _debtAfter, uint256 _collateralAfter) = _getTroveData(_troveId);

        uint256 _expectedCollateral = _amount + (_flashLoanAmountUSD * 1e18 / _price);
        uint256 _expectedDebt = _debtToMint;

        assertApproxEqRel(_collateralAfter, _expectedCollateral, 1e16, "check_openLeveragedTrove: E0"); // 1% diff allowed
        assertApproxEqRel(_debtAfter, _expectedDebt, 1e15, "check_openLeveragedTrove: E1"); // 0.1% diff allowed

        // Check user balances
        assertEq(USDAF.balanceOf(user), 0, "check_openLeveragedTrove: E3");
        assertEq(COLLATERAL_TOKEN.balanceOf(user), 0, "check_openLeveragedTrove: E4");
        assertGe(CRVUSD.balanceOf(user), 0, "check_openLeveragedTrove: E5"); // leftovers

        // Check zapper balances
        assertEq(USDAF.balanceOf(address(FLASH_ZAPPER)), 0, "check_openLeveragedTrove: E6");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(FLASH_ZAPPER)), 0, "check_openLeveragedTrove: E7");
        assertEq(CRVUSD.balanceOf(address(FLASH_ZAPPER)), 0, "check_openLeveragedTrove: E8");

        // Check exchange
        assertEq(USDAF.balanceOf(address(EXCHANGE)), 0, "check_openLeveragedTrove: E9");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_openLeveragedTrove: E10");
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_openLeveragedTrove: E11");
    }

    function check_leverUp(uint256 _amount, uint256 _leverageRatio) public returns (uint256 _troveId) {
        // vm.assume(_amount > MIN_FUZZ && _amount < MAX_FUZZ);
        // vm.assume(_leverageRatio >= MIN_LEVERAGE && _leverageRatio <= MAX_LEVERAGE);

        // Open a trove for the user
        _troveId = _openTrove(_amount);

        // Fetch input parameters
        (uint256 _flashLoanAmount, uint256 _debt) = _leverup_amounts(_troveId, _leverageRatio);

        // Lever up
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
        assertApproxEqRel(_collateralAfter, _expectedCollateral, 1e16, "check_leverUp: E0"); // 1% diff allowed
        assertApproxEqRel(_debtAfter, _expectedDebt, 1e15, "check_leverUp: E1"); // 0.1% diff allowed

        uint256 _expectedLTV = 1e18 - (1e18 * 1e18 / _leverageRatio);
        uint256 _expectedCR = 1e18 * 1e18 / _expectedLTV;
        uint256 _currentCR = ITroveManager(TROVE_MANAGER).getCurrentICR(_troveId, _price);

        // Check leverage ratio
        assertApproxEqRel(_currentCR, _expectedCR, 1e17, "check_leverUp: E2"); // 10% diff allowed, bc of slippage

        // Check user balances
        assertGe(USDAF.balanceOf(user), MIN_DEBT, "check_leverUp: E3");
        assertEq(COLLATERAL_TOKEN.balanceOf(user), 0, "check_leverUp: E4");
        assertGe(CRVUSD.balanceOf(user), 0, "check_leverUp: E5"); // leftovers

        // Check zapper balances
        assertEq(USDAF.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E6");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E7");
        assertEq(CRVUSD.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverUp: E8");

        // Check exchange
        assertEq(USDAF.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E9");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E10");
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_leverUp: E11");
    }

    function check_leverDown(uint256 _amount, uint256 _leverageRatio) public {
        // Open and lever up trove first
        uint256 _troveId = check_leverUp(_amount, _leverageRatio);

        // Fetch trove state and price
        (uint256 _price,) = IPriceOracle(PRICE_ORACLE).fetchPrice();
        (uint256 _debtBefore, uint256 _collateralBefore) = _getTroveData(_troveId);

        // Compute target collateral at MIN_DEBT
        uint256 _targetDebt = MIN_DEBT;
        uint256 _targetCollateral = (((_targetDebt * 1e18) / LTV) * 1e18 / _price) * 105 / 100; // Have some collateral buffer

        // Calculate how much collateral to remove and how much debt to repay
        uint256 _collateralToRemove = _collateralBefore - _targetCollateral;
        uint256 _flashLoanAmount = (_debtBefore - _targetDebt) * 105 / 100; // Add 5% slippage

        // Lever down
        vm.prank(user);
        FLASH_ZAPPER.lever_down_trove(
            _troveId,
            _flashLoanAmount,
            0, // minUSDaf
            _collateralToRemove
        );

        (uint256 _debtAfter, uint256 _collateralAfter) = _getTroveData(_troveId);

        // Check expected trove data
        assertEq(_debtAfter, _targetDebt, "check_leverDown: E0");
        assertApproxEqRel(_collateralAfter, _targetCollateral, 1e15, "check_leverDown: E1"); // 0.1% diff allowed

        // Check user balances
        assertGe(USDAF.balanceOf(user), MIN_DEBT, "check_leverDown: E2");
        assertEq(COLLATERAL_TOKEN.balanceOf(user), 0, "check_leverDown: E3");
        assertGe(CRVUSD.balanceOf(user), 0, "check_leverDown: E4"); // leftovers

        // Check zapper balances
        assertEq(USDAF.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverDown: E5");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverDown: E6");
        assertEq(CRVUSD.balanceOf(address(FLASH_ZAPPER)), 0, "check_leverDown: E7");

        // Check exchange
        assertEq(USDAF.balanceOf(address(EXCHANGE)), 0, "check_leverDown: E8");
        assertEq(COLLATERAL_TOKEN.balanceOf(address(EXCHANGE)), 0, "check_leverDown: E9");
        assertEq(CRVUSD.balanceOf(address(EXCHANGE)), 0, "check_leverDown: E10");
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
