pragma solidity 0.5.11;


contract Echo {
    address masterCopy;

    function helloWorld() external pure returns (string memory) {
        return "hello world";
    }

    function helloWorldArg(string calldata arg)
        external
        pure
        returns (string memory)
    {
        return arg;
    }

    function msgSender() external view returns (address) {
        return msg.sender;
    }

    function returnArg(bool arg) external pure returns (bool) {
        return arg;
    }
}
