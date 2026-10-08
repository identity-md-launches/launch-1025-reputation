// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title REPUTATION (REP)
/// @notice A one-time-minted ERC-20 with an owner-controlled transfer burn and pause.
contract ReputationToken is ERC20 {
    /// @notice One billion REP expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Burn rate in basis points; initially 0.5%, owner-settable from 0% to 100%.
    uint256 public feeBps = 50;
    address public owner;
    address public pendingOwner;
    bool public paused;

    error UnauthorizedOwner(address caller);
    error InvalidOwner(address proposedOwner);
    error UnauthorizedPendingOwner(address caller);
    error InvalidFee(uint256 proposedFeeBps);
    error EnforcedPause();
    error ExpectedPause();

    event FeeUpdated(uint256 previousFeeBps, uint256 newFeeBps);
    event Paused(address account);
    event Unpaused(address account);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() ERC20("REPUTATION", "REP") {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    modifier onlyOwner() {
        if (_msgSender() != owner) revert UnauthorizedOwner(_msgSender());
        _;
    }

    /// @notice Changes the burn rate for subsequent transfers, including while paused.
    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > BPS_DENOMINATOR) revert InvalidFee(newFeeBps);
        uint256 previousFeeBps = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(previousFeeBps, newFeeBps);
    }

    /// @notice Stops all transfers. Approvals and owner operations remain available.
    function pause() external onlyOwner {
        if (paused) revert EnforcedPause();
        paused = true;
        emit Paused(_msgSender());
    }

    function unpause() external onlyOwner {
        if (!paused) revert ExpectedPause();
        paused = false;
        emit Unpaused(_msgSender());
    }

    /// @notice Nominates a new owner, replacing any pending nomination; acceptance is required.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0) || newOwner == address(this)) revert InvalidOwner(newOwner);
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        address sender = _msgSender();
        if (sender == address(0) || sender != pendingOwner) revert UnauthorizedPendingOwner(sender);
        address previousOwner = owner;
        owner = sender;
        delete pendingOwner;
        emit OwnershipTransferred(previousOwner, sender);
    }

    /// @dev Both transfer entry points reach this hook. Minting is untaxed; no public mint/burn exists.
    function _update(address from, address to, uint256 value) internal override {
        if (paused) revert EnforcedPause();
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Require the gross amount even for self-transfers. This also bounds multiplication:
        // value <= balance <= INITIAL_SUPPLY (10^27), and feeBps <= 10^4.
        uint256 fromBalance = balanceOf(from);
        if (value > fromBalance) revert ERC20InsufficientBalance(from, fromBalance, value);
        uint256 burnAmount = value * feeBps / BPS_DENOMINATOR;
        if (burnAmount != 0) super._update(from, address(0), burnAmount);
        super._update(from, to, value - burnAmount);
    }
}
