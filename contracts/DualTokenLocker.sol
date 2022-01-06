// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface ITokenLocker {
    struct BatchInput {
        uint256[] _seasonIDs;
        uint256[] _indexs;
        address account;
        uint256[] _dorAmounts;
        uint256[] _goldAmounts;
        uint32[] proofLengths;
        bytes32[] _merkleProofs;
    }

    function unlock(uint256 _seasonID,
        uint256 _index,
        address _account,
        uint256 _dorAmount,
        uint256 _goldAmount,
        bytes32[] calldata _merkleProof) external;

    function decreaseBalance(address account, uint256 amount) external;

    function decreaseGoldBalance(address account, uint256 amount) external;

    event UnLock(uint256 seasonID, address indexed to, uint256 dorValue, uint256 goldValue);
    event BatchUnLock(uint256[] seasonIDs, address indexed to, uint256 dorValue, uint256 goldValue);
    event UserDeposit(address user, uint256 dorAmount, uint256 goldAmount);
    event UserWithdraw(address user, uint256 dorAmount, uint256 goldAmount);
    event UserSpent(address user, uint256 dorAmount, uint256 goldAmount);
}

contract DualTokenLocker is ITokenLocker, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    IERC20 public DOR;
    IERC20 public GOLD;

    mapping(uint256 => uint256) public startReleaseTimestamps;
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(uint256 => mapping(address => uint8)) private claimed;

    mapping(address => uint256) public lastClaimed;

    mapping(address => uint256) public balances;

    mapping(address => bool) isOperator;

    uint256 firstApplyTaxTimestamp;

    mapping(address => uint256) public goldBalances;

    uint256 constant lockDuration = 1 hours;

    modifier checkLock(address account) {
        uint256 lastUnlock = lastClaimed[account];
        if (lastUnlock == 0) {
            lastUnlock = firstApplyTaxTimestamp;
        }
        require(block.timestamp > lastUnlock + lockDuration, "still locked");
        _;
    }

    modifier onlyOperator {
        require(isOperator[msg.sender], "Only operator");
        _;
    }

    /**
     * @notice initialize the bridge
     */
    function initialize(address _dorToken, address _goldToken) 
    external
    initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        DOR = IERC20(_dorToken);
        GOLD = IERC20(_goldToken);
    }

    function addSeason(
        uint256 _seasonID, 
        uint256 _startReleaseTimestamp, 
        bytes32 _merkleRoot
    ) public onlyOwner {
        startReleaseTimestamps[_seasonID] = _startReleaseTimestamp;
        merkleRoots[_seasonID] = _merkleRoot;
    }

    function getClaimStatus(
        address userAddress,
        uint256[] memory seasonIDs
    ) public view returns (uint8[] memory) {
        uint8[] memory claimStatus = new uint8[](seasonIDs.length);
        for (uint256 index = 0; index < seasonIDs.length; index++) {
            claimStatus[index] = claimed[seasonIDs[index]][userAddress];
        }
        return claimStatus;
    }

    function setTaxTimestamp(uint256 timestamp) onlyOwner public {
        firstApplyTaxTimestamp = timestamp;
    }

    function unlock(
        uint256 _seasonID,
        uint256 _index,
        address _account,
        uint256 _dorAmount,
        uint256 _goldAmount,
        bytes32[] calldata _merkleProof
    ) external override checkLock(_account) nonReentrant whenNotPaused {
        uint256 startReleaseTimestamp = startReleaseTimestamps[_seasonID];
        require(block.timestamp > startReleaseTimestamp, "still locked");
        require(claimed[_seasonID][_account] == 0, "Claimed once");
        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(_index, _account, _dorAmount, _goldAmount));
        require(
            MerkleProof.verify(_merkleProof, merkleRoots[_seasonID], node),
            "MerkleDistributor: Invalid proof."
        );
        
        require(_dorAmount + _goldAmount > 0, "zero unlock");
        uint256 dorAmount = _dorAmount;
        dorAmount = dorAmount.add(balances[_account]);
        DOR.transfer(_account, applyTax(_account, dorAmount));
        GOLD.transfer(_account, _goldAmount.add(goldBalances[_account]));
        balances[_account] = 0;
        goldBalances[_account] = 0;
        claimed[_seasonID][_account] = 1;
        lastClaimed[_account] = block.timestamp;
        emit UnLock(_seasonID, _account, _dorAmount, _goldAmount);
    }

    function batchUnlock(
        BatchInput calldata input
    ) external checkLock(input.account) nonReentrant whenNotPaused {
        uint256 dorAmount = 0;
        uint256 goldAmount = 0;
        uint128 startIndex = 0;
        for (uint256 i = 0; i < input._seasonIDs.length; i++) {
            {
                require(block.timestamp > startReleaseTimestamps[input._seasonIDs[i]], "still locked");
                require(claimed[input._seasonIDs[i]][input.account] == 0, "Claimed once");
            }
            
            // Verify the merkle proof.
            require(
                MerkleProof.verify(
                    getMerkleProofWithIndex(
                        input._merkleProofs, 
                        startIndex, 
                        input.proofLengths[i]
                    ), 
                    getMerkleRoot(input._seasonIDs, i), 
                    keccak256(abi.encodePacked(
                        input._indexs[i], 
                        input.account, 
                        input._dorAmounts[i], 
                        input._goldAmounts[i]
                    ))
                ),
                "MerkleDistributor: Invalid proof."
            );

            {
                startIndex = startIndex + input.proofLengths[i];
                claimed[input._seasonIDs[i]][input.account] = 1;
                dorAmount = dorAmount.add(input._dorAmounts[i]);
                goldAmount = goldAmount.add(input._goldAmounts[i]);
            }
        }

        dorAmount = dorAmount.add(balances[input.account]);
        goldAmount = goldAmount.add(goldBalances[input.account]);
        balances[input.account] = 0;
        goldBalances[input.account] = 0;
        require(dorAmount + goldAmount > 0, "zero unlock");
        DOR.transfer(input.account, applyTax(input.account, dorAmount));
        GOLD.transfer(input.account, goldAmount);
        lastClaimed[input.account] = block.timestamp;
        emit BatchUnLock(input._seasonIDs, input.account, dorAmount, goldAmount);
    }

    function getMerkleRoot(uint256[] memory _seasonIDs, uint256 i) internal view returns (bytes32) {
        return merkleRoots[_seasonIDs[i]];
    }

    function activate(
        uint256[] memory _seasonIDs,
        uint256[] memory _indexs,
        address account,
        uint256[] memory _dorAmounts,
        uint256[] memory _goldAmounts,
        uint32[] memory proofLengths,
        bytes32[] calldata _merkleProofs
    ) external nonReentrant whenNotPaused {
        uint256 dorAmount = 0;
        uint256 goldAmount = 0;
        uint128 startIndex = 0;
        for (uint256 i = 0; i < _seasonIDs.length; i++) {
            require(block.timestamp > startReleaseTimestamps[_seasonIDs[i]], "still locked");
            require(claimed[_seasonIDs[i]][account] == 0, "Claimed once");
            // Verify the merkle proof.
            require(
                MerkleProof.verify(
                    getMerkleProofWithIndex(
                        _merkleProofs, 
                        startIndex, 
                        proofLengths[i]
                    ), 
                    merkleRoots[_seasonIDs[i]], 
                    keccak256(abi.encodePacked(
                        _indexs[i], 
                        account, 
                        _dorAmounts[i], 
                        _goldAmounts[i]
                    ))
                ),
                "MerkleDistributor: Invalid proof."
            );
            startIndex = startIndex+proofLengths[i];
            claimed[_seasonIDs[i]][account] = 1;
            dorAmount = dorAmount.add(_dorAmounts[i]);
            goldAmount = goldAmount.add(_goldAmounts[i]);
        }
        require(dorAmount + goldAmount > 0, "zero unlock");
        balances[account] = balances[account].add(dorAmount);
        goldBalances[account] = balances[account].add(dorAmount);
        emit BatchUnLock(_seasonIDs, account, dorAmount, goldAmount);
    }

    function withdraw(address account) external checkLock(account) nonReentrant whenNotPaused {
        uint256 dorAmount = balances[account];
        uint256 goldAmount = goldBalances[account];
        balances[account] = 0;
        DOR.transfer(account, applyTax(account, dorAmount));
        GOLD.transfer(account, goldAmount);
        goldBalances[account] = 0;
        lastClaimed[account] = block.timestamp;
        emit UserWithdraw(account, dorAmount, goldAmount);
    }

    function deposit(address account, uint256 amount) external nonReentrant whenNotPaused {
        DOR.transferFrom(account, address(this), amount);
        balances[account] = balances[account].add(amount);
        emit UserDeposit(account, amount, 0);
    }

    function decreaseBalance(address account, uint256 amount) external override onlyOperator {
        balances[account] = balances[account].sub(amount);
    }

    function depositGold(address account, uint256 amount) external nonReentrant whenNotPaused {
        GOLD.transferFrom(account, address(this), amount);
        goldBalances[account] = goldBalances[account].add(amount);
        emit UserDeposit(account, 0, amount);
    }

    function decreaseBalanceGold(address account, uint256 amount) external onlyOperator {
        goldBalances[account] = goldBalances[account].sub(amount);
    }

    function getMerkleProofWithIndex(bytes32[] calldata _merkleProofs, uint128 startIndex, uint32 length) public view returns (bytes32[] calldata) {
        return _merkleProofs[startIndex:startIndex+length];
    }

    function updateRoot(uint256 _seasonID, bytes32 _merkleRoot) external onlyOwner {
        merkleRoots[_seasonID] = _merkleRoot;
    }

    function emergencyWithdraw(IERC20 _token, uint256 _amount)
        external
        onlyOwner
    {
        _safeTransfer(_token, owner(), _amount);
    }

    function _safeTransfer(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) internal {
        if (_token == IERC20(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "transfer failed");
        } else {
            _token.transfer(_to, _amount);
        }
    }

    function applyTax(address account, uint256 amount) internal view returns (uint256) {
        uint256 lastUnlock = lastClaimed[account];
        if (lastUnlock == 0) {
            lastUnlock = firstApplyTaxTimestamp;
        }
        if (block.timestamp > lastUnlock.add(18 hours)) {
            return amount.mul(98).div(100);
        }
        uint256 numOfDay = block.timestamp.sub(lastUnlock.add(lockDuration)).div(1 hours);
        return amount.mul(numOfDay.mul(2).add(100).sub(36)).div(100);
    }

    function pause() 
    onlyOwner 
    public {
        _pause();
    }

    function unpause()
    onlyOwner
    public {
        _unpause();
    }
}