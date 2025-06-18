# @version 0.4.1

"""
@title sfrxUSD <--> USDaf
@license MIT
@author asymmetry.finance
@notice Swaps sfrxUSD for USDaf and vice versa
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

from ..interfaces import IExchange

from ..periphery import ownable_2step as ownable
from ..periphery import sweep
from ..periphery import curve_stableswap_swapper as curve_stableswap


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


# USDaf/USDT Curve StableNG Pool
USDC_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 1
USDAF_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 0
USDAF_USDC_CURVE_POOL: constant(address) = 0x95591348FE9718bE8bfa3afcC9b017D9Ec18A7fa

# Curve FRAX/USDC StableNG Pool
FRAX_INDEX_FRAX_USDC_CURVE_POOL: constant(uint256) = 0
USDC_INDEX_FRAX_USDC_CURVE_POOL: constant(uint256) = 1
FRAX_USDC_CURVE_POOL: constant(address) = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2

# Curve FRAX/frxUSD StableNG Pool
FRAX_INDEX_FRAX_FRXUSD_CURVE_POOL: constant(uint256) = 0
FRXUSD_INDEX_FRAX_FRXUSD_CURVE_POOL: constant(uint256) = 1
FRAX_FRXUSD_CURVE_POOL: constant(address) = 0xBBaf8B2837CBbc7146F5bC978D6F84db0BE1CAcc

# Token addresses
USDAF: constant(IERC20) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
USDC: constant(IERC20) = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
FRAX: constant(IERC20) = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e)
FRXUSD: constant(IERC20) = IERC20(0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29)
SFRXUSD: constant(IERC4626) = IERC4626(0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6)


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
    self._max_approve(USDC, FRAX_USDC_CURVE_POOL)
    self._max_approve(FRAX, FRAX_USDC_CURVE_POOL)
    self._max_approve(FRAX, FRAX_FRXUSD_CURVE_POOL)
    self._max_approve(FRXUSD, FRAX_FRXUSD_CURVE_POOL)
    self._max_approve(FRXUSD, SFRXUSD.address)


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
    return SFRXUSD.address


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

    # USDC --> FRAX
    amount_out = curve_stableswap.swapOld(
        USDC_INDEX_FRAX_USDC_CURVE_POOL,
        FRAX_INDEX_FRAX_USDC_CURVE_POOL,
        amount_out,
        FRAX_USDC_CURVE_POOL,
    )

    # FRAX --> frxUSD
    amount_out = curve_stableswap.swap(
        FRAX_INDEX_FRAX_FRXUSD_CURVE_POOL,
        FRXUSD_INDEX_FRAX_FRXUSD_CURVE_POOL,
        amount_out,
        FRAX_FRXUSD_CURVE_POOL,
        self,
    )

    # frxUSD --> sfrxUSD
    amount_out = extcall SFRXUSD.deposit(amount_out, msg.sender)

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull sfrxUSD && --> frxUSD
    extcall SFRXUSD.redeem(amount, self, msg.sender)

    # frxUSD --> FRAX
    amount_out: uint256 = curve_stableswap.swap(
        FRXUSD_INDEX_FRAX_FRXUSD_CURVE_POOL,
        FRAX_INDEX_FRAX_FRXUSD_CURVE_POOL,
        amount,
        FRAX_FRXUSD_CURVE_POOL,
        self,
    )

    # FRAX --> USDC
    amount_out = curve_stableswap.swapOld(
        FRAX_INDEX_FRAX_USDC_CURVE_POOL,
        USDC_INDEX_FRAX_USDC_CURVE_POOL,
        amount_out,
        FRAX_USDC_CURVE_POOL,
    )

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
