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

from ..periphery import curve_stableswap_swapper as curve_stableswap


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# scrvUSD/USDaf Curve StableNG Pool
SCRVUSD_INDEX_CURVE_POOL: constant(uint256) = 0
USDAF_INDEX_CURVE_POOL: constant(uint256) = 1
CURVE_POOL: constant(address) = 0x3bE454C4391690ab4DDae3Fb987c8147b8Ecc08A

# Token addresses
USDAF: constant(IERC20) = IERC20(0x9Cf12ccd6020b6888e4D4C4e4c7AcA33c1eB91f8)
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
SCRVUSD: constant(IERC4626) = IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    self._max_approve(IERC20(SCRVUSD.address), CURVE_POOL)
    self._max_approve(USDAF, CURVE_POOL)
    self._max_approve(CRVUSD, SCRVUSD.address)


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
    return (self.swap_from(amount, min_amount) if from_token else self.swap_to(amount, min_amount))


# ============================================================================================
# Internal functions
# ============================================================================================


def swap_from(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from USDaf to collateral
    @param amount Amount of USDaf to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    # Pull crvUSD
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # crvUSD --> scrvUSD
    amount_out: uint256 = extcall SCRVUSD.deposit(amount, self)

    # scrvUSD --> USDaf
    amount_out = curve_stableswap.swap(
        SCRVUSD_INDEX_CURVE_POOL,
        USDAF_INDEX_CURVE_POOL,
        amount_out,
        CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull USDaf
    extcall USDAF.transferFrom(msg.sender, self, amount, default_return_value=True)

    # USDaf --> scrvUSD
    amount_out: uint256 = curve_stableswap.swap(
        USDAF_INDEX_CURVE_POOL,
        SCRVUSD_INDEX_CURVE_POOL,
        amount,
        CURVE_POOL,
        self,
    )

    # scrvUSD --> crvUSD
    amount_out = extcall SCRVUSD.redeem(amount_out, msg.sender, self)

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
