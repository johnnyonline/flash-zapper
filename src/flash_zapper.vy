# @version 0.4.1

"""
@title USDaf Flash Zapper
@license MIT
@author asymmetry.finance
@notice Leverages up and down USDaf positions using a flash loan
"""
# @todo -- dont allow to update exchange
from ethereum.ercs import IERC20

from interfaces import IExchange
from interfaces import IERC3156FlashLender
from interfaces import ITroveNFT
from interfaces import IBorrowerOperations
from interfaces import IAddressesRegistry

import periphery.ownable_2step as ownable
import periphery.sweep as sweep


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
# Events
# ============================================================================================


event WrappedLeverageZapperSet:
    zapper: address


event ExchangeSet:
    exchange: address
    is_collateral: bool


# ============================================================================================
# Constants
# ============================================================================================


# ERC3156
FLASHLOAN_CALLBACK_SUCCESS: constant(bytes32) = keccak256("ERC3156FlashBorrower.onFlashLoan")

# Selector
SELECTOR_SIZE: constant(uint256) = 4

# # Open trove
# ENCODED_OPEN_TROVE_ARGS_SIZE: constant(uint256) = 416
# OPEN_TROVE_CALLDATA_SIZE: constant(uint256) = ENCODED_OPEN_TROVE_ARGS_SIZE + SELECTOR_SIZE

# Lever up
ENCODED_LEVER_UP_ARGS_SIZE: constant(uint256) = 128
LEVER_UP_CALLDATA_SIZE: constant(uint256) = ENCODED_LEVER_UP_ARGS_SIZE + SELECTOR_SIZE

# # Lever down
# ENCODED_LEVER_DOWN_ARGS_SIZE: constant(uint256) = 96
# LEVER_DOWN_CALLDATA_SIZE: constant(uint256) = ENCODED_LEVER_DOWN_ARGS_SIZE + SELECTOR_SIZE

# Token addresses
USDAF: public(constant(IERC20)) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
CRVUSD: public(constant(IERC20)) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)

# Flashloan provider
FLASH_LENDER: public(constant(IERC3156FlashLender)) = IERC3156FlashLender(0x26dE7861e213A5351F6ED767d00e0839930e9eE1)

# Trove addresses
COLLATERAL_TOKEN: public(immutable(IERC20))
TROVE_NFT: public(immutable(ITroveNFT))
BORROWER_OPERATIONS: public(immutable(IBorrowerOperations))


# ============================================================================================
# Storage
# ============================================================================================


is_wrapped_leverage_zapper_set: public(bool)
wrapped_leverage_zapper: public(address)

usdaf_exchange: public(IExchange)
collateral_exchange: public(IExchange)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__(
    owner: address,
    usdaf_exchange: address,
    collateral_exchange: address,
    addresses_registry: address,
):
    """
    @notice Initialize the contract
    @param owner Address of the owner
    @param usdaf_exchange Address of the crvUSD/USDaf exchange contract
    @param collateral_exchange Address of the crvUSD/collateral exchange contract
    @param addresses_registry Address of the AddressesRegistry contract
    """
    ownable.__init__(owner)

    _addresses_registry: IAddressesRegistry = IAddressesRegistry(addresses_registry)
    COLLATERAL_TOKEN = IERC20(staticcall _addresses_registry.collToken())
    TROVE_NFT = ITroveNFT(staticcall _addresses_registry.troveNFT())
    BORROWER_OPERATIONS = IBorrowerOperations(staticcall _addresses_registry.borrowerOperations())

    self._set_exchange(IExchange(usdaf_exchange), False)
    self._set_exchange(IExchange(collateral_exchange), True, COLLATERAL_TOKEN)

    extcall COLLATERAL_TOKEN.approve(BORROWER_OPERATIONS.address, max_value(uint256), default_return_value=True)


# ============================================================================================
# Owner functions
# ============================================================================================


@external
def set_wrapped_leverage_zapper(zapper: address):
    """
    @notice Sets the address of the wrapped leverage zapper contract
    @param zapper Address of the wrapped leverage zapper contract
    """
    ownable._check_owner()
    assert not self.is_wrapped_leverage_zapper_set, "already set"
    self.wrapped_leverage_zapper = zapper
    self.is_wrapped_leverage_zapper_set = True
    log WrappedLeverageZapperSet(zapper=zapper)


@external
def set_exchange(exchange: IExchange, is_collateral: bool):
    """
    @notice Sets the address of the exchange contract
    @param exchange Address of the exchange contract
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    """
    ownable._check_owner()
    self._set_exchange(exchange, is_collateral)


# ============================================================================================
# Lever up
# ============================================================================================


@external
def lever_up_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Leverages up a trove using a flash loan
    @dev The zapper must be the remove manager and receiver of the trove and the caller must be the owner of it
    @param trove_id ID of the trove to leverage up
    @param flash_loan_amount Amount of crvUSD to borrow, will be swapped for collateral
    @param usdaf_amount Amount of USDaf debt to add to the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    self._check_caller_is_owner(trove_id)
    self._check_zapper_is_remove_manager_and_receiver(trove_id)

    before: uint256 = staticcall CRVUSD.balanceOf(self)

    selector: Bytes[SELECTOR_SIZE] = method_id("_on_lever_up_trove()")
    encoded_args: Bytes[ENCODED_LEVER_UP_ARGS_SIZE] = abi_encode(
        trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee
    )
    data: Bytes[LEVER_UP_CALLDATA_SIZE] = concat(selector, encoded_args)
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    self._return_leftovers(before)


def _on_lever_up_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Internal function to handle leveraging up a trove. Called by the flash loan provider
    @dev No need to use a min, the flash loan provider will revert if the amount returned is not enough
    @param trove_id ID of the trove to leverage up
    @param flash_loan_amount Amount of crvUSD to borrow
    @param usdaf_amount Amount of USDaf to add to the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # crvUSD --> collateral
    collateral_amount: uint256 = self._swap(flash_loan_amount, True, True)

    # Increase trove collateral and debt
    extcall BORROWER_OPERATIONS.adjustTrove(trove_id, collateral_amount, True, usdaf_amount, True, max_upfront_fee)

    # USDaf --> crvUSD
    amount_out: uint256 = self._swap(usdaf_amount, False, False)

    # Make sure we can repay the flash loan
    assert staticcall CRVUSD.balanceOf(self) >= flash_loan_amount, "!repay"


# ============================================================================================
# On flashloan
# ============================================================================================


@external
def onFlashLoan(
    initiator: address,
    token: address,
    amount: uint256,
    fee: uint256,
    data: Bytes[10**5],
) -> bytes32:
    """
    @notice ERC-3156 Flash loan callback.
    """
    assert msg.sender == FLASH_LENDER.address, "!caller"
    assert initiator == self, "!initiator"
    assert token == CRVUSD.address, "!token"
    assert len(data) > 4, "!data"
    assert staticcall CRVUSD.balanceOf(self) >= amount, "!amount"
    assert fee == 0, "!fee"

    selector: Bytes[SELECTOR_SIZE] = slice(data, 0, 4)
    if selector == method_id("_on_lever_up_trove()"):
        trove_id: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        usdaf_amount: uint256 = empty(uint256)
        max_upfront_fee: uint256 = empty(uint256)
        (trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_LEVER_UP_ARGS_SIZE), (uint256, uint256, uint256, uint256)
        )
        self._on_lever_up_trove(trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee)
    else:
        raise "!selector"

    extcall CRVUSD.transfer(FLASH_LENDER.address, amount, default_return_value=True)

    return FLASHLOAN_CALLBACK_SUCCESS


# ============================================================================================
# Internal view functions
# ============================================================================================


@view
def _check_caller_is_owner(trove_id: uint256):
    """
    @notice Checks if the caller is the owner of the trove
    @param trove_id ID of the trove
    """
    owner: address = staticcall TROVE_NFT.ownerOf(trove_id)
    assert msg.sender == owner or msg.sender == self.wrapped_leverage_zapper, "caller != owner"


@view
def _check_zapper_is_remove_manager_and_receiver(trove_id: uint256):
    """
    @notice Checks if the zapper has the necessary privileges to act on a trove
    @param trove_id ID of the trove
    """
    manager: address = empty(address)
    receiver: address = empty(address)
    (manager, receiver) = staticcall BORROWER_OPERATIONS.removeManagerReceiverOf(trove_id)
    assert receiver == self, "zapper != receiver"
    assert manager == self, "zapper != manager"


# ============================================================================================
# Internal mutated functions
# ============================================================================================


def _set_exchange(exchange: IExchange, is_collateral: bool, collateral_token: IERC20 = COLLATERAL_TOKEN):
    """
    @notice Sets the address of the exchange contract
    @param exchange Address of the exchange contract
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    @param collateral_token Address of the collateral token
    """
    assert (staticcall exchange.TOKEN() == CRVUSD.address), "!token"

    paired_with: IERC20 = IERC20(staticcall exchange.PAIRED_WITH())
    old_exchange: IExchange = empty(IExchange)
    if is_collateral:
        assert (paired_with.address == collateral_token.address), "!collateral"
        old_exchange = self.collateral_exchange
        self.collateral_exchange = exchange
    else:
        assert (paired_with.address == USDAF.address), "!usdaf"
        old_exchange = self.usdaf_exchange
        self.usdaf_exchange = exchange

    assert (old_exchange == empty(IExchange) or old_exchange != exchange), "!old_exchange"

    if old_exchange != empty(IExchange):
        extcall CRVUSD.approve(old_exchange.address, 0, default_return_value=True)
        extcall paired_with.approve(old_exchange.address, 0, default_return_value=True)

    extcall CRVUSD.approve(exchange.address, max_value(uint256), default_return_value=True)
    extcall paired_with.approve(exchange.address, max_value(uint256), default_return_value=True)

    log ExchangeSet(exchange=exchange.address, is_collateral=is_collateral)


def _swap(amount: uint256, is_collateral: bool, from_crvusd: bool) -> uint256:
    """
    @notice Swaps between crvUSD and USDaf or the collateral token
    @param amount Amount of tokens to swap
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    @param from_crvusd True if swapping from crvUSD, False otherwise
    @return Amount of tokens received
    """
    return (
        extcall self.collateral_exchange.swap(amount, 0, from_crvusd)
        if is_collateral
        else extcall self.usdaf_exchange.swap(amount, 0, from_crvusd)
    )


def _return_leftovers(before: uint256):
    """
    @notice Transfers back any leftover crvUSD as USDaf to the user
    @param before The crvUSD balance before the flash loan
    """
    after: uint256 = staticcall CRVUSD.balanceOf(self)
    if after > before:
        leftovers: uint256 = after - before
        leftovers = self._swap(leftovers, False, True)
        extcall USDAF.transfer(msg.sender, leftovers, default_return_value=True)
