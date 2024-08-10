// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

library TransferHelper {
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20(token).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED'); 
    }
}



contract BarterAggregatorV1 {
    address private _owner;
    bool private _disabled;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SwapSuccessful(address indexed user, uint amountOut, uint timestamp);
    event Disabled();

     struct TokenAmount {
        address token;
        uint256 amount;
    }

    // Define a struct for whitelisted routers
struct RouterInfo {
    bool isWhitelisted;
    uint8 routerType;
}

// Mapping to store whitelisted routers
mapping(address => RouterInfo) public whitelistedRouters;


// Enum to represent different router types
enum RouterType {
    UniswapV2,
    UniswapV3
}


    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view virtual {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    modifier ensure(uint deadline) {
        if (block.timestamp > deadline) {
            revert("Expired");
        }
        _;
    }

    modifier whenNotDisabled() {
        require(!_disabled, "Contract is disabled");
        _;
    }

    // Function to add or update whitelisted routers (should be called by owner)
function updateWhitelistedRouter(address router, bool isWhitelisted, uint8 routerType) external onlyOwner {
    whitelistedRouters[router] = RouterInfo(isWhitelisted, routerType);
}

 function swap(
    address router,
    bytes calldata callData
) external payable whenNotDisabled ensure(block.timestamp + 300) returns (uint256 amountOut) {
    require(whitelistedRouters[router].isWhitelisted, "Router not whitelisted");

    // Delegate the call to the specified router
    (bool success, bytes memory result) = router.delegatecall(callData);
    
    // If the delegatecall failed, revert the transaction
    require(success, "Delegatecall to swap failed");

    // If the delegatecall was successful, try to decode the result
    RouterType routerType = RouterType(whitelistedRouters[router].routerType);

 
        if (routerType == RouterType.UniswapV2 ) {
            uint[] memory amounts = abi.decode(result, (uint[]));
            amountOut = amounts[amounts.length - 1];
        } else if (routerType == RouterType.UniswapV3 ) {
            amountOut = abi.decode(result, (uint256));
        } else {
            // If we reach here, it's an unsupported router type
            amountOut = 0;
        }
   
    emit SwapSuccessful(msg.sender, amountOut, block.timestamp);
}
    function disable() external onlyOwner {
        _disabled = true;
        emit Disabled();
    }

    function isDisabled() external view returns (bool) {
        return _disabled;
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0) && to != token, "Invalid to");

        uint balance = IERC20(token).balanceOf(address(this));

        if (amount == 0) {
            TransferHelper.safeTransfer(token, to, balance);
        } else {
            require(amount <= balance, "Exceeds balance");
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        if (amount == 0) {
            amount = address(this).balance;
        }
        TransferHelper.safeTransferETH(to, amount);
    }

    receive() external payable {}
}
