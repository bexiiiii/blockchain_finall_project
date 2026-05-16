// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";

contract OracleAdapter is AccessControl {
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    AggregatorV3Interface public priceFeed;
    AggregatorV3Interface public reserveFeed;
    uint256 public maxStaleness;

    event FeedsUpdated(address indexed priceFeed, address indexed reserveFeed);
    event MaxStalenessUpdated(uint256 oldMaxStaleness, uint256 newMaxStaleness);

    error StaleOracle(address feed, uint256 updatedAt, uint256 maxStaleness);
    error InvalidOracleAnswer(address feed, int256 answer);

    constructor(
        AggregatorV3Interface priceFeed_,
        AggregatorV3Interface reserveFeed_,
        uint256 maxStaleness_,
        address admin
    ) {
        require(
            address(priceFeed_) != address(0) && address(reserveFeed_) != address(0), "feed zero"
        );
        require(maxStaleness_ > 0, "staleness zero");
        require(admin != address(0), "admin zero");
        priceFeed = priceFeed_;
        reserveFeed = reserveFeed_;
        maxStaleness = maxStaleness_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);
    }

    function latestPrice() external view returns (uint256 answer, uint256 updatedAt) {
        return _read(priceFeed);
    }

    function latestReserve() external view returns (uint256 answer, uint256 updatedAt) {
        return _read(reserveFeed);
    }

    function setFeeds(AggregatorV3Interface priceFeed_, AggregatorV3Interface reserveFeed_)
        external
        onlyRole(ORACLE_ADMIN_ROLE)
    {
        require(
            address(priceFeed_) != address(0) && address(reserveFeed_) != address(0), "feed zero"
        );
        priceFeed = priceFeed_;
        reserveFeed = reserveFeed_;
        emit FeedsUpdated(address(priceFeed_), address(reserveFeed_));
    }

    function setMaxStaleness(uint256 newMaxStaleness) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(newMaxStaleness > 0, "staleness zero");
        emit MaxStalenessUpdated(maxStaleness, newMaxStaleness);
        maxStaleness = newMaxStaleness;
    }

    function _read(AggregatorV3Interface feed)
        internal
        view
        returns (uint256 answer, uint256 updatedAt)
    {
        (, int256 rawAnswer,, uint256 rawUpdatedAt,) = feed.latestRoundData();
        if (rawAnswer <= 0) revert InvalidOracleAnswer(address(feed), rawAnswer);
        if (rawUpdatedAt == 0 || block.timestamp - rawUpdatedAt > maxStaleness) {
            revert StaleOracle(address(feed), rawUpdatedAt, maxStaleness);
        }
        return (uint256(rawAnswer), rawUpdatedAt);
    }
}
