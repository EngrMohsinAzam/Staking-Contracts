// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}

/**
 * @title Advanced ERC20 Token with Fees, Blacklist, and Pause
 * @dev Complete implementation matching the provided ABI
 */
contract AdvancedERC20Token {
    using SafeMath for uint256;

    // Token Details
    string private _name;
    string private _symbol;
    uint256 private _decimals;
    uint256 private _totalSupply;

    // Fee Structure
    uint256 public txFee;      // Transaction fee in basis points (e.g., 100 = 1%)
    uint256 public burnFee;    // Burn fee in basis points
    address public FeeAddress; // Address to receive transaction fees

    // Access Control
    address public owner;
    bool public paused;

    // Mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _blacklist;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed from, address indexed to, uint256 value);
    event Burn(address indexed burner, uint256 value);
    event Pause();
    event Unpause();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Blacklist(address indexed blackListed, bool value);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "Address is blacklisted");
        _;
    }

    /**
     * @dev Constructor
     * @param _nameParam Token name
     * @param _symbolParam Token symbol
     * @param _decimalsParam Token decimals
     * @param _supply Initial supply (will be multiplied by 10^decimals)
     * @param _txFee Transaction fee in basis points
     * @param _burnFee Burn fee in basis points
     * @param _FeeAddress Address to receive fees
     * @param tokenOwner Address to receive initial supply
     * @param service Service address (for payment)
     */
    constructor(
        string memory _nameParam,
        string memory _symbolParam,
        uint256 _decimalsParam,
        uint256 _supply,
        uint256 _txFee,
        uint256 _burnFee,
        address _FeeAddress,
        address tokenOwner,
        address payable service
    ) payable {
        require(_FeeAddress != address(0), "Fee address cannot be zero");
        require(tokenOwner != address(0), "Token owner cannot be zero");
        require(_txFee <= 10000, "Transaction fee too high"); // Max 100%
        require(_burnFee <= 10000, "Burn fee too high"); // Max 100%

        _name = _nameParam;
        _symbol = _symbolParam;
        _decimals = _decimalsParam;
        
        // Calculate total supply with decimals
        _totalSupply = _supply.mul(10 ** _decimalsParam);
        
        txFee = _txFee;
        burnFee = _burnFee;
        FeeAddress = _FeeAddress;
        owner = tokenOwner;
        paused = false;

        // Mint initial supply to token owner
        _balances[tokenOwner] = _totalSupply;
        emit Transfer(address(0), tokenOwner, _totalSupply);
        emit Mint(address(0), tokenOwner, _totalSupply);

        // Transfer payment to service address if provided
        if (msg.value > 0 && service != address(0)) {
            service.transfer(msg.value);
        }
    }

    // ============ ERC20 Standard Functions ============

    /**
     * @dev Returns the name of the token
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the decimals of the token
     */
    function decimals() public view returns (uint256) {
        return _decimals;
    }

    /**
     * @dev Returns the total supply of the token
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the balance of an account
     */
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return _balances[_owner];
    }

    /**
     * @dev Returns the allowance of a spender for an owner
     */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return _allowances[_owner][_spender];
    }

    /**
     * @dev Transfer tokens to a specified address
     */
    function transfer(address _to, uint256 _value) 
        public 
        whenNotPaused 
        notBlacklisted(msg.sender) 
        notBlacklisted(_to) 
        returns (bool) 
    {
        require(_to != address(0), "Cannot transfer to zero address");
        require(_value <= _balances[msg.sender], "Insufficient balance");

        // Calculate fees
        (uint256 taxAmount, uint256 burnAmount, uint256 transferAmount) = _calculateFees(_value);

        // Deduct from sender
        _balances[msg.sender] = _balances[msg.sender].sub(_value);

        // Add to recipient (after fees)
        _balances[_to] = _balances[_to].add(transferAmount);

        // Handle transaction fee
        if (taxAmount > 0) {
            _balances[FeeAddress] = _balances[FeeAddress].add(taxAmount);
            emit Transfer(msg.sender, FeeAddress, taxAmount);
        }

        // Handle burn fee
        if (burnAmount > 0) {
            _totalSupply = _totalSupply.sub(burnAmount);
            emit Burn(msg.sender, burnAmount);
            emit Transfer(msg.sender, address(0), burnAmount);
        }

        emit Transfer(msg.sender, _to, transferAmount);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another
     */
    function transferFrom(address _from, address _to, uint256 _value) 
        public 
        whenNotPaused 
        notBlacklisted(_from) 
        notBlacklisted(_to) 
        notBlacklisted(msg.sender)
        returns (bool) 
    {
        require(_to != address(0), "Cannot transfer to zero address");
        require(_value <= _balances[_from], "Insufficient balance");
        require(_value <= _allowances[_from][msg.sender], "Insufficient allowance");

        // Calculate fees
        (uint256 taxAmount, uint256 burnAmount, uint256 transferAmount) = _calculateFees(_value);

        // Update balances
        _balances[_from] = _balances[_from].sub(_value);
        _balances[_to] = _balances[_to].add(transferAmount);
        _allowances[_from][msg.sender] = _allowances[_from][msg.sender].sub(_value);

        // Handle transaction fee
        if (taxAmount > 0) {
            _balances[FeeAddress] = _balances[FeeAddress].add(taxAmount);
            emit Transfer(_from, FeeAddress, taxAmount);
        }

        // Handle burn fee
        if (burnAmount > 0) {
            _totalSupply = _totalSupply.sub(burnAmount);
            emit Burn(_from, burnAmount);
            emit Transfer(_from, address(0), burnAmount);
        }

        emit Transfer(_from, _to, transferAmount);
        return true;
    }

    /**
     * @dev Approve a spender to spend tokens
     */
    function approve(address _spender, uint256 _value) 
        public 
        whenNotPaused 
        returns (bool) 
    {
        require(_spender != address(0), "Cannot approve zero address");
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Increase the allowance for a spender
     */
    function increaseApproval(address _spender, uint256 _addedValue) 
        public 
        whenNotPaused 
        returns (bool success) 
    {
        require(_spender != address(0), "Cannot approve zero address");
        _allowances[msg.sender][_spender] = _allowances[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Decrease the allowance for a spender
     */
    function decreaseApproval(address _spender, uint256 _subtractedValue) 
        public 
        whenNotPaused 
        returns (bool success) 
    {
        require(_spender != address(0), "Cannot approve zero address");
        uint256 oldValue = _allowances[msg.sender][_spender];
        
        if (_subtractedValue >= oldValue) {
            _allowances[msg.sender][_spender] = 0;
        } else {
            _allowances[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    // ============ Owner Functions ============

    /**
     * @dev Mint new tokens (only owner)
     */
    function mint(address account, uint256 amount) 
        public 
        onlyOwner 
        whenNotPaused 
        notBlacklisted(account)
    {
        require(account != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than zero");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);

        emit Mint(address(0), account, amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Burn tokens from caller's account
     */
    function burn(uint256 _value) public whenNotPaused {
        require(_value > 0, "Burn amount must be greater than zero");
        require(_value <= _balances[msg.sender], "Insufficient balance to burn");

        _balances[msg.sender] = _balances[msg.sender].sub(_value);
        _totalSupply = _totalSupply.sub(_value);

        emit Burn(msg.sender, _value);
        emit Transfer(msg.sender, address(0), _value);
    }

    /**
     * @dev Update fee structure (only owner)
     */
    function updateFee(uint256 _txFee, uint256 _burnFee, address _FeeAddress) 
        public 
        onlyOwner 
    {
        require(_FeeAddress != address(0), "Fee address cannot be zero");
        require(_txFee <= 10000, "Transaction fee too high"); // Max 100%
        require(_burnFee <= 10000, "Burn fee too high"); // Max 100%
        require(_txFee.add(_burnFee) <= 10000, "Total fees exceed 100%");

        txFee = _txFee;
        burnFee = _burnFee;
        FeeAddress = _FeeAddress;
    }

    /**
     * @dev Add or remove address from blacklist (only owner)
     */
    function blackListAddress(address listAddress, bool isBlackListed) 
        public 
        onlyOwner 
        returns (bool success) 
    {
        require(listAddress != address(0), "Cannot blacklist zero address");
        require(listAddress != owner, "Cannot blacklist owner");
        
        _blacklist[listAddress] = isBlackListed;
        emit Blacklist(listAddress, isBlackListed);
        return true;
    }

    /**
     * @dev Pause the contract (only owner)
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Pause();
    }

    /**
     * @dev Unpause the contract (only owner)
     */
    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpause();
    }

    /**
     * @dev Transfer ownership (only owner)
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        require(newOwner != owner, "New owner is the same as current owner");
        
        address previousOwner = owner;
        owner = newOwner;
        
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    // ============ Internal Helper Functions ============

    /**
     * @dev Calculate transaction and burn fees
     */
    function _calculateFees(uint256 _value) 
        private 
        view 
        returns (uint256 taxAmount, uint256 burnAmount, uint256 transferAmount) 
    {
        // Calculate tax fee (in basis points, 10000 = 100%)
        taxAmount = _value.mul(txFee).div(10000);
        
        // Calculate burn fee (in basis points)
        burnAmount = _value.mul(burnFee).div(10000);
        
        // Calculate amount to transfer after fees
        transferAmount = _value.sub(taxAmount).sub(burnAmount);
        
        return (taxAmount, burnAmount, transferAmount);
    }

    // ============ View Functions ============

    /**
     * @dev Check if an address is blacklisted
     */
    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }

    /**
     * @dev Fallback function to reject direct ETH transfers
     */
    receive() external payable {
        revert("This contract does not accept direct ETH transfers");
    }

    fallback() external payable {
        revert("This contract does not accept direct ETH transfers");
    }
}