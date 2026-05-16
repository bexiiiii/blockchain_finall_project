// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private immutable _DECIMALS;
    string public override description;
    uint256 public override version = 1;

    uint80 public roundId = 1;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;

    constructor(uint8 decimals_, int256 answer_) {
        _DECIMALS = decimals_;
        description = "mock feed";
        updateAnswer(answer_);
    }

    function decimals() external view override returns (uint8) {
        return _DECIMALS;
    }

    function updateAnswer(int256 answer_) public {
        answer = answer_;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        roundId++;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function getRoundData(uint80)
        external
        view
        returns (
            uint80 roundId_,
            int256 answer_,
            uint256 startedAt_,
            uint256 updatedAt_,
            uint80 answeredInRound
        )
    {
        return (roundId, answer, startedAt, updatedAt, roundId);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId_,
            int256 answer_,
            uint256 startedAt_,
            uint256 updatedAt_,
            uint80 answeredInRound
        )
    {
        return (roundId, answer, startedAt, updatedAt, roundId);
    }
}
