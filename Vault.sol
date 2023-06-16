// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libs/TransferHelper.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IStrategy {
    function want() external view returns (IERC20);

    function beforeDeposit() external;

    function deposit(address, uint256) external;

    function depositETH(address) external payable;

    function withdraw(address, uint256) external;

    function withdrawETH(address, uint256) external payable;

    function balanceOf() external view returns (uint256);
}

contract Vault is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount;     // how many underlying tokens the user has provided. usdt, usdc...
    }

    IStrategy public strategy;

    IERC20 public assets;

    uint256 public totalAssets;

    address public mainChef;

    address public WETH;

    mapping(address => UserInfo) public userInfoMap;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function initialize(
        IERC20 _assets,
        address _weth,
        address _mainChef
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        assets = _assets;
        WETH = _weth;
        mainChef = _mainChef;
    }

    function setStrategy(IStrategy _strategy) external onlyOwner {
        strategy = _strategy;
    }

    function setMainChef(address _mainChef) external onlyOwner {
        mainChef = _mainChef;
    }

    function available() public view returns (uint256) {
        return assets.balanceOf(address(this));
    }

    function balance() public view returns (uint256) {
        if (address(assets) == WETH) {
            return address(this).balance;
        } else {
            if (address(strategy) != address(0)) {
                return assets.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
            } else {
                return assets.balanceOf(address(this));
            }
        }
    }

    function deposit(address _userAddr, uint _amount) public payable nonReentrant returns (uint256) {
        require(msg.sender == mainChef, "!mainChef");
        require(_userAddr != address(0), "user address cannot be zero address");

        if (address(strategy) != address(0)) {
            strategy.beforeDeposit();
        }

        uint256 _depositAmount;
        if (address(assets) == WETH) {
            _depositAmount = _depositETH(_userAddr, msg.value);
        } else {
            _depositAmount = _deposit(_userAddr, mainChef, _amount);
        }

        return _depositAmount;
    }

    function _depositETH(address _userAddr, uint _amount) private returns (uint256){
        UserInfo storage _userInfo = userInfoMap[_userAddr];

        _userInfo.amount = _userInfo.amount.add(_amount);
        totalAssets = totalAssets.add(_amount);

        if (address(strategy) != address(0)) {
            IStrategy(strategy).depositETH{value: _amount}(_userAddr);
        }

        return _amount;
    }

    function _deposit(address _userAddr, address _mainChef, uint _amount) private returns (uint256){
        UserInfo storage _userInfo = userInfoMap[_userAddr];

        uint256 _poolBalance = balance();
        TransferHelper.safeTransferFrom(address(assets), _mainChef, address(this), _amount);

        uint256 _afterPoolBalance = balance();
        uint256 _depositAmount = _afterPoolBalance.sub(_poolBalance);

        _userInfo.amount = _userInfo.amount.add(_depositAmount);
        totalAssets = totalAssets.add(_depositAmount);

        if (address(strategy) != address(0)) {
            IStrategy(strategy).deposit(_mainChef, _amount);
        }

        return _depositAmount;
    }

    function withdraw(address _userAddr, uint _amount) public nonReentrant returns (uint256) {
        require(msg.sender == mainChef, "!mainChef");
        require(_userAddr != address(0), "user address cannot be zero address");

        UserInfo storage _userInfo = userInfoMap[_userAddr];

        if (address(assets) == WETH) {
            TransferHelper.safeTransferETH(_userAddr, _amount);
            _userInfo.amount = _userInfo.amount.sub(_amount);
            totalAssets = totalAssets.sub(_amount);

            if (address(strategy) != address(0)) {
                IStrategy(strategy).withdrawETH(_userAddr, _amount);
            }

            return _amount;
        } else {
            TransferHelper.safeTransfer(address(assets), _userAddr, _amount);
            _userInfo.amount = _userInfo.amount.sub(_amount);
            totalAssets = totalAssets.sub(_amount);

            if (address(strategy) != address(0)) {
                IStrategy(strategy).withdraw(_userAddr, _amount);
            }

            return _amount;
        }
    }

    receive() external payable {}
}

