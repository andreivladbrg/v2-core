// SPDX-License-Identifier: LGPL-3.0
pragma solidity >=0.8.13;

import { IERC20 } from "@prb/contracts/token/erc20/IERC20.sol";
import { SafeERC20 } from "@prb/contracts/token/erc20/SafeERC20.sol";
import { UD60x18, toUD60x18 } from "@prb/math/UD60x18.sol";

import { ISablierV2 } from "./interfaces/ISablierV2.sol";
import { ISablierV2Cliff } from "./interfaces/ISablierV2Cliff.sol";
import { SablierV2 } from "./SablierV2.sol";

/// @title SablierV2Cliff
/// @author Sablier Labs Ltd.
contract SablierV2Cliff is
    ISablierV2Cliff, // one dependency
    SablierV2 // one dependency
{
    using SafeERC20 for IERC20;

    /// INTERNAL STORAGE ///

    /// @dev Sablier V2 cliff streams mapped by unsigned integers.
    mapping(uint256 => Stream) internal streams;

    /// MODIFIERS ///

    /// @notice Checks that `msg.sender` is the recipient of the stream.
    modifier onlyRecipient(uint256 streamId) {
        if (msg.sender != streams[streamId].recipient) {
            revert SablierV2__Unauthorized(streamId, msg.sender);
        }
        _;
    }

    /// @notice Checks that `msg.sender` is either the sender or the recipient of the stream.
    modifier onlySenderOrRecipient(uint256 streamId) {
        if (msg.sender != streams[streamId].sender && msg.sender != streams[streamId].recipient) {
            revert SablierV2__Unauthorized(streamId, msg.sender);
        }
        _;
    }

    /// @dev Checks that `streamId` points to a stream that exists.
    modifier streamExists(uint256 streamId) {
        if (streams[streamId].sender == address(0)) {
            revert SablierV2__StreamNonExistent(streamId);
        }
        _;
    }

    /// CONSTANT FUNCTIONS ///

    /// @inheritdoc ISablierV2Cliff
    function getCliffTime(uint256 streamId) external view override returns (uint256 cliffTime) {
        cliffTime = streams[streamId].cliffTime;
    }

    /// @inheritdoc ISablierV2
    function getDepositAmount(uint256 streamId) external view override returns (uint256 depositAmount) {
        depositAmount = streams[streamId].depositAmount;
    }

    /// @inheritdoc ISablierV2
    function getRecipient(uint256 streamId) public view override(ISablierV2, SablierV2) returns (address recipient) {
        recipient = streams[streamId].recipient;
    }

    /// @inheritdoc ISablierV2
    function getReturnableAmount(uint256 streamId) public view returns (uint256 returnableAmount) {
        // If the stream does not exist, return zero.
        Stream memory stream = streams[streamId];
        if (stream.sender == address(0)) {
            return 0;
        }

        unchecked {
            uint256 withdrawableAmount = getWithdrawableAmount(streamId);
            returnableAmount = stream.depositAmount - stream.withdrawnAmount - withdrawableAmount;
        }
    }

    /// @inheritdoc ISablierV2
    function getSender(uint256 streamId) public view override(ISablierV2, SablierV2) returns (address sender) {
        sender = streams[streamId].sender;
    }

    /// @inheritdoc ISablierV2
    function getStartTime(uint256 streamId) external view override returns (uint256 startTime) {
        startTime = streams[streamId].startTime;
    }

    /// @inheritdoc ISablierV2
    function getStopTime(uint256 streamId) external view override returns (uint256 stopTime) {
        stopTime = streams[streamId].stopTime;
    }

    /// @inheritdoc ISablierV2Cliff
    function getStream(uint256 streamId) external view override returns (Stream memory stream) {
        stream = streams[streamId];
    }

    /// @inheritdoc ISablierV2
    function getWithdrawableAmount(uint256 streamId) public view returns (uint256 withdrawableAmount) {
        // If the stream does not exist, return zero.
        Stream memory stream = streams[streamId];
        if (stream.sender == address(0)) {
            return 0;
        }

        // If the cliff time is greater than the block timestamp, return zero.
        uint256 currentTime = block.timestamp;
        if (stream.cliffTime > currentTime) {
            return 0;
        }

        unchecked {
            // If the current time is greater than or equal to the stop time, return the deposit minus
            // the withdrawn amount.
            if (currentTime >= stream.stopTime) {
                return stream.depositAmount - stream.withdrawnAmount;
            }

            // In all other cases, calculate how much the recipient can withdraw.
            UD60x18 elapsedTime = toUD60x18(currentTime - stream.startTime);
            UD60x18 totalTime = toUD60x18(stream.stopTime - stream.startTime);
            UD60x18 quotient = elapsedTime.div(totalTime);
            UD60x18 depositAmount = UD60x18.wrap(stream.depositAmount);
            UD60x18 streamedAmount = quotient.mul(depositAmount);
            UD60x18 withdrawnAmount = UD60x18.wrap(stream.withdrawnAmount);
            withdrawableAmount = UD60x18.unwrap(streamedAmount.uncheckedSub(withdrawnAmount));
        }
    }

    /// @inheritdoc ISablierV2
    function getWithdrawnAmount(uint256 streamId) external view override returns (uint256 withdrawnAmount) {
        withdrawnAmount = streams[streamId].withdrawnAmount;
    }

    /// @inheritdoc ISablierV2
    function isCancelable(uint256 streamId) public view override(ISablierV2, SablierV2) returns (bool cancelable) {
        cancelable = streams[streamId].cancelable;
    }

    /// NON-CONSTANT FUNCTIONS ///

    /// @inheritdoc ISablierV2Cliff
    function create(
        address sender,
        address recipient,
        uint256 depositAmount,
        IERC20 token,
        uint256 startTime,
        uint256 cliffTime,
        uint256 stopTime,
        bool cancelable
    ) external returns (uint256 streamId) {
        // Checks, Effects and Interactions: create the stream.
        streamId = createInternal(sender, recipient, depositAmount, token, startTime, cliffTime, stopTime, cancelable);
    }

    /// @inheritdoc ISablierV2Cliff
    function createWithDuration(
        address sender,
        address recipient,
        uint256 depositAmount,
        IERC20 token,
        uint256 cliffDuration,
        uint256 totalDuration,
        bool cancelable
    ) external returns (uint256 streamId) {
        // Calculate the cliff time and the stop time. It is fine to use unchecked arithmetic because the
        // `createInternal` function will nonetheless check that the stop time is greater than or equal to the
        // cliff time, and that the cliff time is greater than or equal to the start time.
        uint256 startTime = block.timestamp;
        uint256 cliffTime;
        uint256 stopTime;
        unchecked {
            cliffTime = startTime + cliffDuration;
            stopTime = startTime + totalDuration;
        }

        // Checks, Effects and Interactions: create the stream.
        streamId = createInternal(sender, recipient, depositAmount, token, startTime, cliffTime, stopTime, cancelable);
    }

    /// @inheritdoc ISablierV2
    function renounce(uint256 streamId) external streamExists(streamId) {
        Stream memory stream = streams[streamId];

        // Checks: the caller is the sender of the stream.
        if (msg.sender != streams[streamId].sender) {
            revert SablierV2__Unauthorized(streamId, msg.sender);
        }

        // Checks: the stream is cancelable.
        if (!stream.cancelable) {
            revert SablierV2__RenounceNonCancelableStream(streamId);
        }

        // Effects: make the stream non-cancelable.
        streams[streamId].cancelable = false;

        // Emit an event.
        emit Renounce(streamId);
    }

    /// @inheritdoc ISablierV2
    function withdraw(uint256 streamId, uint256 amount)
        external
        streamExists(streamId)
        onlySenderOrRecipient(streamId)
    {
        address to = streams[streamId].recipient;
        withdrawInternal(streamId, to, amount);
    }

    /// @inheritdoc ISablierV2
    function withdrawAll(uint256[] calldata streamIds, uint256[] calldata amounts) external {
        // Checks: count of `streamIds` matches count of `amounts`.
        uint256 streamIdsCount = streamIds.length;
        uint256 amountsCount = amounts.length;
        if (streamIdsCount != amountsCount) {
            revert SablierV2__WithdrawAllArraysNotEqual(streamIdsCount, amountsCount);
        }

        // Iterate over the provided array of stream ids and withdraw from each stream.
        address sender;
        uint256 streamId;
        for (uint256 i = 0; i < streamIdsCount; ) {
            streamId = streamIds[i];

            // If the `streamId` points to a stream that does not exist, skip it.
            sender = streams[streamId].sender;
            if (sender != address(0)) {
                // Checks: the `msg.sender` is either the sender or the recipient of the stream.
                if (msg.sender != sender && msg.sender != streams[streamId].recipient) {
                    revert SablierV2__Unauthorized(streamId, msg.sender);
                }

                // Checks, Effects and Interactions: make the withdrawal.
                withdrawInternal(streamId, streams[streamId].recipient, amounts[i]);
            }

            // Increment the for loop iterator.
            unchecked {
                i += 1;
            }
        }
    }

    /// @inheritdoc ISablierV2
    function withdrawTo(
        uint256 streamId,
        address to,
        uint256 amount
    ) external streamExists(streamId) onlyRecipient(streamId) {
        // Checks: the provided address to withdraw to is not zero.
        if (to == address(0)) {
            revert SablierV2__WithdrawZeroAddress();
        }

        // Checks, Effects and Interactions: make the withdrawal.
        withdrawInternal(streamId, to, amount);
    }

    /// @inheritdoc ISablierV2
    function withdrawAllTo(
        uint256[] calldata streamIds,
        address to,
        uint256[] calldata amounts
    ) external {
        // Checks: the provided address to withdraw to is not zero.
        if (to == address(0)) {
            revert SablierV2__WithdrawZeroAddress();
        }

        // Checks: count of `streamIds` matches `amounts`.
        uint256 streamIdsCount = streamIds.length;
        uint256 amountsCount = amounts.length;
        if (streamIdsCount != amountsCount) {
            revert SablierV2__WithdrawAllArraysNotEqual(streamIdsCount, amountsCount);
        }

        // Iterate over the provided array of stream ids and withdraw from each stream.
        uint256 streamId;
        for (uint256 i = 0; i < streamIdsCount; ) {
            streamId = streamIds[i];

            // If the `streamId` points to a stream that does not exist, skip it.
            if (streams[streamId].sender != address(0)) {
                // Checks: the `msg.sender` is the recipient of the stream.
                if (msg.sender != streams[streamId].recipient) {
                    revert SablierV2__Unauthorized(streamId, msg.sender);
                }

                // Checks, Effects and Interactions: make the withdrawal.
                withdrawInternal(streamId, to, amounts[i]);
            }

            // Increment the for loop iterator.
            unchecked {
                i += 1;
            }
        }
    }

    /// INTERNAL NON-CONSTANT FUNCTIONS ///

    /// @dev See the documentation for the public functions that call this internal function.
    function cancelInternal(uint256 streamId) internal override onlySenderOrRecipient(streamId) {
        Stream memory stream = streams[streamId];

        // Calculate the withdraw and the return amounts.
        uint256 withdrawAmount = getWithdrawableAmount(streamId);
        uint256 returnAmount;
        unchecked {
            returnAmount = stream.depositAmount - stream.withdrawnAmount - withdrawAmount;
        }

        // Effects: delete the stream from storage.
        delete streams[streamId];

        // Interactions: withdraw the tokens to the recipient, if any.
        if (withdrawAmount > 0) {
            stream.token.safeTransfer(stream.recipient, withdrawAmount);
        }

        // Interactions: return the tokens to the sender, if any.
        if (returnAmount > 0) {
            stream.token.safeTransfer(stream.sender, returnAmount);
        }

        // Emit an event.
        emit Cancel(streamId, stream.recipient, withdrawAmount, returnAmount);
    }

    /// @dev See the documentation for the public functions that call this internal function.
    function createInternal(
        address sender,
        address recipient,
        uint256 depositAmount,
        IERC20 token,
        uint256 startTime,
        uint256 cliffTime,
        uint256 stopTime,
        bool cancelable
    ) internal returns (uint256 streamId) {
        // Checks: the common requirements for the `create` function arguments.
        checkCreateArguments(sender, recipient, depositAmount, startTime, stopTime);

        // Checks: the cliff time is greater than or equal to the start time.
        if (startTime > cliffTime) {
            revert SablierV2Cliff__StartTimeGreaterThanCliffTime(startTime, cliffTime);
        }

        // Checks: the stop time is greater than or equal to the cliff time.
        if (cliffTime > stopTime) {
            revert SablierV2Cliff__CliffTimeGreaterThanStopTime(cliffTime, stopTime);
        }

        // Effects: create and store the stream.
        streamId = nextStreamId;
        streams[streamId] = Stream({
            cancelable: cancelable,
            cliffTime: cliffTime,
            depositAmount: depositAmount,
            recipient: recipient,
            sender: sender,
            startTime: startTime,
            stopTime: stopTime,
            token: token,
            withdrawnAmount: 0
        });

        // Effects: bump the next stream id.
        // We're using unchecked arithmetic here because this cannot realistically overflow, ever.
        unchecked {
            nextStreamId = streamId + 1;
        }

        // Interactions: perform the ERC-20 transfer.
        token.safeTransferFrom(msg.sender, address(this), depositAmount);

        // Emit an event.
        emit CreateStream(
            streamId,
            msg.sender,
            sender,
            recipient,
            depositAmount,
            token,
            startTime,
            cliffTime,
            stopTime,
            cancelable
        );
    }

    /// @dev See the documentation for the public functions that call this internal function.
    function withdrawInternal(
        uint256 streamId,
        address to,
        uint256 amount
    ) internal {
        // Checks: the amount must not be zero.
        if (amount == 0) {
            revert SablierV2__WithdrawAmountZero(streamId);
        }

        // Checks: the amount must not be greater than what can be withdrawn.
        uint256 withdrawableAmount = getWithdrawableAmount(streamId);
        if (amount > withdrawableAmount) {
            revert SablierV2__WithdrawAmountGreaterThanWithdrawableAmount(streamId, amount, withdrawableAmount);
        }

        // Effects: update the withdrawn amount.
        unchecked {
            streams[streamId].withdrawnAmount += amount;
        }

        // Load the stream in memory, we will need it below.
        Stream memory stream = streams[streamId];

        // Effects: if this stream is done, save gas by deleting it from storage.
        if (stream.depositAmount == stream.withdrawnAmount) {
            delete streams[streamId];
        }

        // Interactions: perform the ERC-20 transfer.
        stream.token.safeTransfer(to, amount);

        // Emit an event.
        emit Withdraw(streamId, to, amount);
    }
}
