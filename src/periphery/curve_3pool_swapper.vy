# @version 0.4.1

"""
@title Curve3Pool Swapper
@license MIT
@author asymmetry.finance
@notice curve_3pool_swapper.vy swaps tokens on a Curve 3pool
"""

from ..interfaces import ICurve3Pool


# ============================================================================================
# Internal functions
# ============================================================================================


def swap(
    from_index: uint256,
    to_index: uint256,
    amount_in: uint256,
    pool: address,
):
    """
    @notice Swaps tokens on a Curve StableNG pool
    @param from_index Index of the token to swap from
    @param to_index Index of the token to swap to
    @param amount_in Amount of the token to swap
    @param pool Address of the Curve StableNG pool
    """
    extcall ICurve3Pool(pool).exchange(
        convert(from_index, int128),
        convert(to_index, int128),
        amount_in,
        0,  # min_amount_out
    )
