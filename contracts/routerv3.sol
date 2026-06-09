// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IPancakeV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);
    
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);
    
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
    
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface IPancakeV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
    
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface INFTDescriptor {
    function tokenURI(address positionManager, uint256 tokenId) external view returns (string memory);
}

interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract NonfungiblePositionManager is ERC721Enumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Structs
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    // Events
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );

    // State variables
    address public immutable deployer;
    address public immutable factory;
    address public immutable WETH9;
    address private immutable _tokenDescriptor;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    mapping(uint256 => Position) private _positions;
    mapping(address => uint256) private _nonces;
    uint256 private _nextId = 1;

    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction too old");
        _;
    }

    constructor(
        address _deployer,
        address _factory,
        address _WETH9,
        address _tokenDescriptor_
    ) ERC721("Pancake V3 Positions NFT", "CAKE-V3-POS") {
        deployer = _deployer;
        factory = _factory;
        WETH9 = _WETH9;
        _tokenDescriptor = _tokenDescriptor_;
        
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    receive() external payable {
        require(msg.sender == WETH9, "Not WETH9");
    }

    // View functions
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _CACHED_CHAIN_ID
            ? _CACHED_DOMAIN_SEPARATOR
            : _buildDomainSeparator();
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function baseURI() public pure returns (string memory) {
        return "";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Invalid token ID");
        return INFTDescriptor(_tokenDescriptor).tokenURI(address(this), tokenId);
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    // Pool management
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool) {
        require(token0 < token1, "Invalid token order");
        
        pool = IPancakeV3Factory(factory).getPool(token0, token1, fee);
        
        if (pool == address(0)) {
            pool = IPancakeV3Factory(factory).createPool(token0, token1, fee);
            IPancakeV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            // Try to initialize, will revert if already initialized
            try IPancakeV3Pool(pool).initialize(sqrtPriceX96) {} catch {}
        }
    }

    // Mint new position
    function mint(MintParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(params.token0 < params.token1, "Invalid token order");
        
        address pool = IPancakeV3Factory(factory).getPool(
            params.token0,
            params.token1,
            params.fee
        );
        require(pool != address(0), "Pool does not exist");

        tokenId = _nextId++;
        _mint(params.recipient, tokenId);

        bytes memory data = abi.encode(
            MintCallbackData({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                payer: msg.sender
            })
        );

        (amount0, amount1) = IPancakeV3Pool(pool).mint(
            address(this),
            params.tickLower,
            params.tickUpper,
            uint128(params.amount0Desired + params.amount1Desired), // Simplified
            data
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    struct MintCallbackData {
        address token0;
        address token1;
        uint24 fee;
        address payer;
    }

    function pancakeV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        
        address pool = IPancakeV3Factory(factory).getPool(
            decoded.token0,
            decoded.token1,
            decoded.fee
        );
        require(msg.sender == pool, "Invalid callback caller");

        if (amount0Owed > 0) {
            pay(decoded.token0, decoded.payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            pay(decoded.token1, decoded.payer, msg.sender, amount1Owed);
        }
    }

    // Increase liquidity
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(ownerOf(params.tokenId) != address(0), "Invalid token ID");
        Position storage position = _positions[params.tokenId];

        address pool = IPancakeV3Factory(factory).getPool(
            position.token0,
            position.token1,
            position.fee
        );

        bytes memory data = abi.encode(
            MintCallbackData({
                token0: position.token0,
                token1: position.token1,
                fee: position.fee,
                payer: msg.sender
            })
        );

        (amount0, amount1) = IPancakeV3Pool(pool).mint(
            address(this),
            position.tickLower,
            position.tickUpper,
            liquidity,
            data
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");

        position.liquidity += liquidity;

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    // Decrease liquidity
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        address owner = ownerOf(params.tokenId);
        require(owner == msg.sender || getApproved(params.tokenId) == msg.sender || isApprovedForAll(owner, msg.sender), "Not approved");
        
        Position storage position = _positions[params.tokenId];
        require(position.liquidity >= params.liquidity, "Insufficient liquidity");

        address pool = IPancakeV3Factory(factory).getPool(
            position.token0,
            position.token1,
            position.fee
        );

        (amount0, amount1) = IPancakeV3Pool(pool).burn(
            position.tickLower,
            position.tickUpper,
            params.liquidity
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");

        position.liquidity -= params.liquidity;
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    // Collect fees
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        address owner = ownerOf(params.tokenId);
        require(owner == msg.sender || getApproved(params.tokenId) == msg.sender || isApprovedForAll(owner, msg.sender), "Not approved");
        
        Position storage position = _positions[params.tokenId];

        address pool = IPancakeV3Factory(factory).getPool(
            position.token0,
            position.token1,
            position.fee
        );

        (uint128 collected0, uint128 collected1) = IPancakeV3Pool(pool).collect(
            params.recipient,
            position.tickLower,
            position.tickUpper,
            params.amount0Max,
            params.amount1Max
        );

        amount0 = collected0;
        amount1 = collected1;

        if (amount0 > 0) {
            position.tokensOwed0 -= uint128(amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= uint128(amount1);
        }

        emit Collect(params.tokenId, params.recipient, amount0, amount1);
    }

    // Burn NFT
    function burn(uint256 tokenId) external payable {
        address owner = ownerOf(tokenId);
        require(owner == msg.sender || getApproved(tokenId) == msg.sender || isApprovedForAll(owner, msg.sender), "Not approved");
        
        Position storage position = _positions[tokenId];
        require(position.liquidity == 0, "Liquidity not zero");
        require(position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Tokens owed");

        delete _positions[tokenId];
        _burn(tokenId);
    }

    // Permit
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        require(block.timestamp <= deadline, "Permit expired");
        
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, spender, tokenId, _nonces[ownerOf(tokenId)]++, deadline)
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash)
        );

        address recoveredOwner = ecrecover(hash, v, r, s);
        address tokenOwner = ownerOf(tokenId);
        require(recoveredOwner != address(0) && recoveredOwner == tokenOwner, "Invalid signature");

        _approve(spender, tokenId, tokenOwner);
    }

    // Helper functions for token transfers
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            IWETH9(WETH9).deposit{value: value}();
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            IERC20(token).safeTransfer(recipient, value);
        } else {
            IERC20(token).safeTransferFrom(payer, recipient, value);
        }
    }

    function refundETH() external payable {
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable {
        uint256 balance = IWETH9(WETH9).balanceOf(address(this));
        require(balance >= amountMinimum, "Insufficient WETH9");

        if (balance > 0) {
            IWETH9(WETH9).withdraw(balance);
            payable(recipient).transfer(balance);
        }
    }

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amountMinimum, "Insufficient token");

        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
        }
    }

    // Self permit functions
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function selfPermitIfNecessary(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        if (allowance < value) {
            try IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
        }
    }

    function selfPermitAllowed(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
    }

    function selfPermitAllowedIfNecessary(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        if (allowance < type(uint256).max) {
            try IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s) {} catch {}
        }
    }

    // Multicall
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall failed");
            results[i] = result;
        }
    }
}