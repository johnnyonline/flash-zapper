# @version 0.4.1

"""
@title crvUSD <--> scrvUSD
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for scrvUSD and vice versa
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

from ..interfaces import IExchange


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# Token addresses
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
    return SCRVUSD.address


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
    @notice Swaps from token to collateral
    @param amount Amount of token to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)
    amount_out: uint256 = extcall SCRVUSD.deposit(amount, msg.sender)
    assert amount_out >= min_amount, "slippage rekt you"
    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to token
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of token to receive
    @return Amount of token received
    """
    amount_out: uint256 = extcall SCRVUSD.redeem(amount, msg.sender, msg.sender)
    assert amount_out >= min_amount, "slippage rekt you"
    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
