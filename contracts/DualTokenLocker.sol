// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface ITokenLocker {
    function unlock(uint256 _seasonID,
        uint256 _index,
        address _account,
        uint256 _dorAmount,
        uint256 _goldAmount,
        bytes32[] calldata _merkleProof) external;

    event UnLock(uint256 seasonID, address indexed to, uint256 dorValue, uint256 goldValue);
    event BatchUnLock(uint256[] seasonIDs, address indexed to, uint256 dorValue, uint256 goldValue);
}

contract DualTokenLocker is ITokenLocker, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    IERC20 public DOR;
    IERC20 public GOLD;

    mapping(uint256 => uint256) public startReleaseTimestamps;
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(uint256 => mapping(address => uint8)) private claimed;

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

    function unlock(
        uint256 _seasonID,
        uint256 _index,
        address _account,
        uint256 _dorAmount,
        uint256 _goldAmount,
        bytes32[] calldata _merkleProof
    ) external override nonReentrant whenNotPaused {
        uint256 startReleaseTimestamp = startReleaseTimestamps[_seasonID];
        require(block.timestamp > startReleaseTimestamp, "still locked");
        require(claimed[_seasonID][_account] == 0, "Claimed once");
        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(_index, _account, _dorAmount, _goldAmount));
        require(
            MerkleProof.verify(_merkleProof, merkleRoots[_seasonID], node),
            "MerkleDistributor: Invalid proof."
        );
        
        _unlock(_seasonID, _account, _dorAmount, _goldAmount);
    }

    event Debug(uint256 index, bytes32[] proof);

    function batchUnlock(
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
        DOR.transfer(account, dorAmount);
        GOLD.transfer(account, goldAmount);
        emit BatchUnLock(_seasonIDs, account, dorAmount, goldAmount);
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

    function _unlock(uint256 _seasonID, address _account, uint256 _dorAmount, uint256 _goldAmount) internal {
        require(_dorAmount + _goldAmount > 0, "zero unlock");
        DOR.transfer(_account, _dorAmount);
        GOLD.transfer(_account, _goldAmount);
        claimed[_seasonID][_account] = 1;
        emit UnLock(_seasonID, _account, _dorAmount, _goldAmount);
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