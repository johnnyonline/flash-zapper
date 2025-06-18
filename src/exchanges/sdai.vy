# @version 0.4.1

"""
@title sDAI <--> USDaf
@license MIT
@author asymmetry.finance
@notice Swaps sDAI for USDaf and vice versa
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

from ..interfaces import IExchange

from ..periphery import ownable_2step as ownable
from ..periphery import sweep
from ..periphery import curve_stableswap_swapper as curve_stableswap
from ..periphery import curve_3pool_swapper as curve_3pool


# ============================================================================================
# Modules
# ============================================================================================


initializes: ownable
exports: (
    ownable.owner,
    ownable.pending_owner,
    ownable.transfer_ownership,
    ownable.accept_ownership,
)

initializes: sweep[ownable := ownable]
exports: sweep.sweep_token


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# USDaf/USDC Curve StableNG Pool
USDC_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 1
USDAF_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 0
USDAF_USDC_CURVE_POOL: constant(address) = 0x95591348FE9718bE8bfa3afcC9b017D9Ec18A7fa

# Curve 3Pool
DAI_INDEX_THREE_POOL: constant(uint256) = 0
USDC_INDEX_THREE_POOL: constant(uint256) = 1
THREE_POOL: constant(address) = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7

# Token addresses
USDAF: constant(IERC20) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
USDC: constant(IERC20) = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
DAI: constant(IERC20) = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F)
SDAI: constant(IERC4626) = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__(owner: address):
    """
    @notice Initialize the contract
    @param owner Address of the owner
    """
    ownable.__init__(owner)

    self._max_approve(USDAF, USDAF_USDC_CURVE_POOL)
    self._max_approve(USDC, USDAF_USDC_CURVE_POOL)
    self._max_approve(USDC, THREE_POOL)
    self._max_approve(DAI, THREE_POOL)
    self._max_approve(DAI, SDAI.address)


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def BORROW_TOKEN() -> address:
    """
    @notice Returns the address of the borrow token
    @return Address of the borrow token
    """
    return USDAF.address


@external
@view
def COLLATERAL_TOKEN() -> address:
    """
    @notice Returns the address of the collateral token
    @return Address of the collateral token
    """
    return SDAI.address


# ============================================================================================
# Mutative functions
# ============================================================================================


@external
def swap(amount: uint256, min_amount: uint256, from_af: bool) -> uint256:
    """
    @notice Swaps between USDaf and collateral
    @param amount Amount of tokens to swap
    @param min_amount Minimum amount of tokens to receive
    @param from_af True if swapping from USDaf to collateral, False if swapping from collateral to USDaf
    @return Amount of tokens received
    """
    return (self._swap_from(amount, min_amount) if from_af else self._swap_to(amount, min_amount))


# ============================================================================================
# Internal functions
# ============================================================================================


def _swap_from(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from USDaf to collateral
    @param amount Amount of USDaf to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    # Pull USDaf
    extcall USDAF.transferFrom(msg.sender, self, amount, default_return_value=True)

    # USDaf --> USDC
    amount_out: uint256 = curve_stableswap.swap_underlying(
        USDAF_INDEX_USDAF_USDC_CURVE_POOL,
        USDC_INDEX_USDAF_USDC_CURVE_POOL,
        amount,
        USDAF_USDC_CURVE_POOL,
        self,
    )

    # USDC --> DAI
    balance_before: uint256 = staticcall DAI.balanceOf(self)
    curve_3pool.swap(
        USDC_INDEX_THREE_POOL,
        DAI_INDEX_THREE_POOL,
        amount_out,
        THREE_POOL,
    )
    amount_out = staticcall DAI.balanceOf(self) - balance_before

    # DAI --> sDAI
    amount_out = extcall SDAI.deposit(amount_out, msg.sender)

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull sDAI && --> DAI
    amount_out: uint256 = extcall SDAI.redeem(amount, self, msg.sender)

    # DAI --> USDC
    balance_before: uint256 = staticcall USDC.balanceOf(self)
    curve_3pool.swap(
        DAI_INDEX_THREE_POOL,
        USDC_INDEX_THREE_POOL,
        amount_out,
        THREE_POOL,
    )
    amount_out = staticcall USDC.balanceOf(self) - balance_before

    # USDC --> USDaf
    amount_out = curve_stableswap.swap_underlying(
        USDC_INDEX_USDAF_USDC_CURVE_POOL,
        USDAF_INDEX_USDAF_USDC_CURVE_POOL,
        amount_out,
        USDAF_USDC_CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
