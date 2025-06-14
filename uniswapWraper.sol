// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
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
}

interface IUniswapV2Router {

    function swapExactETHForTokens(
        uint amountOutMin, address[] calldata path, address to, uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
    ) external returns (uint[] memory amounts);

}

interface IUniswapV2RouterSupportingFeeOnTransfer {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFavorToken {
    function logBuy(address user, uint amount) external;
}

interface IERC20 {
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
}

contract FavorRouterWrapper is Ownable {
    IUniswapV2Router public uniswapRouter;
    mapping(address => bool) public isFavorToken;

    event FavorTokenAdded(address indexed token);
    event FavorTokenRemoved(address indexed token);
    event RouterUpdated(address indexed router);

    constructor(address _router) {
        require(_router != address(0), "Router cannot be zero address");
        uniswapRouter = IUniswapV2Router(_router);
    }

    // --- Favor Token Management ---
    function addFavorToken(address token) external onlyOwner {
        require(token != address(0), "Zero address not allowed");
        isFavorToken[token] = true;
        emit FavorTokenAdded(token);
    }

    function removeFavorToken(address token) external onlyOwner {
        require(isFavorToken[token], "Token not registered");
        delete isFavorToken[token];
        emit FavorTokenRemoved(token);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        uniswapRouter = IUniswapV2Router(_router);
        emit RouterUpdated(_router);
    }

    // --- Buy Wrappers ---
    function swapETHForFavorAndTrackBonus(
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external payable {
        address finalToken = path[path.length - 1];
        require(isFavorToken[finalToken], "Path must end in registered FAVOR");

        uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: msg.value}(
            amountOutMin, path, to, block.timestamp + 900
        );

        uint favorAmount = amounts[amounts.length - 1];
        IFavorToken(finalToken).logBuy(to, favorAmount);
    }

    function swapExactTokensForFavorAndTrackBonus(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external {
        address finalToken = path[path.length - 1];
        require(isFavorToken[finalToken], "Path must end in registered FAVOR");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);

        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amountIn, amountOutMin, path, to, block.timestamp + 900
        );

        uint favorAmount = amounts[amounts.length - 1];
        IFavorToken(finalToken).logBuy(to, favorAmount);
    }

    // --- Sell Wrappers ---
    function swapExactFavorForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external {
        require(isFavorToken[path[0]], "Path must start with registered FAVOR");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);

     IUniswapV2RouterSupportingFeeOnTransfer(address(uniswapRouter))
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            block.timestamp + 900
        );
    }

    function swapExactFavorForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external {
        require(isFavorToken[path[0]], "Path must start with registered FAVOR");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);
     
     IUniswapV2RouterSupportingFeeOnTransfer(address(uniswapRouter))
        .swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            block.timestamp + 900
        );
    }

    receive() external payable {}
}
