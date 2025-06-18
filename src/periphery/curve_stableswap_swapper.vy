# @version 0.4.1

"""
@title CurveStableSwap Swapper
@license MIT
@author asymmetry.finance
@notice curve_stableswap_swapper.vy swaps tokens on a Curve StableSwap pool
"""

from ..interfaces import ICurveStableSwap
from ..interfaces import ICurveStableSwapOld


# ============================================================================================
# Internal functions
# ============================================================================================


def swap(
    from_index: uint256,
    to_index: uint256,
    amount_in: uint256,
    pool: address,
    receiver: address,
) -> uint256:
    """
    @notice Swaps tokens on a Curve StableSwap pool
    @param from_index Index of the token to swap from
    @param to_index Index of the token to swap to
    @param amount_in Amount of the token to swap
    @param pool Address of the Curve StableNG pool
    @param receiver Address that will receive the swapped tokens
    @return Amount of the token received after the swap
    """
    return extcall ICurveStableSwap(pool).exchange(
        convert(from_index, int128),
        convert(to_index, int128),
        amount_in,
        0,  # min_amount_out
        receiver,
    )


def swapOld(
    from_index: uint256,
    to_index: uint256,
    amount_in: uint256,
    pool: address,
) -> uint256:
    """
    @notice Swaps tokens on an OLD Curve StableSwap pool
    @dev Difference is there's no receiver parameter
    @param from_index Index of the token to swap from
    @param to_index Index of the token to swap to
    @param amount_in Amount of the token to swap
    @param pool Address of the Curve StableNG pool
    @return Amount of the token received after the swap
    """
    return extcall ICurveStableSwapOld(pool).exchange(
        convert(from_index, int128),
        convert(to_index, int128),
        amount_in,
        0,  # min_amount_out
    )


def swap_underlying(
    from_index: uint256,
    to_index: uint256,
    amount_in: uint256,
    pool: address,
    receiver: address,
) -> uint256:
    """
    @notice Swap underlying coins in a Curve StableSwap pool
    @param from_index Index of the token to swap from
    @param to_index Index of the token to swap to
    @param amount_in Amount of the token to swap
    @param pool Address of the Curve StableNG pool
    @param receiver Address that will receive the swapped tokens
    @return Amount of the token received after the swap
    """
    return extcall ICurveStableSwap(pool).exchange_underlying(
        convert(from_index, int128),
        convert(to_index, int128),
        amount_in,
        0,  # min_amount_out
        receiver,
    )
