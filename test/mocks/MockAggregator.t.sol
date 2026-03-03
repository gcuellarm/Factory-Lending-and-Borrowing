// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockAggregator {
    int256 public answer;
    bool public shouldRevert;

    function setAnswer(int256 a) external {
        answer = a;
    }

    function setRevert(bool v) external {
        shouldRevert = v;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (shouldRevert) revert("mock revert");
        return (0, answer, 0, 0, 0);
    }
}