// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title REPUTATION (REP)
/// @notice A fixed supply ERC-20. The deploying address receives every token.
contract ReputationToken is ERC20 {
    /// @notice One billion REP expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("REPUTATION", "REP") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
