// scripts/runRecoveryScenario_5Guardians.ts
// (시나리오: 초기 고객 3명 배포 -> Lost/New 계정 추가 -> 2 C + 1 M 승인)
import { ethers } from "ethers";
import hre from "hardhat";
import "dotenv/config";

// -----------------------------------------------------------------
// ⚠️ 여기에 deploy.ts로 "새로" 배포한 계약 주소를 붙여넣으세요!
const DEPLOYED_CONTRACT_ADDRESS = "0x...";
// -----------------------------------------------------------------

// .env 파일에서 모든 키와 URL을 읽어옵니다.
const {
  SEPOLIA_RPC_URL,
  PRIVATE_KEY, // Deployer(Owner)
  MANAGER_1_PRIVATE_KEY,
  CUSTOMER_GUARDIAN_1_KEY, // 초기 고객 (가디언 역할)
  CUSTOMER_GUARDIAN_2_KEY, // 초기 고객 (가디언 역할)
  LOST_ACCOUNT_ADDRESS,    // 분실 계정 (주소만)
  NEW_ACCOUNT_KEY,         // 복구 받을 새 계정 (키 필요)
} = process.env;

// 헬퍼 함수: 트랜잭션 전송 및 대기
async function sendTx(txPromise: Promise<ethers.ContractTransactionResponse>, name: string) {
  try {
    const tx = await txPromise;
    console.log(`${name} tx sent: ${tx.hash}`);
    await tx.wait();
    console.log(`${name} tx confirmed.`);
    return tx;
  } catch (e: any) {
    if (e.message.includes("Customer already exists") || e.message.includes("token already minted")) {
      console.log(`${name} failed: Already completed. Skipping.`);
    } else {
      console.error(`Error during ${name}:`, e.message);
      throw e;
    }
  }
}


async function main() {
  console.log("Sepolia 5-Guardian (2 Customer + 1 Manager) Sceanrio Started...");

  // --- 1. 필수 변수 검증 ---
  if (DEPLOYED_CONTRACT_ADDRESS === "0x...") {
    throw new Error("DEPLOYED_CONTRACT_ADDRESS를 실제 배포된 주소로 변경해주세요.");
  }
  if (
    !SEPOLIA_RPC_URL ||
    !PRIVATE_KEY ||
    !MANAGER_1_PRIVATE_KEY ||
    !CUSTOMER_GUARDIAN_1_KEY ||
    !CUSTOMER_GUARDIAN_2_KEY ||
    !LOST_ACCOUNT_ADDRESS ||
    !NEW_ACCOUNT_KEY
  ) {
    throw new Error("스크립트에 필요한 5개의 KEY와 1개의 ADDRESS가 .env 파일에 없습니다.");
  }

  // --- 2. Provider 및 Signer(지갑) 설정 ---
  const provider = new ethers.JsonRpcProvider(SEPOLIA_RPC_URL);

  const deployerSigner = new ethers.Wallet(PRIVATE_KEY, provider);
  const manager1Signer = new ethers.Wallet(MANAGER_1_PRIVATE_KEY, provider);
  const guardian1Signer = new ethers.Wallet(CUSTOMER_GUARDIAN_1_KEY, provider);
  const guardian2Signer = new ethers.Wallet(CUSTOMER_GUARDIAN_2_KEY, provider);
  const newAccountSigner = new ethers.Wallet(NEW_ACCOUNT_KEY, provider);
  const lostAddress = LOST_ACCOUNT_ADDRESS;
  
  console.log("Signers (Accounts) Loaded:");
  console.log("- Deployer (Owner):", deployerSigner.address);
  console.log("- Manager 1:", manager1Signer.address);
  console.log("- Customer Guardian 1 (Initial):", guardian1Signer.address);
  console.log("- Customer Guardian 2 (Initial):", guardian2Signer.address);
  console.log("- Lost Account (Address Only):", lostAddress);
  console.log("- New Account (Recoverer):", newAccountSigner.address);

  // --- 3. 배포된 컨트랙트 인스턴스 생성 ---
  const artifact = await hre.artifacts.readArtifact("CustomerCentricGuardianSystem");
  const contract = new ethers.Contract(
    DEPLOYED_CONTRACT_ADDRESS,
    artifact.abi,
    provider
  );
  console.log(`\nConnecting to contract at: ${await contract.getAddress()}`);

  // --- 4. 시나리오 준비: 4번째, 5번째 고객 추가 ---
  console.log(`\n--- PREPARING NEW CUSTOMERS ---`);
  
  // 4번째 고객 (LostAccount) 추가.
  await sendTx(
    contract.connect(manager1Signer).addCustomer(lostAddress),
    "Add Customer (Lost Account)"
  );

  // 5번째 고객 (NewAccount) 추가.
  await sendTx(
    contract.connect(manager1Signer).addCustomer(newAccountSigner.address),
    "Add Customer (New Account)"
  );
  console.log("New customers setup complete.");

  // --- 5. SBT 민팅 (시나리오 준비) ---
  const tokenId = 1; 
  console.log(`\n--- MINTING SBT ---`);
  
  // mint()는 onlyOwner이므로 deployerSigner가 호출
  await sendTx(
    contract.connect(deployerSigner).mint(lostAddress, tokenId),
    `Mint SBT (ID: ${tokenId})`
  );

  const initialOwner = await contract.ownerOf(tokenId);
  console.log(`SBT (ID: ${tokenId}) minted.`);
  
  // [수정 1] EIP-55 체크섬 문제 해결 (모두 소문자로 비교)
  if (initialOwner.toLowerCase() !== lostAddress.toLowerCase()) {
    throw new Error(
      `SBT 민팅 실패 또는 소유자 불일치. 
       Expected (from .env): ${lostAddress.toLowerCase()}
       Got (from Contract): ${initialOwner.toLowerCase()}`
    );
  }

  // --- 6. 복구 시나리오 시작: 1단계 (복구 요청) ---
  console.log(`\n--- STARTING RECOVERY SCENARIO ---`);
  console.log(`New Account (${newAccountSigner.address}) is requesting recovery for Lost Account (${lostAddress})...`);

  // "New Account"가 "Lost Account" 주소를 인자로 넣어 복구를 요청
  await sendTx(
    contract.connect(newAccountSigner).requestRecovery(lostAddress),
    "Request Recovery"
  );
  
  const request = await contract.recoveryRequests(lostAddress);
  console.log(`Recovery requested. Current Nonce: ${request.nonce}`);
  
  // --- 7. 복구 시나리오: 2단계 (가디언 승인) ---
  console.log(`\n--- GUARDIAN APPROVALS ---`);

  // 승인 1: 고객 가디언 1 (LostAccount의 가디언임)
  console.log(`Approving (Customer Guardian 1: ${guardian1Signer.address})...`);
  await sendTx(
    contract.connect(guardian1Signer).approveRecovery(lostAddress),
    "Approve (Guardian 1)"
  );

  // 승인 2: 고객 가디언 2 (LostAccount의 가디언임)
  console.log(`Approving (Customer Guardian 2: ${guardian2Signer.address})...`);
  await sendTx(
    contract.connect(guardian2Signer).approveRecovery(lostAddress),
    "Approve (Guardian 2)"
  );

  let ownerCheck = await contract.ownerOf(tokenId);
  console.log(`Owner check (before final approval): ${ownerCheck}`);
  
  // [수정 2] EIP-55 체크섬 문제 해결 (모두 소문자로 비교)
  if (ownerCheck.toLowerCase() !== lostAddress.toLowerCase()) {
     throw new Error("SBT가 너무 일찍 전송되었습니다!");
  }

  // 승인 3: 매니저 1 (LostAccount의 가디언임)
  console.log(`Approving (Manager 1: ${manager1Signer.address})... (This should trigger final recovery)`);
  await sendTx(
    contract.connect(manager1Signer).approveRecovery(lostAddress),
    "Approve (Manager 1)"
  );
  console.log("Manager 1 approved. Recovery should be complete.");

  // --- 8. 복구 시나리오: 3단계 (결과 검증) ---
  console.log(`\n--- VERIFYING RECOVERY ---`);
  console.log("Waiting 5 seconds for chain update...");
  await new Promise(resolve => setTimeout(resolve, 5000)); 

  const finalOwner = await contract.ownerOf(tokenId);
  
  console.log(`Final owner of Token ID ${tokenId}: ${finalOwner}`);

  // [수정 3] EIP-55 체크섬 문제 해결 (양쪽 모두 소문자로 비교)
  if (finalOwner.toLowerCase() === newAccountSigner.address.toLowerCase()) {
    console.log("SUCCESS: SBT has been successfully recovered by 2 Customers and 1 Manager.");
  } else {
    console.error(`FAILED: SBT owner is still ${finalOwner}.`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});