# @version 0.4.1

"""
@title sUSDS <--> USDaf
@license MIT
@author asymmetry.finance
@notice Swaps sUSDS for USDaf and vice versa
"""

from ethereum.ercs import IERC20

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
USDT_INDEX_USDAF_USDT_CURVE_POOL: constant(uint256) = 2
USDAF_INDEX_USDAF_USDT_CURVE_POOL: constant(uint256) = 0
USDAF_USDT_CURVE_POOL: constant(address) = 0x95591348FE9718bE8bfa3afcC9b017D9Ec18A7fa

# Curve sUSDS/USDT StableNG Pool
SUSDS_INDEX_SUSDS_USDT_CURVE_POOL: constant(uint256) = 0
USDT_INDEX_SUSDS_USDT_CURVE_POOL: constant(uint256) = 1
SUSDS_USDT_CURVE_POOL: constant(address) = 0x00836Fe54625BE242BcFA286207795405ca4fD10

# Token addresses
USDAF: constant(IERC20) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
USDT: constant(IERC20) = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7)
USDS: constant(IERC20) = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F)
SUSDS: constant(IERC20) = IERC20(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD)


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

    self._max_approve(USDAF, USDAF_USDT_CURVE_POOL)
    self._max_approve(USDT, USDAF_USDT_CURVE_POOL)
    self._max_approve(USDT, SUSDS_USDT_CURVE_POOL)
    self._max_approve(SUSDS, SUSDS_USDT_CURVE_POOL)


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
    return SUSDS.address


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

    # USDaf --> USDT
    amount_out: uint256 = curve_stableswap.swap_underlying(
        USDAF_INDEX_USDAF_USDT_CURVE_POOL,
        USDT_INDEX_USDAF_USDT_CURVE_POOL,
        amount,
        USDAF_USDT_CURVE_POOL,
        self,
    )

    # USDT --> sUSDS
    amount_out = curve_stableswap.swap(
        USDT_INDEX_SUSDS_USDT_CURVE_POOL,
        SUSDS_INDEX_SUSDS_USDT_CURVE_POOL,
        amount_out,
        SUSDS_USDT_CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull sUSDS
    extcall SUSDS.transferFrom(msg.sender, self, amount, default_return_value=True)

    # sUSDS --> USDT
    amount_out: uint256 = curve_stableswap.swap(
        SUSDS_INDEX_SUSDS_USDT_CURVE_POOL,
        USDT_INDEX_SUSDS_USDT_CURVE_POOL,
        amount,
        SUSDS_USDT_CURVE_POOL,
        self,
    )

    # USDT --> USDaf
    amount_out = curve_stableswap.swap_underlying(
        USDT_INDEX_USDAF_USDT_CURVE_POOL,
        USDAF_INDEX_USDAF_USDT_CURVE_POOL,
        amount_out,
        USDAF_USDT_CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
