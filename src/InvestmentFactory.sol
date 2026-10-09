// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IInvestmentFactory} from "./IInvestmentFactory.sol";
import {IInvestment} from "./IInvestment.sol";
import {Investment} from "./Investment.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRestrictedToken {
    function setAdmin(address _user) external;
}

/// @title InvestmentFactory
/// @notice Factory contract for Investment contracts.
contract InvestmentFactory is IInvestmentFactory, Ownable {
    address public restrictedToken;

    constructor(address _initialOwner, address _restrictedToken) Ownable(_initialOwner) {
        restrictedToken = _restrictedToken;
    }
    /// @inheritdoc IInvestmentFactory

    function newInvestment(
        string memory _name,
        uint256 _totalInvestment,
        uint256 _minTotalInvestment,
        uint256 _deadline,
        address _receiver,
        address _initialOwner,
        address _investmentHelper,
        address _restrictedToken
    ) external onlyOwner returns (IInvestment) {
        bytes32 salt = bytes32(uint256(keccak256(abi.encodePacked(_name))));
        address computedAddress = computeEscrowAddress(
            type(Investment).creationCode,
            address(this),
            uint256(salt),
            _name,
            _totalInvestment,
            _minTotalInvestment,
            _deadline,
            _receiver,
            _initialOwner,
            _investmentHelper,
            _restrictedToken
        );

        Investment investment = new Investment{salt: salt}(
            _name,
            _totalInvestment,
            _minTotalInvestment,
            _deadline,
            _receiver,
            _initialOwner,
            _investmentHelper,
            _restrictedToken
        );
        if (address(investment) != computedAddress) {
            revert InvestmentFactory__AddressesDiffer();
        }

        IRestrictedToken(restrictedToken).setAdmin(_receiver);
        IRestrictedToken(restrictedToken).setAdmin(_investmentHelper);
        IRestrictedToken(restrictedToken).setAdmin(address(investment));
        emit InvestmentCreated(_name, address(investment), _totalInvestment, _minTotalInvestment, _deadline, _receiver);
        return investment;
    }

    /// @dev See https://docs.soliditylang.org/en/latest/control-structures.html#salted-contract-creations-create2
    function computeEscrowAddress(
        bytes memory byteCode,
        address deployer,
        uint256 salt,
        string memory _name,
        uint256 _totalInvestment,
        uint256 _minTotalInvestment,
        uint256 _deadline,
        address _receiver,
        address _initialOwner,
        address _investmentHelper,
        address _restrictedToken
    ) public pure returns (address) {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    byteCode,
                                    abi.encode(
                                        _name,
                                        _totalInvestment,
                                        _minTotalInvestment,
                                        _deadline,
                                        _receiver,
                                        _initialOwner,
                                        _investmentHelper,
                                        _restrictedToken
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
        return predictedAddress;
    }
}
