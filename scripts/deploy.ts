// scripts/deploy.ts (Hardhat v3 + ethers v6 방식)

import hre from "hardhat"; // 1. hre에서 'artifacts'를 가져오기 위해 import
import "dotenv/config";    // 2. .env 파일 로드
import { ethers } from "ethers"; // 3. 'hardhat'이 아닌 'ethers'에서 직접 import

async function main() {
  // --- 1. .env에서 설정값 읽기 ---
  const {
    PRIVATE_KEY,
    SEPOLIA_RPC_URL,
    MANAGER_ADDRESS_1,
    MANAGER_ADDRESS_2,
    MANAGER_ADDRESS_3,
    INITIAL_CUSTOMER_LIST,
  } = process.env;

  // --- 2. 필수 값 검증 ---
  if (!PRIVATE_KEY || !SEPOLIA_RPC_URL) {
    throw new Error("Missing PRIVATE_KEY or SEPOLIA_RPC_URL in .env file");
  }
  if (
    !MANAGER_ADDRESS_1 ||
    !MANAGER_ADDRESS_2 ||
    !MANAGER_ADDRESS_3 ||
    !INITIAL_CUSTOMER_LIST
  ) {
    throw new Error("Missing deployment configuration in .env file");
  }

  // --- 3. ethers 수동 설정 (v3 방식) ---
  // Sepolia 네트워크 제공자(Provider) 설정
  const provider = new ethers.JsonRpcProvider(SEPOLIA_RPC_URL);
  // .env의 비공개 키로 지갑(Signer) 설정
  const signer = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log(`Deploying contracts with the account: ${signer.address}`);

  // --- 4. HRE에서 아티팩트(ABI, Bytecode) 가져오기 ---

  const artifact = await hre.artifacts.readArtifact(
    "CustomerCentricGuardianSystem"
  );

  // --- 5. Ethers ContractFactory 생성 ---
  const ContractFactory = new ethers.ContractFactory(
    artifact.abi,
    artifact.bytecode,
    signer // 배포자(signer) 연결
  );

  // --- 6. 배포 인자(Constructor Arguments) 준비 ---
  const managers: string[] = [
    MANAGER_ADDRESS_1,
    MANAGER_ADDRESS_2,
    MANAGER_ADDRESS_3,
  ];
  
  const initialCustomers: string[] = INITIAL_CUSTOMER_LIST
    .split(',')
    .map(addr => addr.trim());

  const requiredApprovals = 3;

  console.log("Deploying CustomerCentricGuardianSystem with:");
  console.log("- Managers:", managers);
  console.log("- Initial Customers:", initialCustomers);

  // --- 7. 배포 ---
  const guardianSystem = await ContractFactory.deploy(
    initialCustomers,
    managers,
    requiredApprovals
  );

  await guardianSystem.waitForDeployment();
  
  // (ethers v6에서는 .target 대신 await .getAddress() 사용)
  console.log(
    `✅ CustomerCentricGuardianSystem deployed to: ${await guardianSystem.getAddress()}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});