// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomerCentricGuardianSystem is ERC721, Ownable{

    
    struct Customer {
        address customerAddress;
        address[] guardians;
    }


    mapping(address => Customer) public customers; 
    mapping(address => bool) public isCustomer;
    mapping(address => bool) public managers; 
    
    address[] public customerList;
    
    address public constant MANAGER_1 = 0x9002aF6489E76980528B790BB1114Cb0D842fE47; // replace with your address
    address public constant MANAGER_2 = 0x78aA20900Ba03A0c39Fc4019A3384D675bff1eEa; // replace with your address
    address public constant MANAGER_3 = 0xbDf2036Dc0E0a992bF7716E54fE6EAdb6B5F2D8D; // replace with your address, only for initial customer
    uint8 public constant CUSTOMER_GUARDIAN_COUNT = 3;
    uint8 public constant MANAGER_COUNT = 2;
    uint8 public requiredApprovals;
    
    
    
    // 2. SBT 토큰 ID 관리 (주소당 1개의 SBT만 가정)
    // 소유자 주소 => 토큰 ID
    mapping(address => uint256) public sbtTokenId;
    // 3. 복구 시도 정보
    struct RecoveryAttempt {
        address newOwner; // 복구를 요청한 새 주소
        uint256 nonce;    // 복구 시도 ID (새 요청 시 증가)
        bool active;      // 현재 진행중인 요청인지 여부
    }
    // 분실한 주소 => 현재 진행중인 복구 시도
    mapping(address => RecoveryAttempt) public recoveryRequests;
    // This new mapping replaces the flawed `guardianApprovals` boolean mapping.
    
    // 4. 복구 승인 상태
    // 분실한 주소 => 가디언 => 마지막으로 승인한 nonce
    mapping(address => mapping(address => uint256)) public approvalNonces;
    // 분실한 주소 => 매니저 주소 => 마지막으로 거절한 nonce
    mapping(address => mapping(address => uint256)) public rejectNonces;
    // 분실한 주소 => 현재 nonce에 대한 승인 수
    mapping(address => uint256) public approvalCounts;
    // 분실한 주소 => 현재 nonce에 대한 거절 수
    mapping(address => uint256) public rejectCounts;
    
    

    // 6. 복구 중 전송을 임시로 허용하기 위한 플래그
    bool internal _isRecovering;

    event CustomerAdded(address indexed customer, address[] guardians);      
    event GuardianReplaced(address indexed customer, address indexed oldGuardian, address indexed newGuardian);
    


    event RecoveryRequested(address indexed lostAddress, address indexed newOwner, uint256 nonce);
    event ManagerRejected(address indexed lostAddress, address indexed approver, uint256 nonce);
    event GuardianApproved(address indexed lostAddress, address indexed approver, uint256 nonce);
    event SBTRecovered(address indexed lostAddress,address indexed newOwner);
    event SBTRecoveryFailed(address indexed lostAddress);
    
    
    modifier onlyCustomer() {
        require(isCustomer[msg.sender], "Caller is not a registered customer.");
        _;
    }

    modifier onlyManager() {
        require(managers[msg.sender], "Only managers can perform this action.");
        _;
    }



    // 이니셜 커스터머 3명 아래로.
    constructor(address[] memory _initialCustomers, uint8 _requiredApprovals) ERC721("RecoverableSBT", "RSBT") {
        require(_initialCustomers.length > 0, "Must provide at least one initial customer.");
        require(_requiredApprovals == 3, "Required approvals must be 3 for a 5-guardian system.");

        managers[MANAGER_1] = true;
        managers[MANAGER_2] = true;
        managers[MANAGER_3] = true;
        requiredApprovals = _requiredApprovals;

        address[] memory initialGuardians = new address[](MANAGER_COUNT + 1);
        initialGuardians[0] = MANAGER_1;
        initialGuardians[1] = MANAGER_2;
        initialGuardians[2] = MANAGER_3;

        for (uint i = 0; i < _initialCustomers.length; i++) {
            address customerAddr = _initialCustomers[i];
            if (!isCustomer[customerAddr]) {
                isCustomer[customerAddr] = true;
                customers[customerAddr] = Customer({ customerAddress: customerAddr, guardians: initialGuardians });
                customerList.push(customerAddr);
                emit CustomerAdded(customerAddr, initialGuardians);
            }
        }
    }

    // --- SBT 핵심 로직 (전송 방지) ---

    /**
     * @dev 토큰 전송을 막습니다. (SBT의 핵심)
     * _isRecovering 플래그가 true일 때(즉, executeRecovery 함수 호출 시)만 전송을 허용합니다.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        // 1. 복구 중인 경우, 전송 허용
        if (_isRecovering) {
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
            return;
        }

        // 2. 민팅(발행)인 경우, 허용
        if (from == address(0)) {
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
            return;
        }

        // 3. 그 외 모든 경우 (소각 포함) 전송/소각 금지
        revert("SBT: Non-transferable");
    }
    // --- SBT 발행 (테스트용) ---
    
    function mint(address to, uint256 tokenId) public onlyOwner {
        _mint(to, tokenId);
        sbtTokenId[to] = tokenId;
    }

    function requestRecovery(address _lostAddress) external {
        uint256 tokenId = sbtTokenId[_lostAddress];
        require(_exists(tokenId), "No SBT found for lost address");
        require(ownerOf(tokenId) == _lostAddress, "Address mismatch");
        
        
        RecoveryAttempt storage attempt = recoveryRequests[_lostAddress];
        
        // 새로운 주소(msg.sender)로 새 복구 요청 시작
        attempt.newOwner = msg.sender;
        attempt.active = true;
        // nonce를 증가시켜 이전 승인들을 무효화
        attempt.nonce++; 
        
        // 새 nonce에 대한 승인 수 초기화
        approvalCounts[_lostAddress] = 0;
        rejectCounts[_lostAddress] = 0;
        emit RecoveryRequested(_lostAddress, msg.sender, attempt.nonce);
    }

  

    // 고객 추가
    function addCustomer(address _newCustomer) external onlyManager {
        require(!isCustomer[_newCustomer], "Customer already exists.");

        uint totalCustomers = customerList.length;
        address[] memory newGuardians = new address[](MANAGER_COUNT + CUSTOMER_GUARDIAN_COUNT);
        if(totalCustomers<3){
            newGuardians[0] = MANAGER_1;
            newGuardians[1] = MANAGER_2;
            newGuardians[2] = MANAGER_3;
            isCustomer[_newCustomer] = true;
            customers[_newCustomer].customerAddress = _newCustomer;
            customers[_newCustomer].guardians = newGuardians;
            customerList.push(_newCustomer);
            emit CustomerAdded(_newCustomer, newGuardians);
        }
        else{
        newGuardians[0] = MANAGER_1;
        newGuardians[1] = MANAGER_2;
        uint customerGuardiansAssigned = 0;
        for (uint i = totalCustomers; i > 0 && customerGuardiansAssigned < CUSTOMER_GUARDIAN_COUNT; i--) {
            newGuardians[MANAGER_COUNT + customerGuardiansAssigned] = customerList[i - 1];
            customerGuardiansAssigned++;
        }
        
        isCustomer[_newCustomer] = true;
        customers[_newCustomer].customerAddress = _newCustomer;
        customers[_newCustomer].guardians = newGuardians;
        customerList.push(_newCustomer);

        emit CustomerAdded(_newCustomer, newGuardians);
        }
    }

   

    // 가디언이 복구요청을 승인하는 함수 이걸 뼈대로 가자잉...
    function approveRecovery(address _lostAddress) external {
        RecoveryAttempt storage attempt = recoveryRequests[_lostAddress];
        uint256 currentNonce = attempt.nonce;
        require(attempt.active, "No recovery in progress");
        require(isGuardianFor(msg.sender, _lostAddress), "Caller is not a guardian for this customer.");
        
        
        // 현재 nonce에 대해 이미 승인했는지 확인
        require(
            approvalNonces[_lostAddress][msg.sender] != currentNonce,
            "Already approved this request"
        );
        // 승인 기록
        approvalNonces[_lostAddress][msg.sender] = currentNonce;
        approvalCounts[_lostAddress]++;

        emit GuardianApproved(_lostAddress, msg.sender, currentNonce);


        // 필요 승인 횟수 이상 승인 되면 sbt 복구 함수를 호출한다, 그리고 매니저가 적어도 한명 승인을 해야함
        if ((approvalCounts[_lostAddress] >= requiredApprovals) && (approvalNonces[_lostAddress][MANAGER_1] == currentNonce || approvalNonces[_lostAddress][MANAGER_2] == currentNonce )) {
            _finalizeRecovery(_lostAddress, true);
        }
    }
    // 매니저의 복구요청 거절 함수
    function rejectRecovery(address _lostAddress) external onlyManager {
        RecoveryAttempt storage attempt = recoveryRequests[_lostAddress];
        require(attempt.active, "No recovery in progress");
        uint256 currentNonce = attempt.nonce;
        
        // 현재 nonce에 대해 이미 거절했는지 확인
        require(
            rejectNonces[_lostAddress][msg.sender] != currentNonce,
            "Already approved this request"
        );

        // 거절 기록
        rejectNonces[_lostAddress][msg.sender] = currentNonce;
        rejectCounts[_lostAddress]++;

        emit ManagerRejected(_lostAddress, msg.sender, currentNonce);


       
        // 매니저 2명이 복구를 거절하면 sbt 복구요청은 실패한다
        if (rejectCounts[_lostAddress] >= MANAGER_COUNT) {
            _finalizeRecovery(_lostAddress, false);
        }
    }
    
    //고객이 자신의 불활성 가디언을 변경하는 함수
    function replaceInactiveGuardian(address _oldGuardian, address _newGuardian) external onlyCustomer {
        require(isGuardianFor(_oldGuardian, msg.sender), "Old guardian is not a guardian for you.");
        require(isCustomer[_newGuardian], "New guardian must be a registered customer.");
        require(!isGuardianFor(_newGuardian, msg.sender), "New guardian is already one of your guardians.");

        address[] storage guardians = customers[msg.sender].guardians;
        for (uint i = 0; i < guardians.length; i++) {
            if (guardians[i] == _oldGuardian) {
                guardians[i] = _newGuardian;
                emit GuardianReplaced(msg.sender, _oldGuardian, _newGuardian);
                return;
            }
        }
        revert("Guardian replacement failed.");
    }

    // 특정 고객의 가디언인지 여부 확인
    function isGuardianFor(address _guardian, address _customer) public view returns (bool) {
        if (!isCustomer[_customer]) return false;

        address[] memory guardians = customers[_customer].guardians;
        for (uint i = 0; i < guardians.length; i++) {
            if (guardians[i] == _guardian) {
                return true;
            }
        }
        return false;
    }


    // sbt 복구, 복구 실패
    function _finalizeRecovery(address _lostAddress, bool _success) internal {
        RecoveryAttempt storage attempt = recoveryRequests[_lostAddress];

        if (_success) {
            uint256 tokenId = sbtTokenId[_lostAddress];
            address newOwner = attempt.newOwner;

            // 1. 복구 플래그 활성화
            _isRecovering = true;

            // 2. ERC721의 _transfer 실행 (SBT 전송)
            // _beforeTokenTransfer 훅에서 _isRecovering 플래그를 확인하고 통과시킴
            _transfer(_lostAddress, newOwner, tokenId);

            // 3. 복구 플래그 비활성화
            _isRecovering = false;

            // 4. 상태 변수 정리
            delete sbtTokenId[_lostAddress];
            sbtTokenId[newOwner] = tokenId;

            // 복구 요청 정보 초기화
            delete recoveryRequests[_lostAddress];
            delete approvalCounts[_lostAddress];
            delete rejectCounts[_lostAddress];
            emit SBTRecovered(_lostAddress, newOwner);
        } else {
            // 복구 시도 비활성화
            attempt.active = false;
            attempt.newOwner = address(0);
            
            
            approvalCounts[_lostAddress] = 0; // 승인 수 초기화

            emit SBTRecoveryFailed(_lostAddress);
        }
    }
}