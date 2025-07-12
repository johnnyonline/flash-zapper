# @version 0.4.1

"""
@title USDaf Flash Zapper
@license MIT
@author asymmetry.finance
@notice Leverages up and down USDaf positions using a flash loan
"""
# @todo -- make sure retrun_leftovers actually makes sense
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
# Constants
# ============================================================================================


# ERC3156
FLASHLOAN_CALLBACK_SUCCESS: constant(bytes32) = keccak256("ERC3156FlashBorrower.onFlashLoan")
MAX_FLASHLOAN_CALLBACK_DATA_SIZE: constant(uint256) = 10**5

# Selector
SELECTOR_SIZE: constant(uint256) = 4

# Open trove
ENCODED_OPEN_TROVE_ARGS_SIZE: constant(uint256) = 288
OPEN_TROVE_CALLDATA_SIZE: constant(uint256) = ENCODED_OPEN_TROVE_ARGS_SIZE + SELECTOR_SIZE

# Lever up
ENCODED_LEVER_UP_ARGS_SIZE: constant(uint256) = 128
LEVER_UP_CALLDATA_SIZE: constant(uint256) = ENCODED_LEVER_UP_ARGS_SIZE + SELECTOR_SIZE

# Lever down
ENCODED_LEVER_DOWN_ARGS_SIZE: constant(uint256) = 128
LEVER_DOWN_CALLDATA_SIZE: constant(uint256) = ENCODED_LEVER_DOWN_ARGS_SIZE + SELECTOR_SIZE

# WETH gas compensation needed for opening a trove
ETH_GAS_COMPENSATION: constant(uint256) = as_wei_value(0.0375, "ether")

# Token addresses
USDAF: public(constant(IERC20)) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
CRVUSD: public(constant(IERC20)) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
WETH: public(constant(IERC20)) = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)

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
    self._set_exchange(IExchange(collateral_exchange), True)

    extcall WETH.approve(BORROWER_OPERATIONS.address, max_value(uint256), default_return_value=True)
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


# ============================================================================================
# Open leveraged
# ============================================================================================


@external
def open_leveraged_trove(
    owner: address,
    owner_index: uint256,
    initial_collateral_amount: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    upper_hint: uint256,
    lower_hint: uint256,
    annual_interest_rate: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Opens a leveraged trove using a flash loan
    @dev Adds this contract as add/receive manager to be able to fully adjust trove
    @param owner Address of the trove owner
    @param owner_index Index of the trove owner in the trove index
    @param initial_collateral_amount Amount of collateral to pull from the user, will be added to the trove
    @param flash_loan_amount Amount of crvUSD to flash loan, will be swapped for collateral
    @param usdaf_amount Amount of USDaf to mint
    @param upper_hint Upper hint for the trove
    @param lower_hint Lower hint for the trove
    @param annual_interest_rate Annual interest rate for the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    extcall COLLATERAL_TOKEN.transferFrom(msg.sender, self, initial_collateral_amount, default_return_value=True)
    extcall WETH.transferFrom(msg.sender, self, ETH_GAS_COMPENSATION, default_return_value=True)

    before: uint256 = staticcall CRVUSD.balanceOf(self)

    selector: Bytes[SELECTOR_SIZE] = method_id("_on_open_leveraged_trove()")
    encoded_args: Bytes[ENCODED_OPEN_TROVE_ARGS_SIZE] = abi_encode(
        owner,
        owner_index,
        initial_collateral_amount,
        flash_loan_amount,
        usdaf_amount,
        upper_hint,
        lower_hint,
        annual_interest_rate,
        max_upfront_fee,
    )
    data: Bytes[OPEN_TROVE_CALLDATA_SIZE] = concat(selector, encoded_args)
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    self._return_leftovers(before)


def _on_open_leveraged_trove(
    owner: address,
    owner_index: uint256,
    initial_collateral_amount: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    upper_hint: uint256,
    lower_hint: uint256,
    annual_interest_rate: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Internal function to handle opening a leveraged trove. Called by the flash loan provider
    @param owner Address of the trove owner
    @param owner_index Index of the trove owner in the trove index
    @param initial_collateral_amount Amount of collateral that was pulled from the user
    @param flash_loan_amount Amount of crvUSD to flash loan, will be swapped for collateral
    @param usdaf_amount Amount of USDaf to mint
    @param upper_hint Upper hint for the trove
    @param lower_hint Lower hint for the trove
    @param annual_interest_rate Annual interest rate for the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # crvUSD --> collateral
    collateral_amount: uint256 = self._swap(flash_loan_amount, True, True) + initial_collateral_amount

    before: uint256 = staticcall USDAF.balanceOf(self)

    # Open trove with collateral and Bold debt
    extcall BORROWER_OPERATIONS.openTrove(
        owner,
        owner_index,
        collateral_amount,
        usdaf_amount,
        upper_hint,
        lower_hint,
        annual_interest_rate,
        max_upfront_fee,
        self,  # addManager
        self,  # removeManager
        self  # receiver
    )

    # USDaf --> crvUSD
    self._swap(staticcall USDAF.balanceOf(self) - before, False, False)


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
    @dev Returns leftovers as USDaf to the caller
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
    self._swap(usdaf_amount, False, False)


# ============================================================================================
# Lever down
# ============================================================================================


@external
def lever_down_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    min_usdaf_amount: uint256,
    collateral_amount: uint256,
):
    """
    @notice Leverages down a trove using a flash loan
    @dev The zapper must be the remove manager and receiver of the trove and the caller must be the owner of it
    @param trove_id ID of the trove to leverage down
    @param flash_loan_amount Amount of crvUSD to borrow, will be swapped for USDaf
    @param min_usdaf_amount Minimum amount of USDaf to receive from the swap
    @param collateral_amount Amount of collateral to remove from the trove
    """
    self._check_caller_is_owner(trove_id)
    self._check_zapper_is_remove_manager_and_receiver(trove_id)

    before: uint256 = staticcall CRVUSD.balanceOf(self)

    selector: Bytes[SELECTOR_SIZE] = method_id("_on_lever_down_trove()")
    encoded_args: Bytes[ENCODED_LEVER_DOWN_ARGS_SIZE] = abi_encode(
        trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount
    )
    data: Bytes[LEVER_UP_CALLDATA_SIZE] = concat(selector, encoded_args)
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    self._return_leftovers(before)


def _on_lever_down_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    min_usdaf_amount: uint256,
    collateral_amount: uint256,
):
    """
    @notice Internal function to handle leveraging down a trove. Called by the flash loan provider
    @param trove_id ID of the trove to leverage down
    @param flash_loan_amount Amount of crvUSD to borrow
    @param min_usdaf_amount Minimum amount of USDaf to receive from the swap
    @param collateral_amount Amount of collateral to remove from the trove
    """
    # Cache balances before
    collateral_before: uint256 = staticcall COLLATERAL_TOKEN.balanceOf(self)
    usdaf_before: uint256 = staticcall USDAF.balanceOf(self)

    # crvUSD --> USDaf
    usdaf_amount: uint256 = self._swap(flash_loan_amount, False, True)
    assert usdaf_amount >= min_usdaf_amount, "slippage rekt you"

    # Decrease trove collateral and debt
    extcall BORROWER_OPERATIONS.adjustTrove(trove_id, collateral_amount, False, usdaf_amount, False, 0)

    # Collateral --> crvUSD
    self._swap(staticcall COLLATERAL_TOKEN.balanceOf(self) - collateral_before, True, False)

    # Send leftover USDaf back to the user
    leftovers: uint256 = staticcall USDAF.balanceOf(self) - usdaf_before
    if leftovers > 0:
        extcall USDAF.transfer(msg.sender, leftovers, default_return_value=True)


# ============================================================================================
# On flashloan
# ============================================================================================


@external
def onFlashLoan(
    initiator: address,
    token: address,
    amount: uint256,
    fee: uint256,
    data: Bytes[MAX_FLASHLOAN_CALLBACK_DATA_SIZE],
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

    selector: Bytes[SELECTOR_SIZE] = slice(data, 0, SELECTOR_SIZE)
    if selector == method_id("_on_lever_up_trove()"):
        trove_id: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        usdaf_amount: uint256 = empty(uint256)
        max_upfront_fee: uint256 = empty(uint256)
        (trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_LEVER_UP_ARGS_SIZE), (uint256, uint256, uint256, uint256)
        )
        self._on_lever_up_trove(trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee)
    elif selector == method_id("_on_lever_down_trove()"):
        trove_id: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        min_usdaf_amount: uint256 = empty(uint256)
        collateral_amount: uint256 = empty(uint256)
        (trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_LEVER_DOWN_ARGS_SIZE), (uint256, uint256, uint256, uint256)
        )
        self._on_lever_down_trove(trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount)
    elif selector == method_id("_on_open_leveraged_trove()"):
        owner: address = empty(address)
        owner_index: uint256 = empty(uint256)
        initial_collateral_amount: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        usdaf_amount: uint256 = empty(uint256)
        upper_hint: uint256 = empty(uint256)
        lower_hint: uint256 = empty(uint256)
        annual_interest_rate: uint256 = empty(uint256)
        max_upfront_fee: uint256 = empty(uint256)

        (
            owner,
            owner_index,
            initial_collateral_amount,
            flash_loan_amount,
            usdaf_amount,
            upper_hint,
            lower_hint,
            annual_interest_rate,
            max_upfront_fee
        ) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_OPEN_TROVE_ARGS_SIZE),
            (address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
        )

        self._on_open_leveraged_trove(
            owner,
            owner_index,
            initial_collateral_amount,
            flash_loan_amount,
            usdaf_amount,
            upper_hint,
            lower_hint,
            annual_interest_rate,
            max_upfront_fee
        )
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
    assert manager == self, "zapper != manager"
    assert receiver == self, "zapper != receiver"


# ============================================================================================
# Internal mutated functions
# ============================================================================================


def _set_exchange(exchange: IExchange, is_collateral: bool):
    """
    @notice Sets the address of the exchange contract
    @param exchange Address of the exchange contract
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    """
    assert (staticcall exchange.TOKEN() == CRVUSD.address), "!token"

    paired_with: IERC20 = IERC20(staticcall exchange.PAIRED_WITH())
    if is_collateral:
        assert (paired_with.address == COLLATERAL_TOKEN.address), "!collateral"
        self.collateral_exchange = exchange
    else:
        assert (paired_with.address == USDAF.address), "!usdaf"
        self.usdaf_exchange = exchange

    extcall CRVUSD.approve(exchange.address, max_value(uint256), default_return_value=True)
    extcall paired_with.approve(exchange.address, max_value(uint256), default_return_value=True)


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
