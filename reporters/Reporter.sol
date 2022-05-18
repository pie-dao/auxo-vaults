// SPDX-License-Identifier: MIT
//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.12;
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

interface IVault {
    function balanceOfUnderlying(address user) external view returns (uint256);

    function deposit(address to, uint256 underlyingAmount)
        external
        returns (uint256);
}

interface ILayerZeroEndpoint {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;
}

interface AnyswapRouter {
    function anySwapOutUnderlying(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external;
}

/**
    should this reported also hold the vault share?
    Let's say yes for now
 */
contract Reporter {
    using SafeTransferLib for ERC20;

    //----------
    //  EVENTS
    //----------
    event LogSetOperator(address indexed operator, bool status);

    //----------
    //  VARIABLE
    //----------
    AnyswapRouter private immutable AnyRouter;
    ILayerZeroEndpoint private immutable endpoint;
    IVault public immutable owner;
    mapping(address => bool) public isOperator;
    IVault public immutable vault;
    ERC20 public underlying;
    uint256 public lastUpdated;
    uint256 public interval;
    uint16 public immutable dstChainId;
    address public immutable dstAddr;
    bool isBriding = false;

    constructor(
        ILayerZeroEndpoint _endpoint,
        address _vault,
        uint16 _dstChainId, // Chain ID of the destination chain whete the xVaultStrategy is deployed
        address _dstAddr, // Address of the xVaultStrategy on the destination chain
        address _anyRouter
    ) {
        endpoint = _endpoint;
        owner = msg.sender;
        vault = IVault(_vault);
        underlying = ERC20(vault.underlying());
        dstChainId = _dstChainId;
        dstAddr = _dstAddr;
        AnyRouter = AnyswapRouter(_anyRouter);
    }

    modifier enforceInterval() {
        require(
            block.timestamp > (lastUpdated + interval) || (msg.sender == owner),
            "Report too recent."
        );
        _;
    }

    modifier onlyOperator() {
        require(isOperator[msg.sender], "only operator");
        _;
    }

    modifier notBridging() {
        require(isBriding = false, "Bridging is active");
        _;
    }

    /**
        @dev This function should not be called during the process of exiting the vault and bridging back to the main chain.
     */
    function joinVault() notBridging {
        uint256 totalAmount = underlying.balanceOf(address(this));
        require(totalAmount > 0, "No underlying assets to deposit.");
        underlying.safeApprove(address(vault), totalAmount);
        vault.deposit(address(this), totalAmount);
        report();
    }

    function bridgeBackToStrategy() onlyOperator {
        vault.exitBatchBurn();
        uint256 totalAmount = underlying.balanceOf(address(this));
        require(totalAmount > 0, "No underlying assets to bridge.");
        AnyRouter.anySwapOutUnderlying(
            address(underlying),
            dstAddr,
            totalAmount,
            dstChainId
        );
        isBriding = false;
    }

    function exitVault() onlyOperator {
        uint256 totalAmount = underlying.balanceOf(address(this));
        vault.enterBatchBurn(totalAmount);
    }

    function withdraw() external {
        require(msg.sender == owner);
        uint256 amount = address(this).balance;

        // Owner has to be payable
        (bool success, ) = owner.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    /// @dev called by anyone, including public task manager like gelato
    function report() public {
        require(
            address(this).balance > 0,
            "the balance of this contract is 0. pls send gas for message fees"
        );

        // encode the payload with the amount in vault
        bytes memory payload = abi.encode(
            uint32(block.timestamp),
            vault.balanceOfUnderlying(address(this))
        );

        // get the fees we need to pay to LayerZero for message delivery
        (uint256 messageFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            payload,
            false,
            adapterParams
        );
        require(
            address(this).balance >= messageFee,
            "address(this).balance < messageFee. fund this contract with more ether"
        );

        // send LayerZero message
        lzEndpoint.send{value: messageFee}(
            dstChainId,
            abi.encodePacked(dstAddr),
            payload,
            payable(this),
            address(0x0),
            bytes("")
        );

        lastUpdated = block.timestamp;
    }

    //----------
    //  ADMIN
    //----------
    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
        emit LogSetOperator(operator, status);
    }

    function setBridging(bool status) external onlyOwner {
        isBriding = status;
    }

    fallback() external payable {}

    receive() external payable {}
}
