# 고객 중심 가디언 시스템 (Customer-Centric Guardian System)

ERC721 기반의 소셜 복구 기능이 구현된 SBT(Soul-Bound Token) 스마트 계약입니다.

이 프로젝트는 키를 분실했을 때 지정된 '가디언' 네트워크의 승인을 통해 자산을 복구할 수 있는 SBT 시스템을 제공합니다. SBT는 기본적으로 전송이 불가능하지만, 이 계약은 정해진 복구 절차를 통해서만 소유권 이전을 허용합니다.

이 프로젝트는 **Hardhat v3** 및 **ethers v6** 환경으로 구성되어 있습니다.

## 핵심 개념

이 시스템은 세 가지 주요 역할로 구성됩니다:

1.  **Customer (고객):** SBT를 소유한 사용자입니다. 각 고객은 자신의 계정을 복구해 줄 가디언 그룹을 가집니다.
2.  **Manager (관리자):** 시스템의 특수 관리자입니다. 신규 고객을 등록하고, 복구 요청을 승인/거부할 수 있는 강력한 권한을 가집니다.
3.  **Guardian (가디언):** 고객의 SBT 복구를 승인해 줄 수 있는 주소입니다. 이 시스템에서 가디언은 \*\*관리자(Manager)\*\*와 \*\*다른 고객(Customer)\*\*들로 구성됩니다.

## 주요 기능 (Features)

  * **SBT (Soul-Bound Token):** `_beforeTokenTransfer` 훅을 사용하여 평상시에는 `transfer`가 불가능하며, 오직 `_finalizeRecovery`를 통해서만 전송됩니다.
  * **소셜 복구 (Social Recovery):** 키를 분실한 고객(`_lostAddress`)은 새 주소(`msg.sender`)로 복구를 요청할 수 있습니다.
  * **M-of-N 승인:**
      * 총 가디언 중 **`requiredApprovals` (현재 3)명 이상의 승인**이 필요합니다.
      * 안정성을 위해, 승인자 중 \*\*최소 1명은 반드시 매니저(MANAGER\_1 또는 MANAGER\_2)\*\*여야 합니다.
  * **관리자 거부권 (Veto):** `MANAGER_COUNT` (현재 2)명의 매니저가 모두 거부하면 해당 복구 요청은 즉시 실패합니다.
  * **가디언 관리:** 고객은 자신의 가디언(고객 가디언)이 비활성화될 경우 다른 고객으로 직접 교체할 수 있습니다. (`replaceInactiveGuardian`)
  * **고객 온보딩:** 관리자만 신규 고객을 시스템에 추가할 수 있습니다. (`addCustomer`)

## 핵심 복구 워크플로우

1.  **복구 요청 (Request):** 새로운 주소 B가 분실한 주소 A의 복구를 `requestRecovery(A)` 함수로 요청합니다.
2.  **승인 (Approve):** A의 가디언(매니저 및 다른 고객)들이 `approveRecovery(A)`를 호출하여 요청을 승인합니다.
3.  **거부 (Reject):** 매니저가 `rejectRecovery(A)`를 호출하여 요청을 거부할 수 있습니다.
4.  **복구 실행 (Finalize):**
      * **성공:** (승인 수 \>= 3) **그리고** (매니저 승인자 \>= 1) 조건을 만족하면, A의 SBT가 B에게 전송됩니다.
      * **실패:** (거부 수 \>= 2) 조건을 만족하면, 복구 요청이 실패하고 종료됩니다.

-----

## 시작하기 (Getting Started)

이 프로젝트를 로컬 환경에서 설정하고 Sepolia 테스트넷에 배포 및 테스트하는 방법입니다.

### 1\. 사전 준비

  * [Node.js](https://nodejs.org/) (v18 or higher)
  * [Git](https://git-scm.com/)

### 2\. 설치

1.  저장소 복제 및 폴더 이동:

    ```bash
    git clone https://github.com/Mustree/Customer_Centric_Guardian_System.git
    cd Customer_Centric_Guardian_System
    ```

2.  의존성 설치 (Hardhat, ethers v6 포함):

    ```bash
    npm install
    ```

### 3\. 환경 변수 설정

프로젝트 루트에 `.env.example` 파일을 복사하여 `.env` 파일을 생성합니다.

```bash
cp .env.example .env
```

`.env` 파일은 **배포**와 **시나리오 테스트**에 모두 사용됩니다. **모든** 값을 본인의 환경에 맞게 채워야 합니다. 모든 계정은 가스비를 위해 Sepolia ETH를 보유해야 합니다.

```ini
# .env.example (수정된 시나리오 기준)

# --- 공통 설정 ---
# Alchemy 또는 Infura의 Sepolia RPC URL
SEPOLIA_RPC_URL="https."

# --- 1. 배포 스크립트 (deploy.ts) 용 ---
# 계약 배포자(Owner)의 비공개 키
PRIVATE_KEY="YOUR_DEPLOYER_OWNER_PRIVATE_KEY"

# 계약 생성자에 전달될 매니저 주소 3개
MANAGER_ADDRESS_1="0xManager1Address"
MANAGER_ADDRESS_2="0xManager2Address"
MANAGER_ADDRESS_3="0xManager3Address"

# 계약 생성자에 전달될 "초기 고객" 3명 (가디언 역할)
# 3명을 쉼표로 구분하여 입력
INITIAL_CUSTOMER_LIST="0xGuardian1Address,0xGuardian2Address,0xGuardian3Address"

# --- 2. 시나리오 스크립트 (runRecoveryScenario_5Guardians.ts) 용 ---
# 위 Manager 주소 1의 비공개 키
MANAGER_1_PRIVATE_KEY="YOUR_MANAGER_1_PRIVATE_KEY"

# 위 INITIAL_CUSTOMER_LIST 중 승인에 사용할 고객 2명의 비공개 키
CUSTOMER_GUARDIAN_1_KEY="KEY_FOR_0xGuardian1Address"
CUSTOMER_GUARDIAN_2_KEY="KEY_FOR_0xGuardian2Address"

# '분실 계정' (새로 추가할 고객)의 "주소" (키 필요 없음)
LOST_ACCOUNT_ADDRESS="0xYourLostAccountAddress" 

# '새 계정'(복구자)의 "비공개 키" (addCustomer 및 requestRecovery 서명용)
NEW_ACCOUNT_KEY="YOUR_NEW_ACCOUNT_PRIVATE_KEY"
```

-----

## 사용법 (Usage)

### 1\. 컴파일

스마트 계약을 컴파일합니다.

```bash
npx hardhat compile
```

### 2\. 테스트

*(현재 `test/` 폴더에 테스트 파일이 없습니다. 향후 추가될 수 있습니다.)*

```bash
npx hardhat test
```

### 3\. 계약 배포 (Sepolia)

`.env` 파일에 **(1) 배포 스크립트 용** 변수들(`PRIVATE_KEY`, `MANAGER_ADDRESS_1/2/3`, `INITIAL_CUSTOMER_LIST`)이 올바르게 입력되었는지 확인합니다.

`INITIAL_CUSTOMER_LIST`에 가디언 역할을 할 3명의 고객 주소를 입력했는지 확인한 후, 배포 스크립트를 실행합니다.

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

배포에 성공하면 터미널에 **배포된 계약 주소**가 출력됩니다. 이 주소를 복사하여 다음 단계에서 사용합니다.

### 4\. 복구 시나리오 실행 (Sepolia)

`scripts/runRecoveryScenario_5Guardians.ts` 스크립트를 사용하여 Sepolia 테스트넷에서 전체 복구 흐름을 테스트합니다.

1.  **계약 주소 설정:** `scripts/runRecoveryScenario_5Guardians.ts` 파일을 엽니다.
    상단의 `DEPLOYED_CONTRACT_ADDRESS` 변수 값을 \*\*(3)\*\*에서 복사한 **새로운 계약 주소**로 수정합니다.

2.  **.env 파일 확인:** `.env` 파일에 **(2) 시나리오 스크립트 용** 변수들(`MANAGER_1_PRIVATE_KEY`, `CUSTOMER_GUARDIAN_1_KEY`, `CUSTOMER_GUARDIAN_2_KEY`, `LOST_ACCOUNT_ADDRESS`, `NEW_ACCOUNT_KEY`)이 모두 올바르게 입력되었는지 확인합니다.

3.  **시나리오 실행:**

    ```bash
    npx hardhat run scripts/runRecoveryScenario_5Guardians.ts --network sepolia
    ```

    스크립트가 실행되면 `addCustomer` (Lost/New 계정), SBT 민팅, 복구 요청, 가디언 승인(고객 2명, 매니저 1명), 최종 소유권 이전까지의 과정이 터미널에 순차적으로 출력됩니다.

-----

## 라이선스 (License)

이 프로젝트는 [MIT] 라이선스를 따릅니다.