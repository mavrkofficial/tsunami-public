// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SentryTokenStandard
 * @dev Bare-bones ERC20 token deployed by the Sentry Launch Factory.
 * 1 billion fixed supply, auto-renounced ownership, ERC2771 meta-transaction support.
 */

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract ERC2771Context is Context {
    address private immutable _trustedForwarder;

    constructor(address trustedForwarder_) {
        _trustedForwarder = trustedForwarder_;
    }

    function trustedForwarder() public view virtual returns (address) {
        return _trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return forwarder == trustedForwarder();
    }

    function _msgSender() internal view virtual override returns (address) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return msg.data[:calldataLength - contextSuffixLength];
            }
        } else {
            return super._msgData();
        }
    }

    function _contextSuffixLength() internal view virtual override returns (uint256) {
        return 20;
    }
}

interface ISentryVerificationRegistry {
    function canTransfer(address operator, address from, address to) external view returns (bool);
}

contract SentryTokenStandard is ERC2771Context {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public owner;
    address public verificationRegistry;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        address _deployer,
        address trustedForwarder_,
        address _verificationRegistry
    ) ERC2771Context(trustedForwarder_) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = 1_000_000_000 * (10 ** uint256(decimals));
        owner = address(0x000000000000000000000000000000000000dEaD);
        verificationRegistry = _verificationRegistry;
        balanceOf[_deployer] = totalSupply;
        emit Transfer(address(0), _deployer, totalSupply);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(_msgSender(), to, amount, _msgSender());
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][_msgSender()] >= amount, "Insufficient allowance");
        allowance[from][_msgSender()] -= amount;
        _transfer(from, to, amount, _msgSender());
        return true;
    }

    function _transfer(address from, address to, uint256 amount, address operator) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (verificationRegistry != address(0)) {
            require(
                ISentryVerificationRegistry(verificationRegistry).canTransfer(operator, from, to),
                "Transfer not allowed"
            );
        }

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _msgSender() internal view override returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}