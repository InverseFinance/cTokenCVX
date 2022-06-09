pragma solidity >=0.5.16;

interface IOracle {
    function setFeed(
        address cToken_,
        address feed_,
        uint8 tokenDecimals_
    ) external;

    function getUnderlyingPrice(address cToken_)
        external
        view
        returns (uint256);
}
