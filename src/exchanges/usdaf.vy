# @version 0.4.1

"""
@title crvUSD <--> USDaf
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for USDaf and vice versa
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


# USDaf/USDC Curve StableNG Pool
USDC_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 1
USDAF_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 0
USDAF_USDC_CURVE_POOL: constant(address) = 0x95591348FE9718bE8bfa3afcC9b017D9Ec18A7fa

# crvUSD/USDC Curve StableNG Pool
USDC_INDEX_CRVUSD_USDC_POOL: constant(uint256) = 0
CRVUSD_INDEX_CRVUSD_USDC_POOL: constant(uint256) = 1
CRVUSD_USDC_POOL: constant(address) = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E

# Token addresses
USDAF: constant(IERC20) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
USDC: constant(IERC20) = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)


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
    self._max_approve(USDC, CRVUSD_USDC_POOL)
    self._max_approve(CRVUSD, CRVUSD_USDC_POOL)


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def TOKEN() -> address:
    """
    @notice Returns the address of the token
    @return Address of the token
    """
    return CRVUSD.address


@external
@view
def PAIRED_WITH() -> address:
    """
    @notice Returns the address of the paired with token
    @return Address of the paired token
    """
    return USDAF.address


# ============================================================================================
# Mutative functions
# ============================================================================================


@external
def swap(amount: uint256, min_amount: uint256, from_token: bool) -> uint256:
    """
    @notice Swaps between crvUSD and the paired token
    @param amount Amount of tokens to swap
    @param min_amount Minimum amount of tokens to receive
    @param from_token If true, swap from crvUSD to the paired token, otherwise swap from the paired token to crvUSD
    @return Amount of tokens received
    """
    return (self._swap_from(amount, min_amount) if from_token else self._swap_to(amount, min_amount))


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
    # Pull crvUSD
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # crvUSD --> USDC
    amount_out: uint256 = curve_stableswap.swap(
        CRVUSD_INDEX_CRVUSD_USDC_POOL,
        USDC_INDEX_CRVUSD_USDC_POOL,
        amount,
        CRVUSD_USDC_POOL,
        self,
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


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
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

    # USDC --> crvUSD
    amount_out = curve_stableswap.swap(
        USDC_INDEX_CRVUSD_USDC_POOL,
        CRVUSD_INDEX_CRVUSD_USDC_POOL,
        amount_out,
        CRVUSD_USDC_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
