// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Minimal } from "../src/MinimalERC20.sol";

/// @notice Test-only token with configurable failure, fee, and callback behavior.
contract AdversarialERC20 is IERC20Minimal {
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    bool public returnFalseOnTransfer;
    bool public returnFalseOnTransferFrom;
    bool public revertOnTransfer;
    bool public revertOnTransferFrom;
    bool public malformedReturnOnTransfer;
    bool public malformedReturnOnTransferFrom;
    uint16 public feeBps;

    address public callbackTarget;
    bytes public callbackData;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    error InsufficientBalance();
    error InsufficientAllowance();
    error ForcedTokenRevert();

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function configureReturns(bool falseTransfer, bool falseTransferFrom) external {
        returnFalseOnTransfer = falseTransfer;
        returnFalseOnTransferFrom = falseTransferFrom;
    }

    function configureReverts(bool revertTransfer_, bool revertTransferFrom_) external {
        revertOnTransfer = revertTransfer_;
        revertOnTransferFrom = revertTransferFrom_;
    }

    function configureMalformedReturns(bool malformedTransfer, bool malformedTransferFrom)
        external
    {
        malformedReturnOnTransfer = malformedTransfer;
        malformedReturnOnTransferFrom = malformedTransferFrom;
    }

    function configureFee(uint16 feeBps_) external {
        require(feeBps_ <= 10_000, "fee too high");
        feeBps = feeBps_;
    }

    function configureCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
        callbackAttempted = false;
        callbackSucceeded = false;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (revertOnTransfer) revert ForcedTokenRevert();
        if (returnFalseOnTransfer) return false;

        _transfer(msg.sender, to, amount);
        _executeCallback();

        if (malformedReturnOnTransfer) {
            assembly {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        if (revertOnTransferFrom) revert ForcedTokenRevert();
        if (returnFalseOnTransferFrom) return false;

        uint256 permitted = allowance[from][msg.sender];
        if (permitted < amount) revert InsufficientAllowance();
        if (permitted != type(uint256).max) allowance[from][msg.sender] = permitted - amount;

        _transfer(from, to, amount);
        _executeCallback();

        if (malformedReturnOnTransferFrom) {
            assembly {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return true;
    }

    function _executeCallback() internal {
        if (callbackTarget != address(0)) {
            callbackAttempted = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 fee = (amount * feeBps) / 10_000;
        uint256 received = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += received;
        totalSupply -= fee;
    }
}
