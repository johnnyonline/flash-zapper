# @version 0.4.1

"""
@title crvUSD <--> sUSDS
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for sUSDS and vice versa
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


# scrvUSD/sUSDS Curve StableNG Pool
SCRVUSD_INDEX_CURVE_POOL: constant(uint256) = 0
SUSDS_INDEX_CURVE_POOL: constant(uint256) = 1
CURVE_POOL: constant(address) = 0xfD1627E3f3469C8392C8c3A261D8F0677586e5e1

# Token addresses
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
SUSDS: constant(IERC20) = IERC20(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD)
SCRVUSD: constant(IERC4626) = IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    self._max_approve(SUSDS, CURVE_POOL)
    self._max_approve(IERC20(SCRVUSD.address), CURVE_POOL)
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
    return SUSDS.address


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
    @notice Swaps from crvUSD to collateral
    @param amount Amount of crvUSD to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    # Pull crvUSD
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # crvUSD --> scrvUSD
    amount_out: uint256 = extcall SCRVUSD.deposit(amount, self)

    # scrvUSD --> sUSDS
    amount_out = curve_stableswap.swap(
        SCRVUSD_INDEX_CURVE_POOL,
        SUSDS_INDEX_CURVE_POOL,
        amount_out,
        CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to crvUSD
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of crvUSD to receive
    @return Amount of crvUSD received
    """
    # Pull sUSDS
    extcall SUSDS.transferFrom(msg.sender, self, amount, default_return_value=True)

    # sUSDS --> scrvUSD
    amount_out: uint256 = curve_stableswap.swap(
        SUSDS_INDEX_CURVE_POOL,
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
