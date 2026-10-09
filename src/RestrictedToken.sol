// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RestrictedToken is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public admin;
    address public factoryContract;

    modifier ownerOrFactory() {
        require(
            msg.sender == owner() || msg.sender == factoryContract,
            "This function can only be called by owner or the factory contract."
        );
        _;
    }

    constructor(address initialOwner) ERC20("Restricted Token", "RST") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Override transfer function
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (!admin[msg.sender]) {
            require(admin[recipient], "Transfers only allowed to admin");
        }
        return super.transfer(recipient, amount);
    }

    // Override transferFrom function
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (!admin[sender]) {
            require(admin[recipient], "Transfers only allowed to admin");
        }

        return super.transferFrom(sender, recipient, amount);
    }

    function setAdmin(address _user) external ownerOrFactory {
        admin[_user] = true;
    }

    function revokeAdmin(address[] memory _users) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            admin[_users[i]] = false;
        }
    }

    function setFactoryContract(address factory) external onlyOwner {
        factoryContract = factory;
    }
}
