// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/IOwnable.sol";

// 계약에서 사용하는 Struct 정의 (인터페이스 파일 최상단)
struct Customer {
    address customerAddress;
    address[] guardians;
}

struct RecoveryAttempt {
    address newOwner;
    uint256 nonce;
    bool active;
}

/**
 * @title ICustomerCentricGuardianSystem
 * @dev CustomerCentricGuardianSystem 계약의 외부 인터페이스
 */
interface ICustomerCentricGuardianSystem is IERC721, IOwnable {
    // --- Events ---
    event CustomerAdded(address indexed customer, address[] guardians);
    event GuardianReplaced(address indexed customer, address indexed oldGuardian, address indexed newGuardian);
    event RecoveryRequested(address indexed lostAddress, address indexed newOwner, uint256 nonce);
    event ManagerRejected(address indexed lostAddress, address indexed approver, uint256 nonce);
    event GuardianApproved(address indexed lostAddress, address indexed approver, uint256 nonce);
    event SBTRecovered(address indexed lostAddress, address indexed newOwner);
    event SBTRecoveryFailed(address indexed lostAddress);

    // --- State Variable Getters ---
    
    // Struct Getters
    function customers(address _customer) external view returns (address customerAddress);
    function recoveryRequests(address _lostAddress) external view returns (address newOwner, uint256 nonce, bool active);

    // Mapping Getters
    function isCustomer(address _customer) external view returns (bool);
    function managers(address _manager) external view returns (bool);
    function sbtTokenId(address _owner) external view returns (uint256);
    function approvalNonces(address _lostAddress, address _guardian) external view returns (uint256);
    function rejectNonces(address _lostAddress, address _manager) external view returns (uint256);
    function approvalCounts(address _lostAddress) external view returns (uint256);
    function rejectCounts(address _lostAddress) external view returns (uint256);

    // Array Getter
    function customerList(uint256 _index) external view returns (address);

    // Public Constant Getters
    function MANAGER_1() external view returns (address);
    function MANAGER_2() external view returns (address);
    function MANAGER_3() external view returns (address);
    function CUSTOMER_GUARDIAN_COUNT() external view returns (uint8);
    function MANAGER_COUNT() external view returns (uint8);
    function requiredApprovals() external view returns (uint8);

    // --- External Functions ---
    
    function mint(address to, uint256 tokenId) external;
    
    function requestRecovery(address _lostAddress) external;
    
    function addCustomer(address _newCustomer) external;
    
    function approveRecovery(address _lostAddress) external;
    
    function rejectRecovery(address _lostAddress) external;
    
    function replaceInactiveGuardian(address _oldGuardian, address _newGuardian) external;
    
    function isGuardianFor(address _guardian, address _customer) external view returns (bool);
}